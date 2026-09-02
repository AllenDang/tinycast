# Hotkeys (in-house, zero dependencies)

`Features/HotKeys/` holds:

- `KeyShortcut` — Sendable model, Carbon keycode + modifiers, layout-aware glyphs via `UCKeyTranslate`.
- `HotKeyBinding` — what an action is actually bound to: a `.combo(KeyShortcut)` or a
  `.doubleTap(DoubleTapModifier)`.
- `HotKeyCenter` — the Carbon `RegisterEventHotKey` layer, pausable.
- `EscapeComboProbe` — a second, narrower Carbon registration the recorder uses to catch a modified ⎋
  (see below).
- `DoubleTapModifier` / `DoubleTapDetector` / `DoubleTapMonitor` — the double-tap stack.

`HotKeyBindings` owns them all: persistence, conflict lookup, and dispatch. Every action reads and
writes one `HotKeyBinding`, so the two kinds share persistence, conflict detection, the recorder and
the keycap rendering — only the _engine_ differs.

## Persistence

Bindings persist as JSON strings under stable, app-owned `hotkey.<action>` UserDefaults keys. The set
of bound bundle IDs lives in `boundAppBundleIDs` and is re-registered on launch. System Settings panes
use `boundPaneBundleIDs`; custom commands and quicklinks use their stable UUIDs in
`boundCustomCommandIDs` and `boundQuicklinkIDs`. Those two are the per-item case — unlike a fixed
catalog, there is no `allCases` to walk — so each needs an index for `start()` to re-register from
and to prune bindings whose record was deleted while Tinycast wasn't running. That prune is why
`QuicklinkStore` loads at launch even when the feature is off
(see [quicklinks.md](quicklinks.md#hotkeys)).

`HotKeyBinding` synthesizes `Codable`: both `.combo(KeyShortcut)` and
`.doubleTap(DoubleTapModifier)` round-trip through the same current format. The same values are stored
by `SettingsBackup.HotkeyBackup`, so export and import within one build use one representation.

System actions and window commands are the fixed-catalog case. Their stable keys are
`hotkey.systemAction.<raw-id>` and `hotkey.windowCommand.<raw-id>`, and they need no bound-ID index:
`start()` and `conflictOwner` iterate `allCases`, and `register` ignores an unbound item. A registered
window-command shortcut still does nothing while the feature switch is off because
`AppCore.runWindowCommand` re-checks it. System actions route through `SystemActionCoordinator`, so the
confirmation gate applies equally to hotkeys and palette activation.

## Double-tap modifiers

Any action can instead be bound to a **double-tapped lone modifier** — ⌃, ⌥, ⇧ or ⌘. Carbon cannot
register a modifier-only shortcut at all, so this is a separate engine that meets the combo path only
at `HotKeyBinding`.

`DoubleTapDetector` is the recognizer: Foundation-only, pure, and clock-injected (`now` is a caller-
supplied monotonic timestamp), so `Tools/hotkey-test.swift` drives it without an event tap. A **tap**
is a press that starts from no modifiers held, keeps exactly one of the four held with no `fn`
alongside, sees no key press or mouse click, and is released within `maxHold` (250 ms — the same
window `HyperKeyTap` calls a quick press). A **double-tap** is a second tap of the same modifier
starting within `maxGap` (300 ms) of the first one's release.

Only _momentary_ keys may feed `hasOtherModifiers`. Caps Lock must not: `maskAlphaShift` tracks the
**latch**, not a press, so testing it would disqualify every tap for as long as Caps Lock is on and
silently kill the feature. Caps Lock is still ineligible as a _binding_ — that is what the Hyper Key
is for.

It **fires on the second release, not the second press**. The modifier is then already up when the
action runs, so the palette never opens with a phantom ⌘ held and focus restoration isn't polluted —
and "double-tap and hold" is a deliberate non-event.

`DoubleTapMonitor` is the one platform file. It is a **listen-only** `CGEventTap` and it installs only
while something is actually bound to a double-tap, so users who never use the feature pay nothing. Two
details are load-bearing:

- It is `.tailAppendEventTap`, unlike the two head-inserted taps, so it observes events **after**
  `HyperKeyTap`'s rewrite. A Hyper-remapped right-side modifier therefore arrives as the full ⌃⌥⇧⌘
  chord and correctly reads as "not a lone modifier" — the left-side twin still double-taps.
- Like every keyboard tap it needs the **Accessibility** grant, and it never prompts for it. The
  binding records regardless; the recorder shows an inline warning that opens System Settings, and the
  one-second health timer installs the tap the moment the grant lands.

⇧ is bindable this way even though `KeyShortcut` rejects a bare ⇧ combo: a double-_tap_ is unambiguous
where a bare ⇧ combo would shadow typing.

## Recorder

The settings recorder (`Features/HotKeys/UI/ShortcutRecorder.swift`) is deliberately **not** a focusable
control: the active recorder is `HotKeyBindings.recordingAction` state, and keys are captured by local
NSEvent monitors while both engines are paused. It records both kinds — type a combo, or double-tap a
modifier — by feeding its `.flagsChanged` / `.keyDown` monitors into the _same_ `DoubleTapDetector`
the global monitor uses, so recording needs no event tap and no permission.

Setting `recordingAction` is what starts and stops the capture, so there is exactly **one**
`ShortcutCaptureSession` (`Features/HotKeys/Service/`) for the app rather than one per row — which lets the
callout above the field render the live state from outside the row that opened it. The field itself
only ever shows the binding; the prompt, the live preview and the conflict message all live in the
callout. See [ui.md](ui.md#the-shortcut-recorder-callout).

### The ⎋-with-a-modifier swallow

The WindowServer swallows a modified ⎋ (⌘⎋, ⌥⎋, …) before it ever becomes a normal key event — the
same swallow ⌘⇥ and ⌘Space get, confirmed empirically: neither `NSEvent.addLocalMonitorForEvents` nor
`addGlobalMonitorForEvents` ever see a keyDown for it, while a bare ⎋ or any other modified key
delivers normally. `ShortcutCaptureSession`'s NSEvent monitors are therefore blind to it — recording
⌘⎋ would otherwise just sit at "Listening…" forever.

`EscapeComboProbe` works around it: Carbon's hotkey table sits below that swallow (`RegisterEventHotKey`
both accepts and fires a modified ⎋, verified the same way), so the capture session keeps a probe
registered for exactly ⎋ + whatever modifiers `heldModifiers` currently reports, re-registering on every
`flagsChanged`. A fire routes through the same `KeyShortcut` validation and `commit` as a normal keyDown,
so a swallowed combo can still lose a conflict check or fail the "commanding modifier" rule like any
other. This is the same Carbon mechanism `HotKeyCenter` already uses for real bindings, so it costs the
recorder no new event tap and no permission prompt — a bare ⎋ still cancels through the ordinary keyDown
path, since that one is never swallowed.

One hazard the probe itself creates: it must release its own registration _before_ the real one takes
over the same chord. `commit` unregisters the probe right before `setBinding`/`recordingAction = nil`,
which is what makes `HotKeyCenter` reactivate every entry including the one just captured — Carbon
refuses a second `RegisterEventHotKey` for the identical keycode+modifiers even under a different id
(`eventHotKeyExistsErr`, verified directly), so a probe left registered a moment too long would make
the binding save successfully (UserDefaults, the recorder's keycaps) while silently never firing.
