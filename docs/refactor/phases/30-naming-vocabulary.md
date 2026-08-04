# Phase 30 — Naming vocabulary renames

**Milestone:** M6 · **Effort:** M · **Risk:** Low · **Context:** Med

> **Compatibility policy applies.** See [`../POLICY.md`](../POLICY.md). Persisted keys and raw values may
> be renamed along with their types. Carve-out 2 — internal consistency within one build — is what
> matters here now.

---

## Overview

Apply the ten-suffix naming vocabulary from the review, and record it in `AGENTS.md` so it holds. Five
type renames, one file rename, no logic changes.

## Why this phase exists

Roughly twenty competing suffixes are in use — `Manager`, `Service`, `Store`, `Index`, `Session`,
`Controller`, `Registry`, `Catalog`, `Runner`, `Monitor`, `Center`, `Presenter`, `Repository`,
`Scanner`, `Policy`, `Engine`, `Injector`, `Launcher`, `Mover`, `Tap`, `ViewModel`. Most carry real
meaning; the problem is that some are synonyms for each other and no rule is written down.

## Architecture Review reference

**L-3, L-4, L-5, L-10** · §4.1 naming vocabulary

## Objectives

1. Apply five renames.
2. Write the ten-suffix table into `AGENTS.md`.
3. Change nothing else.

## Renames

| Today                  | Becomes                                   | Why                                                                                   |
| ---------------------- | ----------------------------------------- | ------------------------------------------------------------------------------------- |
| `ClipboardManager`     | `ClipboardMonitor`                        | It polls an external stream — that is what `Monitor` means                            |
| `HotKeyManager`        | `HotKeyBindings`                          | It persists and publishes bindings; `HotKeyCenter` is already the Carbon layer        |
| `CommandRegistry`      | `CommandCatalog`                          | Matches `SystemActionCatalog`, `WindowCommandCatalog`                                 |
| `PaletteViewModel`     | `PaletteState`                            | It is shared app state read by the window controller and the panel, not a per-view VM |
| `Bundle+AppName.swift` | already `AppDisplayName.swift` (phase 27) | Concept-named, like `CursorScreen.swift`                                              |

## Expected files to modify

Every file referencing a renamed type — roughly 20 — plus `AGENTS.md`.

## Files that must NOT change

- No behaviour anywhere. This phase is `git grep` and rename.
- **Raycast import** — `RaycastFormat`, `RaycastV1Decoder`, `RaycastImportV1`, `RaycastImportV2` and
  their field names. That is another application's format, not Tinycast's legacy (POLICY carve-out 3).
- `Tools/*.swift` assertions — only the type names they reference, if any.

## Implementation boundaries

- **Renames only.** Do not move a file, change a signature, or "tidy" anything while renaming.
- **Persisted identifiers may be renamed** — but every producer and consumer must move together, or the
  app breaks _within this build_. The four that bite (POLICY carve-out 2):
  - `ClipboardManager.internalType` — the writer and the poller must agree, or Tinycast re-captures its
    own pastes in a loop.
  - `SettingsKey.showInMenuBar` — shared with `TinycastApp`'s `@AppStorage`. Rename in both or neither.
  - `CommandID` raw values — they _are_ `AppEntry.id`, which favourites, visibility and learned ranking
    key on. Rename them and those records are orphaned; that is acceptable under the policy, but the
    orphaning must be total rather than partial.
  - SQLite column names — schema, prepared statements and row decoder must agree.
- **Renaming a persisted key is permitted but adds nothing here.** This phase renames _types_. Rename a
  key only where leaving it would contradict the new type name badly enough to confuse a reader.
- The renamed file name must match its renamed type.
- Do **not** rename `AppLauncher` or `QuicklinkLauncher`. "Launcher" is clearer than "Runner" for
  opening things; document them in `AGENTS.md` as a reserved synonym for `NSWorkspace.open` wrappers.
- Do **not** rename `SnippetRepository`. Its conflict-detecting, revision-checked file semantics earn
  the name; document it as the eleventh suffix.
