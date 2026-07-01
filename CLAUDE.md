# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

Tinycast is a native macOS menu-bar launcher (a minimal Raycast): fuzzy app launcher, global + per-app
hotkeys, and a text/image clipboard history. SwiftUI + AppKit, runs as an accessory (no Dock icon,
`LSUIElement`). Targets **macOS 26+** (Liquid Glass) and is built with the **Xcode 26** toolchain.

## Build & run

The real build is **SwiftPM driven through Xcode's toolchain**, not `xcodebuild`. SwiftPM only emits a
bare executable, so `Packaging/make-app.sh` assembles the `.app` bundle (Info.plist, resource bundles,
code signing) around it:

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer Packaging/make-app.sh debug   # -> build/Tinycast.app
open build/Tinycast.app
Packaging/build-dmg.sh                                                                  # release .app + DMG
```

- `DEVELOPER_DIR` is mandatory: the SwiftUI `@State`/`@FocusState` macros live in Xcode's macOS
  platform, not in the Command Line Tools. Building with plain `swift build` or `xcodebuild` against
  the CLT will fail here. (If `xcode-select` already points at Xcode you can drop the prefix.)
- Run `Packaging/dev-cert.sh` **once** to create a stable self-signed identity ("Tinycast Self-Signed").
  `make-app.sh` signs with it when present; this keeps the macOS Accessibility (TCC) grant alive across
  rebuilds. Without it the build falls back to ad-hoc signing and you must re-grant Accessibility every
  build (needed for clipboard paste — see Paster).

There are **two parallel project definitions**: `Package.swift` is the build of record;
`project.yml` (XcodeGen → `xcodegen generate && open Tinycast.xcodeproj`) exists only to open the
project in the Xcode IDE. Keep dependency/version changes in sync between them.

## Tests

No XCTest target. The launcher matcher has a standalone harness:

```sh
swift Tools/fuzz-test.swift
```

`Tools/fuzz-test.swift` contains a **copy** of `FuzzyMatch` from `Tinycast/Core/AppIndex.swift`. If you
change the scoring in one, mirror it in the other or the test is meaningless.

## Architecture

**Single-owner core.** `AppCore.shared` (`Core/AppCore.swift`) is a `@MainActor` singleton that owns
every long-lived manager (`AppIndex`, `ClipboardStore`, `ClipboardManager`, `HotKeyManager`,
`AppSettings`, `FavoritesStore`, `RunningAppsMonitor`, `PaletteViewModel`) plus the window controllers.
`AppDelegate.applicationDidFinishLaunching` calls `AppCore.shared.start()` and nothing else; that's the
one wiring point. All palette/paste/launch actions are methods on `AppCore` that the SwiftUI views call.

**Two entry points, mostly AppKit windows.** `TinycastApp` (`@main`) declares only a `MenuBarExtra`
scene; everything visible is driven imperatively from AppKit. The command palette is a borderless
floating `NSPanel` (`Core/PalettePanel.swift`) hosting SwiftUI via `NSHostingView`, managed by
`PaletteWindowController`. Settings/About/Changelog are plain `NSWindow`s via `AuxWindowController`
(in `Features/About/AboutView.swift`) — the SwiftUI `Settings`/`Window` scenes are unreliable for
accessory apps, so this is deliberate. The app forces `.darkAqua` appearance globally; the Liquid Glass
material is tuned for a dark surface only.

**Palette state flow.** `PaletteViewModel` (mode/query/selection/`focusToken`) is the bridge between the
panel and `AppCore`. Showing the palette calls `prepare(mode:)`, which resets state and bumps
`focusToken` (a UUID) so the SwiftUI search field re-focuses. `RootPaletteView` switches between
`LauncherView` and `ClipboardView` on `mode`. The panel auto-dismisses on `windowDidResignKey`.

**Focus restoration is load-bearing.** `PaletteWindowController` records `previousApp` (the frontmost
app) on show. Paste then targets that app: `Paster.paste` activates it and posts a synthetic ⌘V via
`CGEvent`; `Paster.pasteInPlace` posts ⌘V straight to the app's PID _without_ activating it, so the
palette can stay open and frontmost (used by "paste keeping window open"). Both require the Accessibility
permission (`Permissions.ensureAccessibility()`).

**Clipboard capture is poll-based.** `ClipboardManager` runs a 0.5s `Timer` watching
`NSPasteboard.general.changeCount`. To avoid re-capturing Tinycast's own writes, every write stamps a
private `internalType` marker on the pasteboard and the poller skips anything carrying it.
`ClipboardStore` is file-backed: a small JSON index + PNG blobs under `~/Library/Caches/<bundle-id>/`.
Writes are snapshotted and performed off the main actor (`nonisolated static func write`), debounced 250ms
so a burst of copies collapses into one write.

**App index & fuzzy match.** `AppIndex.scan()` runs off-main, enumerates the standard `/Applications`
dirs, dedups by bundle ID (first dir wins). `FuzzyMatch.score` is a tiered scorer (exact → prefix →
substring/word-start → subsequence with consecutive/word-boundary bonuses); rankings are memoized one
query deep. Icons go through a count-capped `NSCache` (`IconCache`).

**Hotkeys** use the KeyboardShortcuts package (the only dependency). `HotKeyManager` registers global
toggles for palette and clipboard, plus per-app shortcuts keyed `appHotkey.<bundleID>`; the set of bound
bundle IDs is persisted in `UserDefaults` and re-registered on launch.

## Layout

- `Tinycast/Core/` — managers, stores, windows, AppKit glue (no view bodies beyond hosting).
- `Tinycast/Features/` — SwiftUI views: `RootPaletteView`, `Launcher/`, `Clipboard/`, `Settings/`, `About/`.
- `Tinycast/App/` — `@main` app + delegate.
- `Tinycast/Resources/CHANGELOG.md` — bundled and shown in-app by `ChangelogView`; update it when shipping.
- `Packaging/` — `make-app.sh` (bundle assembly + signing), `build-dmg.sh`, `dev-cert.sh`.

## Concurrency

Strict concurrency is on (`SWIFT_STRICT_CONCURRENCY: complete`). Almost everything is `@MainActor`;
cross-actor model types are `Sendable`. Heavy/IO work (app scan, clipboard JSON encode) is deliberately
pushed off-main via `Task.detached` / `nonisolated`. Keep that boundary when adding code. Note
`Package.swift` pins `.swiftLanguageMode(.v5)` even though the tools version is 6.0.
