# Phase 29 — Feature folders and the Settings shell

**Milestone:** M5 · **Effort:** L · **Risk:** Low · **Context:** High

---

## Overview

The last and largest set of moves: co-locate each feature's pure layer, effect layer, UI and Settings
pane under `Features/<Name>/`, leaving `Settings/` as a shell. Thirteen features, ~15 harness command
lines to update.

## Why this phase exists

This is the phase that actually fixes H-5. Today "Quicklinks" is 6 files in `Core/Quicklinks/`, 2 in
`Features/Quicklinks/`, 2 in `Features/Settings/`, plus slices in eight shared files. Phases 23–26
removed the shared-file slices; this one co-locates what remains.

## Architecture Review reference

**M-1**, **M-8**, **H-5** · §4.2

## Objectives

1. Create `Features/<Name>/{Model,Service,UI,Settings}/` for the thirteen features.
2. Move each feature's files in.
3. Reduce `Settings/` to `SettingsRootView.swift`, `SettingsTab.swift`, `AppSettings.swift`.
4. Update every affected harness command line.

## Target layout

| Feature              | Model (pure)                                                              | Service (effects)                                                                                                             | UI                                                                                | Settings                                                                                          |
| -------------------- | ------------------------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------- | --------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------- |
| **Launcher**         | `AppEntry`, `SearchRelevance`, `SearchScopes`, `LauncherRankingStore`     | `AppIndex`, `AppLauncher`, `SpotlightNames`, `SettingsPaneScanner`, `FavoritesStore`, `VisibilityStore`, `RunningAppsMonitor` | `LauncherScreen`, `LauncherList`, `AppRow`, `AppIconView`, `AppActionsMenu`       | `ApplicationsSettingsView`, `SystemSettingsSettingsView`, `LauncherItemsCard`, `SearchScopesCard` |
| **Clipboard**        | `ClipboardStore`                                                          | `ClipboardManager`, `Paster`                                                                                                  | `ClipboardScreen` + views                                                         | `ClipboardSettingsView`, `AppPickerPopover`                                                       |
| **Calculator**       | `Calculator/*`, `CurrencyData.generated`                                  | `CurrencyRateStore`, `CalculatorHistoryStore`                                                                                 | `CalculatorHistoryScreen`, `CalculatorCardView`                                   | —                                                                                                 |
| **Emoji**            | `EmojiCatalog`, `EmojiGridGeometry`, `EmojiData.generated`                | `EmojiIndex`, `FrequentEmojiStore`                                                                                            | `EmojiScreen`                                                                     | `EmojiSettingsView`                                                                               |
| **Quicklinks**       | `Quicklink`, `QuicklinkDestination`, `QuicklinkStore`, `QuicklinkArchive` | `QuicklinkLauncher`, `QuicklinkArgumentSession`                                                                               | screens + `QuicklinkCoordinator`                                                  | `QuicklinksSettingsView`, `QuicklinkEditorSheet`                                                  |
| **Snippets**         | `Snippets/*` pure                                                         | `SnippetTextInjector`, `SnippetKeywordListener`                                                                               | `SnippetArgumentsPrompt` + coordinator                                            | `SnippetsSettingsView`                                                                            |
| **WindowManagement** | `WindowCommand`, `WindowLayout`, `WindowActionMemory`                     | `WindowMover`                                                                                                                 | —                                                                                 | `WindowManagementSettingsView`                                                                    |
| **Uninstall**        | 5 pure files                                                              | `UninstallScanner`, `UninstallRunner`, `UninstallSession`                                                                     | `UninstallScreen` + coordinator                                                   | —                                                                                                 |
| **SystemActions**    | `SystemAction`, `VolumeLevel`                                             | `SystemActionRunner`, `VolumeState`                                                                                           | coordinator                                                                       | `SystemActionsSettingsView`                                                                       |
| **CustomCommands**   | `CustomCommand`                                                           | `ShellCommandRunner`                                                                                                          | coordinator                                                                       | `CommandsSettingsView`, `CustomCommandEditorSheet`                                                |
| **HotKeys**          | `KeyShortcut`, `HotKeyBinding`, `DoubleTapModifier`, `DoubleTapDetector`  | `HotKeyCenter`, `HotKeyManager`, `DoubleTapMonitor`, `HyperKeyTap`, `ShortcutCaptureSession`                                  | `ShortcutRecorder`, `ShortcutRecorderPopover`, `CalloutShape`, `CalloutPlacement` | —                                                                                                 |
| **Backup**           | `SettingsBackup`, `Raycast*`                                              | `BackupActions`, `Scrypt`, `Gunzip`                                                                                           | —                                                                                 | `BackupSettingsView`, `RaycastImportSelection`                                                    |
| **Onboarding**       | `OnboardingState`                                                         | —                                                                                                                             | `OnboardingView`                                                                  | —                                                                                                 |

