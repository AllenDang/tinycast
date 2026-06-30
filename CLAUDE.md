# CLAUDE.md — Tinycast

A tiny, native macOS launcher: a stripped-down Raycast with only the core features — app launcher,
global + per-app hotkeys, and a clipboard manager. Built for speed and low RAM, using stock macOS
Liquid Glass UI (no custom-drawn chrome). Menu-bar accessory app, no Dock icon.

- **Platform:** macOS 26+ (Tahoe / Liquid Glass), Apple Silicon, Swift 6.
- **Dependencies:** one — [KeyboardShortcuts](https://github.com/sindresorhus/KeyboardShortcuts) (global hotkeys + recorder). Everything else is first-party Apple frameworks.

## Build & run

> ⚠️ **Always build via SwiftPM with Xcode's toolchain, never `xcodebuild`.**
> On this machine `xcodebuild` is broken (Xcode 26.5 vs macOS 27 / CLT mismatch — `DVTDownloads`
> plugin load failure). The Command Line Tools toolchain also can't compile SwiftUI (missing
> `SwiftUIMacros` plugin), so the `DEVELOPER_DIR` below is required — it points SwiftPM at Xcode's
> toolchain/SDK, which has the macro plugins, without invoking the broken `xcodebuild`.

```bash
# Compile
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift build

# Run the matcher unit test (no Xcode needed)
swift Tools/fuzz-test.swift

# One-time: create a stable self-signed identity so the Accessibility grant survives rebuilds
Packaging/dev-cert.sh

# Build a runnable .app  ->  build/Tinycast.app
Packaging/make-app.sh debug      # or: release

# Build the distributable DMG  ->  build/Tinycast.dmg
Packaging/build-dmg.sh
```

`make-app.sh` assembles the bundle by hand: copies the SwiftPM binary + resource bundles, writes a
concrete `Info.plist` (the one in `Tinycast/Info.plist` uses build variables and is only for the
XcodeGen project), and signs it. It prefers the stable `Tinycast Self-Signed` identity created by
`dev-cert.sh` and falls back to ad-hoc (`codesign --sign -`). Use the stable identity locally: an
ad-hoc signature gets a new cdhash every build, which invalidates the TCC **Accessibility** grant
(the app then reports "permission not given" after each rebuild). Grant Accessibility once after the
first stable-signed build and it persists.

**Distribution:** GitHub DMG, ad-hoc signed (no notarization). Users bypass Gatekeeper via System
Settings → Privacy & Security → "Open Anyway". Non-sandboxed (required to launch apps, post events).

`project.yml` (XcodeGen) is kept for IDE editing once Xcode is fixed, but is not the build path.

## Architecture

`AppCore` (`Core/AppCore.swift`) is the single `@MainActor` coordinator (`AppCore.shared`), wired up
from `App/AppDelegate.swift` on launch. It owns every manager:

- **AppIndex** (`Core/AppIndex.swift`) — scans app folders off the main thread, caches `[AppEntry]`,
  and provides `matches(query:)`. `FuzzyMatch` is a tiered ranker (exact → prefix → word-boundary
  substring → substring → subsequence). Display names come from the bundle's `CFBundleDisplayName`/
  `CFBundleName` (never the ".app" filename). **Keep `Tools/fuzz-test.swift` in sync** with it.
- **ClipboardStore / ClipboardManager** (`Core/Clipboard*.swift`) — a 0.5s timer polls
  `NSPasteboard.changeCount`; text + images are captured. Store is file-backed: a small `clipboard.json`
  index + PNG blobs in Application Support. Image *data is never held in memory* — see Performance.
- **HotKeyManager** (`Core/HotKeyManager.swift`) — registers the global launcher and clipboard
  shortcuts plus dynamic per-app shortcuts (`KeyboardShortcuts.Name("appHotkey." + bundleID)`).
- **PaletteWindowController / PalettePanel** (`Core/Palette*.swift`) — the command palette is a
  borderless floating `NSPanel` hosting SwiftUI. Show with `activate(ignoringOtherApps:)` +
  `makeKeyAndOrderFront` + **`orderFrontRegardless()`** (an accessory app summoned over another app
  won't raise otherwise). Dismiss on `windowDidResignKey`. **Never set both
  `.canJoinAllSpaces` and `.moveToActiveSpace` in `collectionBehavior`** — that throws and crashes
  on show.
- **Paster / Permissions** (`Core/*.swift`) — paste-back sets the pasteboard, re-activates the
  previously frontmost app, and posts ⌘V via `CGEvent` (needs Accessibility / `AXIsProcessTrusted`).

UI lives in `Features/`: `RootPaletteView` (search field + bottom bar), `Launcher/`, `Clipboard/`
(list + preview pane), `About/` (About + Changelog), `Settings/`. Settings, About and Changelog all
open in their own `NSWindow` via `AuxWindowController` (`Features/About/AboutView.swift`), raised by
`AppCore.showSettings()/showAbout()/showChangelog()` — the SwiftUI `Settings` scene is unreliable for
an accessory app, so it is not used.

## SwiftUI gotchas learned here (don't regress)

- **List identity:** use plain `ForEach(results)` with stable `Identifiable` ids and drive
  selection/scroll by **element id**. Do *not* combine `ForEach(enumerated, id:)` with `.id(index)`
  and `scrollTo(Int)` — it makes rows render stale/wrong content.
- **Aux windows:** an accessory app must `NSApp.activate` and raise the window itself, otherwise
  Settings/About/Changelog open behind other apps and render inactive/grey. `AuxWindowController`
  caches one window per id and does this on every `show`.

## Conventions

- Managers and anything touching AppKit/UI are `@MainActor`. Hotkey/timer callbacks hop via
  `MainActor.assumeIsolated { … }` (they fire on the main run loop).
- Keep dependencies minimal and changes surgical; match surrounding style.
- No debug `os_log`/print or `TINYCAST_*` env hooks in committed code — those are temporary only.
- No attribution/credit lines in code, commits, or PRs.

## Performance & low-RAM principles (the app's whole point)

- **Clipboard images:** load via `Core/ImageThumbnail.swift` — ImageIO downsampling to the exact
  pixel size needed (64px rows, ~1200px preview) cached in an `NSCache` (auto-evicts under memory
  pressure). Read dimensions from metadata (`pixelSize`), never by decoding the full image. Never
  hold full-res `NSImage`s; blobs stay on disk.
- **Lazy everywhere:** `LazyVStack` lists; app icons fetched on demand per visible row (system-cached),
  not retained.
- **Filter once per render:** `RootPaletteView.body` runs the matcher/search a single time for the
  active mode; rare event handlers may recompute.
- **Idle cost:** only the 0.5s pasteboard poll runs in the background; the panel is created once and
  reused. Ship **Release** (`-O`) builds — `make-app.sh release`.
- When adding features, prefer on-disk/lazy over in-memory caches, and downsample before display.
