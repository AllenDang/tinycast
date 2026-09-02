# Phase 26 — Fix the Core dependency inversions

**Milestone:** M4 · **Effort:** M · **Risk:** Med · **Context:** Med

---

## Overview

Break the three documented `Core/` reaches into `AppCore.shared`, plus the omitted Backup reach,
by injecting exactly what each feature needs.

## Why this phase exists

The intended direction is `Features → AppCore → stores → pure core`. Four dependency clusters invert it:

| Site                                   | Reaches for                                  | Why it is a problem                                                 |
| -------------------------------------- | -------------------------------------------- | ------------------------------------------------------------------- |
| `HotKeyManager.displayName` (4 refs)   | `appIndex`, `customCommands`, `quicklinks`   | You cannot understand `HotKeyManager` without three other stores    |
| `KeyShortcut.collapsedModifierSymbols` | `settings.hyperKey`, `hyperKeyReplacesGlyph` | A pure-ish formatting helper depends on global app state            |
| `SystemActionRunner` async completion  | `AppCore.shared.presentSystemActionFailure`  | Bends the documented "runner owns effects, `AppCore` owns UI" split |
| Backup gather/apply and UI flows       | stores, replacement methods and dialogs      | Serialization and import orchestration actively locate the composition root |

None is a type-level cycle, but each is a cycle in reasoning — and each blocks the file from ever being
harness-reachable.

## Architecture Review reference

**§2.3 Dependency direction** · Roadmap W5.7

## Objectives

1. `HotKeyManager.displayName` takes a name-resolver closure, injected at wiring time.
2. `KeyShortcut.collapsedModifierSymbols` takes the Hyper display preference as parameters.
3. `SystemActionRunner` reports its async failure through an injected callback.
4. A feature-owned `BackupCoordinator` receives stores, replacement closures and dialog closures once;
   `SettingsBackup` receives a concrete dependency context and `BackupActions` stays stateless.

## Expected files to modify

| File                                     | Change                                                    |
| ---------------------------------------- | --------------------------------------------------------- |
| `Tinycast/Core/HotKeyManager.swift`      | `displayName` uses an injected resolver.                  |
| `Tinycast/Core/HotKey/KeyShortcut.swift` | `collapsedModifierSymbols` takes Hyper display parameters. |
| `Tinycast/Core/SystemActionRunner.swift` | `onAsyncFailure` callback instead of `AppCore.shared`.    |
| `Tinycast/Core/AppCore.swift`            | Wires all dependencies once in `start()` / the composition root. |
| `Tinycast/Core/Backup/SettingsBackup.swift` | Explicit concrete context, no `AppCore` type.                 |
| `Tinycast/Core/Backup/BackupActions.swift`  | Stateless panels, detection and summary helpers only.        |
| `Tinycast/Features/Backup/BackupCoordinator.swift` | **New.** Owns backup/import orchestration.             |
| Backup UI call sites                       | Call the feature coordinator; Phase 32 environment-injects it. |
| Call sites of `collapsedModifierSymbols` | Pass the two new arguments.                               |

## Files that must NOT change

- `Tinycast/Core/HotKey/HotKeyCenter.swift`, `DoubleTapMonitor.swift`
- `Tinycast/Core/SystemAction.swift` — harness-compiled
- `Tinycast/Core/AppIndex.swift`, `Core/CustomCommand.swift`, `Core/Quicklinks/QuicklinkStore.swift`
- Any coordinator from phases 24–25

## Implementation boundaries

- **Closures, not protocols.** Each injection is one closure property set once in `AppCore.start()`.
  Do **not** introduce a `NameResolving` protocol, a `FailureReporting` protocol, or any abstraction —
  the review is explicit that no protocol should be added for testability.
- `displayName`'s resolver signature should be as narrow as possible, e.g.
  `var displayName: (HotKeyAction) -> String?` with `HotKeyManager` supplying its own fallbacks for the
  cases it already knows (`.togglePalette`, `.toggleClipboard`, `.toggleEmoji`, `.systemAction`,
  `.windowCommand` — all of which resolve from static catalogs, not from stores).
- `collapsedModifierSymbols` becomes a pure function of its arguments. **Do not** change what it
  produces: the ✦ collapse is keyed on _configuration_, not on tap health, so the glyphs never flicker,
  and leftover modifiers keep canonical order after the ✦.
- `SystemActionRunner`'s callback is set once. The existing `Task { @MainActor in … }` inside the
  `openApplication` completion handler stays — only the destination changes.
- **Do not** attempt to make any of these three files harness-compiled in this phase. Removing the
  inversion is the objective; adding a harness is a separate, later decision.