Also: `Core/CommandRegistry.swift` → `Features/Launcher/Model/`; `Core/HealthTicker.swift` and
`Core/Memo.swift` → `Platform/`.

## Files that must NOT change (contents)

- **Every moved file.** This phase is 100 % moves.
- `EdgeDissolve.swift`, `ThinScrollbar.swift` — already in `DesignSystem/Scrolling/`, untouched again

## Implementation boundaries

- **One feature per commit, on one branch.** Thirteen small commits are far easier to bisect than one
  giant move, and `git` follows renames either way.
- **~15 harness command lines change.** Every harness in `checklists/testing.md` except
  `palette-selection-test` names at least one moving file. Update `docs/development.md` **and**
  `AGENTS.md` **and** `checklists/testing.md` in the same commit as each feature's move.
- **`AGENTS.md`'s Critical Invariants section names file paths throughout.** Every one of those paths
  must be updated in this phase. Read the whole section and fix every reference — a stale invariant is
  worse than none.
- Do not rename any type. Phase 30.
- Do not merge, split or edit any file.
- Do not create `Features/<Name>/` subfolders for a feature that has only one or two files — Onboarding
  and WindowManagement do not need four empty directories. Use judgement; the layer split is for
  features large enough to benefit.
- Run `xcodegen generate` after each feature and commit the project file with it.

## Detailed acceptance criteria

1. Every file is at its target path.
2. `git diff -M --stat` shows 100 % similarity for every move.
3. All 18 harness command lines updated in all three places (`docs/development.md`, `AGENTS.md`,
   `checklists/testing.md`) and all 18 pass.
4. Every file path referenced in `AGENTS.md`'s Critical Invariants section is correct.
5. `Settings/` contains exactly three files.
6. `Core/` no longer exists, or contains only what genuinely has no feature home — and that list is
   named in the summary.
7. Debug and Release builds succeed; UI pixel-identical.

## Manual verification checklist

- [ ] `checklists/build.md` including the **Release build**
- [ ] `checklists/testing.md` — **all 18**, using the updated command lines, copy-pasted fresh from
      `docs/development.md` to prove that file is correct
- [ ] `checklists/regression.md` — **the full document**
- [ ] Read `AGENTS.md`'s Critical Invariants section end to end; every path resolves
- [ ] `grep -rn "Tinycast/Core/" docs/ AGENTS.md` → only intentional historical references remain
- [ ] Screenshot the palette and two Settings panes before/after → pixel-identical
- [ ] `xcodegen generate` twice → stable

## Regression risks

| Risk                                                                                       | Mitigation                                                             |
| ------------------------------------------------------------------------------------------ | ---------------------------------------------------------------------- |
| **A harness command line is missed** → red suite, possibly not noticed until a later phase | AC3; copy-paste the block fresh from `docs/development.md`             |
| `AGENTS.md` invariants point at dead paths → the contract silently rots                    | AC4; read the whole section                                            |
| A single giant commit makes a partial revert impossible                                    | Boundary: one feature per commit                                       |
| Access-control breakage after a move                                                       | Compiler catches it; do not widen beyond `internal`                    |
| A file lands in the wrong layer (an effect file under `Model/`)                            | Reviewer checks imports: a `Model/` file importing AppKit is misplaced |

## Rollback strategy

`git revert` the specific feature's commit. That is why this is thirteen commits rather than one.

## Expected commit size

~110 files moved across ~13 commits. Content delta zero.

## Suggested commit message

Per feature, e.g.:

```
Move the Quicklinks feature into Features/Quicklinks/

Model (pure, harness-compiled), Service (effects), UI and Settings under
one folder. Harness command lines updated in docs/development.md and
AGENTS.md. Contents unchanged.
```

## Dependencies

**Phase 28 (hard).** Blocks 30, 31, 32.

## Definition of Done

- All acceptance criteria met
- All 18 harnesses green from freshly copy-pasted command lines
- `AGENTS.md` invariant paths all correct
- Merged

## Estimated difficulty

**Medium** per feature, **High** in aggregate. Tedious rather than hard.

## Estimated Claude context usage

**High.** Do it in thirteen conversations if needed — one per feature — rather than one long one.

## Notes for reviewers

- **The `AGENTS.md` path audit is the part that gets skipped and the part that matters most.** That file
  is the project contract; every stale path in it makes the contract less trustworthy for the next
  contributor and the next agent.
- Copy the harness block out of `docs/development.md` and run it verbatim. If it works, that file is
  correct — which is the only way to be sure.
- Check the layer placement by imports: anything in a `Model/` folder importing AppKit or SwiftUI is in
  the wrong layer, and the `Tools/` harness for that feature will tell you.
- Similarity must be 100 % everywhere. Zero exceptions in this phase.
