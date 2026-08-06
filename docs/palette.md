# Palette

The command palette is a borderless floating `NSPanel` hosting SwiftUI; see
[architecture.md](architecture.md) for window ownership.

## State flow

`PaletteViewModel` (mode / query / selection / `focusToken`) is the bridge between the panel and
`AppCore`. Showing the palette calls `prepare(mode:)`, which resets state and bumps `focusToken` (a
UUID) so the SwiftUI search field re-focuses. `RootPaletteView` switches its content on `mode`:

- `.launcher` → `LauncherList`
- `.clipboard` → `ClipboardList` + preview
- `.calculatorHistory` → `CalculatorHistoryList`
- `.uninstall` → `UninstallList` (see [uninstall.md](uninstall.md))
- `.quicklinks` → `QuicklinkList`
- `.quicklinkArguments` → `QuicklinkArgumentsView` (see [quicklinks.md](quicklinks.md#the-argument-prompt))

Clipboard and Calculator History are sub-screens reached from the launcher (Tab, a command, or a
hotkey) and back out to it. Uninstall is one too, but reached only from a launcher app's Actions menu
and scoped to that app; like Calculator History it stays out of the Tab cycle. So do both Quicklinks
screens.

The argument screen is the one mode where the search field is not a search field: it _is_ the current
argument's input, so its placeholder names that argument and ↵ submits rather than activating a row.
Its own state lives on `AppCore.quicklinkArguments`, the way `.uninstall`'s target lives on
`UninstallSession`, and leaving the mode cancels the pending open. A bare backspace steps back an
argument before it falls through to the usual exit-to-launcher.

The flat `selection` index is the single source of truth for highlight / activation and **must always
match the visible row order**, including the inline calculator card at index 0 when present (see
[calculator.md](calculator.md)).

## Window placement

`PaletteWindowController` resolves an anchor (left edge + top edge) **once per summon** and reuses it
for every compact↔expanded resize, so only the height changes and the top edge never drifts. The
anchor is dropped on hide, so the next summon re-resolves for wherever the user is then.

Which display it anchors to depends on the **Follow the cursor across displays** setting
(`AppSettings.openOnCursorScreen`, on by default):

- **On** — the screen holding `NSEvent.mouseLocation`, i.e. the display under the pointer.
- **Off** — `NSScreen.main`.

`NSScreen.main` alone can't implement the follow-the-cursor case: it is documented as the _key window's_
screen, and an accessory app driving a non-activating panel has no key window on the display the user is
looking at, so `main` resolves to the menu-bar display regardless of where the pointer is.

The hit test is `NSMouseInRect(mouse, screen.frame, false)`, **not** `CGRect.contains`. A mouse location
is the CoreGraphics cursor position flipped about the primary display's height, so a screen's rows land
in the half-open interval `(minY, maxY]`: the topmost row is exactly `maxY`, which `contains` excludes,
while that same value is the `minY` of the display stacked above. `contains` would therefore hand a
pointer parked at the top of one display to its neighbour. `NSMouseInRect` exists for precisely this.

## The placeholder is Tinycast's, not the field's

The search field is a SwiftUI `TextField` with **no `prompt`**; `RootPaletteView` draws the
placeholder itself as a leading-aligned background `Text`.

AppKit gives an `NSTextField` a field editor one point taller than the field (measured: a 24pt editor
in a 23pt field), and a `prompt` is rendered by whichever of the cell and the editor currently owns
the text. The same placeholder glyphs therefore sit **one point higher** once the field takes the
panel's shared field editor. That editor is created lazily and then cached on the window for its
lifetime, so the step was only ever visible on the first summon after launch — and only where the eye
could track it, when the outgoing and incoming placeholders share a leading word.

Drawing it in SwiftUI pins it to the layout instead: measured ink is identical in both focus states,
against a two-backing-pixel step for the real prompt. It is a **background**, not an overlay, so the
caret still draws over it, and it carries `allowsHitTesting(false)` so clicking the placeholder still
lands the caret. `PaletteMode.placeholder` is still the one source of the strings; the field takes an
explicit `accessibilityLabel` because the prompt used to supply it.

This is the same class of bug as the freeze below — both come from the cell/field-editor swap.

### An IME candidate is visible before `query` ever sees it

SwiftUI's `TextField` binding does not update while an IME candidate is only *marked* — typing Pinyin
shows the romanization and, once a candidate is chosen, the character — so `vm.query` stays empty for
the entire composing gesture and only changes on commit. A placeholder gated on `query.isEmpty` alone
would sit on top of the marked text the whole time the user is composing, and only vanish once they'd
already picked a candidate.

`PalettePanel.sendEvent` is the fix: it already sees every keyDown before dispatch and again lets it
through to `super.sendEvent`, which is what drives `NSTextInputContext` and therefore the field
editor's marked text for that keystroke. Reading `(firstResponder as? NSTextView)?.hasMarkedText()`
right after that call catches the update synchronously and mirrors it into `PaletteViewModel.isComposing`
— a tracked property, unlike `menuOpen`, since this one has to drive a re-render. The placeholder checks
`query.isEmpty && !isComposing`; a bare backspace's "empty query navigates back a screen" check gets the
same guard in the other direction, since backspace while composing must delete from the marked text
instead. Nothing else keyed off `query.isEmpty` (search filtering, the compact↔expanded swap) needed the
same fix — waiting for a commit before either fires is correct there, the way Spotlight does.

`NSText.didChangeNotification` looked like the obvious hook and isn't one: it does not fire for
`setMarkedText` at all, only for a committed `insertText` (checked directly against `NSTextView`,
not inferred) — which is exactly why the SwiftUI binding it presumably backs stays silent too.

## Search field input freeze

Two situations leave the search field mounted and focused with nothing useful for typing to do, and
both read as inert without **ever resigning first responder** — resigning makes the `NSTextField`
swap between its field-editor and cell rendering, shifting the text / placeholder a point or two, so
focus stays put:

- A footer popover menu (⌘K Actions / app menu) is open — the field is a search field, but the menu
  owns the keyboard.
- The palette is showing `.aiCommand` — `AICommandSession.begin` already captured the query that
  matched the command as its `input` before the request went out, so editing the field afterwards
  (loading or answered) would change what's on screen without changing what the request already ran
  on (see [ai-commands.md](ai-commands.md#the-screen-loading--answer-never-mid-keystroke)).

Input is frozen instead:

- `RootPaletteView` mirrors `showActions || showAppMenu || vm.mode == .aiCommand` into
  `PaletteViewModel.searchFieldFrozen`, whose `didSet` fires `onSearchFieldFrozenChanged`.
- `PalettePanel.sendEvent` then swallows text-editing keystrokes while `searchFieldFrozen` (letting
  ⌘/⌥ chords and menu-nav keys — also needed by `.aiCommand`'s own ↵/Esc — through to SwiftUI
  `onKeyPress`).
- The caret is hidden by clearing SwiftUI's **own** live field editor's `insertionPointColor`. SwiftUI
  force-casts its field editor to a private subclass, so vending a custom one crashes — only the
  existing one can be tuned.

## Focus restoration (load-bearing)

`PaletteWindowController` records `previousApp` (the frontmost app) on show. Paste then targets that
app:

- `Paster.paste` activates it and posts a synthetic ⌘V via `CGEvent`.
- `Paster.pasteInPlace` posts ⌘V straight to the app's PID _without_ activating it, so the palette can
  stay open and frontmost (used by "paste keeping window open").

Both require the Accessibility permission (`Permissions.ensureAccessibility()`).

The same show also mirrors that app into `PaletteViewModel.pasteTarget` (a `PasteTarget`: localized
name + bundle path), so Clipboard and Emoji can name it — the footer pill reads "Paste to Notes" and
the ⌘K paste rows carry the app's icon. Resolved once per summon, never per render, and deliberately
not cleared by `prepare` (pop-to-root resets the screen, not the target).