- Backup keeps one feature coordinator owned by `AppCore`; it receives concrete stores plus narrow
  replacement/dialog closures. No protocol, DI container, global locator, second dialog or store owner.
- `SettingsBackup`'s JSON fields, partial-apply semantics and consent exclusion stay unchanged.
- Raycast detection/decryption/mapping and snippet → settings → clipboard import ordering stay unchanged.

## Detailed acceptance criteria

1. `rg "AppCore\\.shared|AppCore = \\.shared|AppCore\\b" Tinycast/Core --glob '*.swift'` finds no
   active lower-layer dependency outside `AppCore.swift`; explanatory comments and the palette window's
   composition-root host reference are listed explicitly.
2. No protocol was introduced.
3. `collapsedModifierSymbols` is a pure function; it reads no global state.
4. The recorder's "Used by …" conflict message still names apps, panes, custom commands, system actions,
   window commands and quicklinks correctly.
5. Hyper Key ✦ collapse renders identically in launcher rows, Settings recorders and the recorder
   callout.
6. Turning "Replace occurrences of ⌃⌥⇧⌘ with ✦" off restores the full modifier glyphs everywhere.
7. A screen-saver launch failure still surfaces its dialog.
8. `AppCore.start()` wires the three callback inversions once.
9. Backup serialization/import code has no `AppCore` type or singleton lookup; its external JSON and
   consent behavior are unchanged.
10. Native and Raycast import keep executable-command confirmation and snippet/settings/clipboard order.

## Manual verification checklist

- [ ] `checklists/build.md`
- [ ] `checklists/testing.md` — `hotkey-test`, `callout-test`, `system-action-test`, `raycast-test`,
      `snippets-test`, `clipboard-test`, `quicklink-test`, `palette-selection-test`
- [ ] `checklists/regression.md` — Core sweep + **Hotkeys** + **System actions & window management**
- [ ] Bind a shortcut to an app; try to bind the same combo to a **custom command** → the conflict
      message names the **app**
- [ ] Repeat with a quicklink, a system action and a window command as the existing owner → each is
      named correctly
- [ ] Bind a shortcut to a **settings pane**; conflict message names the pane
- [ ] Set a Hyper Key with ✦ replacement **on** → launcher rows, Settings rows and the recorder callout
      all show ✦
- [ ] Turn ✦ replacement **off** → all three show ⌃⌥⇧⌘
- [ ] Toggle "Include Shift" → the glyph set changes consistently in all three places
- [ ] Delete `/System/Library/CoreServices/ScreenSaverEngine.app` is not testable; instead verify a
      different async failure path, or confirm by inspection that the callback is wired
- [ ] Export/import a native backup and confirm `snippetsEnabled` remains excluded
- [ ] Import Raycast snippets/settings/clipboard and verify the existing result summary/order

## Regression risks

| Risk                                                                               | Mitigation                                 |
| ---------------------------------------------------------------------------------- | ------------------------------------------ |
| The conflict message stops naming user-created items (custom commands, quicklinks) | AC4 + testing each of the six action kinds |
| ✦ collapse diverges between the three render sites                                 | AC5/AC6 — check all three                  |
| A protocol sneaks in "for cleanliness"                                             | AC2                                        |
| The failure callback is wired but never set, so a real failure is silent           | AC8 — read `start()`                       |
| `HotKeyManager` loses its static-catalog fallbacks and shows raw IDs               | AC4                                        |
| Backup dependencies or ordering drift                                             | AC9/AC10 + backup/Raycast harnesses         |

## Rollback strategy

`git revert <sha>`. In-memory wiring only.

## Expected commit size

14 files plus one new coordinator; net size depends on the moved Backup orchestration.

## Suggested commit message

```text
Break Core dependency inversions

Inject hotkey names, Hyper glyph configuration and asynchronous system-action
failure reporting. Move Backup orchestration behind a feature coordinator with
explicit stores and closures, leaving serialization independent of AppCore.
```

## Dependencies

Phase 15 (`HotKeyManager` observation) and **phase 25** (`AppCore` settled). Blocks 27.

## Definition of Done

- All acceptance criteria met
- No active lower-layer composition-root lookup remains in `Core/`
- All six conflict-owner kinds verified by hand
- Native backup and Raycast import behavior verified
- Merged

## Estimated difficulty

**Medium.**

## Estimated Claude context usage

**Medium.**

## Notes for reviewers

- **Run the grep yourself.** It is the phase's headline criterion and it takes two seconds.
- The conflict-owner test is tedious but it is the only thing that catches a resolver wired for four of
  six action kinds. Do all six.
- Check the ✦ collapse in **three** places — a launcher row keycap, a Settings recorder, and the
  recorder's callout. They render through different paths.
- If a protocol appeared, revert. The review is explicit: no protocol for testability.