- Do **not** rename `SnippetTextInjector`, `WindowMover`, `HyperKeyTap` — domain terms with no better
  alternative.

## Detailed acceptance criteria

1. All five renames applied consistently; no old name remains
   (`git grep -n "ClipboardManager\|HotKeyManager\|CommandRegistry\|PaletteViewModel"` → empty).
2. Every file's name matches its primary type.
3. **Every changed string literal is accounted for**: if a persisted key was renamed, every producer and
   consumer moved with it. Verified by the changed-literal grep, not by assumption.
4. `AGENTS.md` contains the ten-suffix table plus the three documented exceptions
   (`Launcher`, `Repository`, and the domain terms).
5. All 18 harnesses pass.
6. Zero behaviour change on a clean install.

## Manual verification checklist

- [ ] `checklists/build.md`
- [ ] `checklists/testing.md` — all 18
- [ ] `checklists/regression.md` — Core sweep + **Clipboard** + **Hotkeys** + **Clean install**
- [ ] **Wipe the Dev channel, launch, and use the app properly for five minutes**
- [ ] Copy something → it is captured
- [ ] Paste from Tinycast → it is **not** re-captured (the pasteboard marker still agrees with itself)
- [ ] Set a hotkey, quit, relaunch → it still fires
- [ ] Favourite an app and hide another; quit and relaunch → both stuck
- [ ] Settings ▸ a pane switch from the palette still works
- [ ] Export a settings backup, wipe, import → everything comes back

## Regression risks

| Risk                                                                                                                                          | Mitigation                                                   |
| --------------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------ |
| **A persisted key is renamed on one side only** — the writer moves, the reader does not. Now the real risk, since renaming itself is allowed. | AC3 + the changed-literal grep, read line by line            |
| The pasteboard marker changes in the writer but not the poller → Tinycast re-captures its own pastes in a loop                                | The paste-then-check test                                    |
| `SettingsKey.showInMenuBar` moves in `AppSettings` but not in `TinycastApp`'s `@AppStorage` → the menu-bar toggle silently stops working      | Toggle it and watch the icon                                 |
| A rename lands in a `Tools/` harness assertion string                                                                                         | All 18 harnesses                                             |
| A Raycast field name is renamed → import breaks against a real export                                                                         | `RaycastImport*` on the must-not-change list; `raycast-test` |

## Rollback strategy

`git revert <sha>`. **No data risk** — local data is disposable under [`POLICY.md`](../POLICY.md). Wipe
the Dev channel after reverting if anything looks stale.

## Expected commit size

~20 files, mostly one-line identifier changes. `AGENTS.md` +40 lines.

## Suggested commit message

```
Apply the naming vocabulary

ClipboardManager → ClipboardMonitor, HotKeyManager → HotKeyBindings,
CommandRegistry → CommandCatalog, PaletteViewModel → PaletteState. The
ten-suffix table goes into AGENTS.md along with the three documented
exceptions. Where a persisted key moved with its type, every producer and
consumer moved with it.
```

## Dependencies

**Phase 29 (hard).**

## Definition of Done

- All acceptance criteria met
- Changed-literal grep reviewed line by line
- Vocabulary table in `AGENTS.md`
- Merged

## Estimated difficulty

**Low.** IDE-driven. The compatibility sharp edge this phase used to carry is gone.

## Estimated Claude context usage

**Medium.**

## Notes for reviewers

- **Search the diff for string literals**: `git diff -U0 | grep '^[-+].*"'`. Renaming a persisted string
  is now allowed, so the question is no longer _"did anything change?"_ but _"did everything that
  references it change together?"_ Account for every line the grep returns.
- The four consistency traps are `internalType`, `showInMenuBar`, `CommandID` raw values and the SQLite
  column names. Check each one's producers **and** consumers.
- Confirm `RaycastImport*` is absent from the diff — that is an external format, not Tinycast's legacy.
- Confirm the `AGENTS.md` table lists the exceptions with reasons. A vocabulary with undocumented
  exceptions is a vocabulary nobody follows.
