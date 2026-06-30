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

## Performance & low-RAM principles (the app's whole point)
- App should be well optimized, fast and low ram usage.
