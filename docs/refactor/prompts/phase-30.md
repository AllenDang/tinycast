# Phase 30 kickoff — Naming vocabulary renames

Read `docs/refactor/phases/30-naming-vocabulary.md` completely.

## Task

Six renames, plus write the ten-suffix vocabulary table into `AGENTS.md`.

| Today              | Becomes            |
| ------------------ | ------------------ |
| `ClipboardManager` | `ClipboardMonitor` |
| `HotKeyManager`    | `HotKeyBindings`   |
| `CommandRegistry`  | `CommandCatalog`   |
| `PaletteViewModel` | `PaletteState`     |

## Hard gates

Per `docs/refactor/POLICY.md` you **may** rename persisted identifiers. The risk is no longer "did it
change?" but **"did every producer and consumer change together?"** These four bite:

- `ClipboardManager.internalType` — the writer and the poller must agree, or Tinycast re-captures its own
  pastes in a loop
- `SettingsKey.showInMenuBar` — shared with `TinycastApp`'s `@AppStorage`; rename in both or neither
- **`CommandID` raw values** — they _are_ `AppEntry.id`, which favourites, visibility and ranking key on
- SQLite column names — schema, prepared statements and row decoder must agree

**Renaming a persisted key is permitted but adds nothing here.** This phase renames _types_. Leave keys
alone unless one badly contradicts its new type name.

**Do not touch Raycast import** (`RaycastFormat`, `RaycastV1Decoder`, `RaycastImportV1/V2`) — another
application's format, not Tinycast's legacy.

Also:

- **Renames only.** Do not move a file, change a signature, or tidy anything while renaming.
- Each renamed file's name must match its renamed type.
- **Do not rename** `AppLauncher`, `QuicklinkLauncher` (Launcher is clearer for opening things),
  `SnippetRepository` (its conflict-detecting file semantics earn the name), `SnippetTextInjector`,
  `WindowMover` or `HyperKeyTap` (domain terms). Document all of these as exceptions in `AGENTS.md`.

## Verify before you summarise

```
xcodegen generate
xcodebuild build -project Tinycast.xcodeproj -scheme Tinycast -configuration Debug CODE_SIGNING_ALLOWED=NO
git grep -n "ClipboardManager\|HotKeyManager\|CommandRegistry\|PaletteViewModel"    # must be empty
git diff -U0 | grep '^[-+].*"'    # inspect EVERY changed string literal
```

Account for **every** line that grep returns — each needs its counterpart moved too.

Run all 18 harnesses. Then wipe the Dev channel, launch, and use the app for five minutes: copy, paste,
set a hotkey, favourite an app, quit, relaunch.

## Summarise

Use the system-prompt format. **Paste the output of the changed-string-literal grep** and, for each line,
name the producer and consumer that moved together. Confirm `RaycastImport*` is absent from the diff, and
that the `AGENTS.md` table includes the documented exceptions with reasons.
