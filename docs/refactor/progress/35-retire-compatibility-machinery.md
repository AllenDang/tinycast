# Phase 35 — Retire compatibility machinery

## Status

| Field | Value |
| --- | --- |
| Status | Complete; independent review passed |
| Date | 2026-09-01 |
| Commit | none — orchestration forbids commits |

## Implemented

- Replaced every `KeyboardShortcuts_…` key with the stable app-owned `hotkey.…` namespace.
- Replaced `HotKeyBinding`'s fallback decoder and custom encoder with synthesized `Codable`.
- Folded all seven clipboard columns and the pin index into the fresh schema; removed both migrations.
- Deleted the post-roadmap single-provider AI defaults and Keychain migration with supervisor approval.
- Removed the `AGENTS.md` refactor banner and updated current subsystem and policy documentation.
- Replaced the clipboard migration fixture with fresh-schema column, index and persistence coverage.
- Extended `hotkey-test` to cover every key category and both synthesized `Codable` cases.
- Added `PresentationActions` and removed four feature coordinators' dependency on full `AppCore`.
- Moved pending quicklink editor state into the observable `QuicklinkCoordinator`.
- Replaced RootPaletteView's concrete-screen chord downcasts with a default-unhandled screen hook.
- Replaced the modal snippet argument alert with the app-owned async `DialogController` form.
- Routed Snippet, AI, Custom Command and Quicklink deletion confirmations through their coordinators.
- Routed Clipboard clear-history and launcher-ranking reset through their coordinators.
- Rejects Tinycast keyword targets before automatic generation and cancels argument dialogs on disable.
- Scoped argument-dialog cancellation by request UUID and made stale generation cancellation a no-op.

## Compatibility boundaries

Raycast v1/v2 sources, the Raycast harness and snippet Markdown serializer were not edited in Phase 35.
Their non-comment digests still match the Phase 34 pre-pass manifest. `SettingsBackup.deliberatelyExcluded`,
`SettingsData`, `AppSettings` and all fresh-install defaults likewise retain their Phase 34 digests.

The current provider store still reads and writes `aiProviders`, keeps `aiProviderEnabled` off by
default and uses per-provider bundle-scoped Keychain services. A scratch clean-suite test proved old
single-provider defaults are ignored while current provider storage reopens successfully.

## Automated verification

- Debug and Release builds: PASS with `CODE_SIGNING_ALLOWED=NO`.
- All 19 standalone harnesses: PASS.
- `hotkey-test`: 38 passed, including nine distinct `hotkey.…` keys and both binding cases.
- `clipboard-test`: 22 passed, including exact seven-column fresh schema and the pin index.
- `snippets-test`: own-app targets are ignored, another app remains eligible, the current generation may
  cancel, and a stale prompt generation cannot cancel newer automatic delivery.
- Snippet async-flow assertions: request IDs guard dialog cancellation, stale cancellation is a no-op,
  target rejection precedes generation, and automatic validation precedes activation.
- AI current-storage scratch test: PASS.
- XcodeGen: byte-stable across consecutive runs.
- `git diff --check`: PASS.
- Comment budget: PASS across 200 in-scope Swift files.
- Compatibility grep: no old hotkey key, migration symbol, `ALTER TABLE` or `columnExists` in `Tinycast/`.
- Final non-generated, non-off-limits source: 28,484 lines across 200 files.
- Final structure after architecture follow-up: AppCore 378 lines, RootPaletteView 575, `Core/`
  absent, 19 harnesses.
- Presentation-boundary follow-up: AppCore 560 lines; the four migrated coordinators have zero
  `AppCore` references and `DialogController()` still has exactly one owner.
- Leaf-coordinator follow-up: AppCore 417 lines after AI, Calculator, Clipboard, Emoji, Window
  Management and snippet settings actions moved to their feature owners.
- Launcher follow-up: AppCore 318 lines after every `AppEntry.Kind` and `CommandID` activation moved
  into the 145-line `LauncherCoordinator`; Launcher feature files contain no `AppCore` reference.
- The six migrated feature trees contain no `AppCore` reference; their screens and Settings panes
  receive concrete coordinators.
- Dialog argument-state scratch test: PASS for empty text defaults, first-option defaults and edits.
- Dialog grep: no `NSAlert`, SwiftUI `.alert`, `.confirmationDialog` or snippet modal prompt remains;
  file-panel `runModal` calls are unchanged.
- Dialog ownership: exactly one `DialogController()` construction remains.
- Staged files and commits: none.

## Environment coverage

The composition root injects every dependency before a view is mounted:

- Palette modes: launcher, uninstall, quicklink arguments, quicklinks, AI command, emoji, clipboard and
  calculator history. The palette hosting tree also injects `RunningAppsMonitor` and `HotKeyBindings`
  for launcher and quicklink row descendants.
- Settings panes: General, Applications, System Settings, System Actions, Commands, Quicklinks,
  Snippets, AI Commands, Window Management, Clipboard, Emoji, Permissions, Backup, Miscellaneous and
  About.
- Auxiliary flow: Onboarding receives BackupCoordinator, PaletteCoordinator, AppSettings and hotkeys.

## Approved exceptions and residual risk

- The Release executable remains 4,936,336 bytes; the user accepted the pre-existing MarkdownUI overage.
- Manual UI, pixel, Instruments, RSS, clean-channel relaunch and live shortcut checks were not run; the
  user explicitly waived these unavailable gates before Phase 35.
- The CI header and Xcode-selection block retain six pre-existing lint findings by prior explicit
  approval; Phase 35 changes only the hotkey harness command in that workflow.
- SwiftLint still reports two pre-existing `ClipboardScreen` closure-parameter violations.

## Post-roadmap architecture cleanup

- Added feature coordinators for launcher, AI, calculator, clipboard, emoji and window management.
- Moved snippet consent and Finder actions into `SnippetExpansionCoordinator`.
- Replaced concrete-screen key routing with the finite `PaletteCommand` seam.
- Removed every `AppCore` reference from `Palette/` and `Features/`.
- `PaletteWindowController` now owns only window state plus narrow injected callbacks and content.
- `PaletteCoordinator` receives delayed Settings and Onboarding builders from the composition root.
- Settings, Onboarding and every palette mode receive concrete stores and coordinators via environment.
- `AppCore` now contains ownership, initialization, startup wiring, observation and view builders only.
- Debug and Release builds plus all 19 harnesses pass after the cleanup.
- AppCore is a 378-line composition root including the three explicit SwiftUI environment builders.
- RootPaletteView no longer downcasts concrete screens for any palette command or running-state sample.
- Follow-up review restored `RunningAppsMonitor` and `HotKeyBindings` in the independent palette tree.
- Snippet argument collection now awaits the sole `DialogController`; feature shutdown cancels the task
  and only its request UUID. Tinycast targets are rejected before generation changes, stale prompt
  cancellation is a no-op, and stale automatic deliveries validate generation before target activation.
- All six Settings confirmations preserve their prior title, message and destructive action, but now use
  each feature's injected coordinator rather than a system alert or confirmation dialog.
