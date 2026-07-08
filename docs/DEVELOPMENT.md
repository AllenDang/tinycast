# Development

How to build, test, package, and release Tinycast.

## Requirements

- macOS 26 or later (Liquid Glass).
- Xcode 26 installed — it provides the SwiftUI macro plugin and SDK used to build.

## Build & run

Tinycast builds with Swift Package Manager, driven through Xcode's toolchain:

```sh
# Build a runnable, ad-hoc-signed app into ./build/Tinycast.app
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer Packaging/make-app.sh debug
open build/Tinycast.app
```

`DEVELOPER_DIR` is required because the SwiftUI `@State`/`@FocusState` macros live in Xcode's
macOS platform, not in the Command Line Tools — a plain `swift build`/`xcodebuild` against the
CLT fails. If `xcode-select` already points at Xcode
(`sudo xcode-select -s /Applications/Xcode.app`), you can drop the `DEVELOPER_DIR=` prefix.

Run `Packaging/dev-cert.sh` **once** to create a stable self-signed identity. `make-app.sh` signs
with it when present, which keeps the macOS Accessibility (TCC) grant alive across rebuilds;
without it the build falls back to ad-hoc signing and you must re-grant Accessibility each build.

### Opening in Xcode

There's an XcodeGen `project.yml` for the IDE:

```sh
xcodegen generate && open Tinycast.xcodeproj
```

`Package.swift` is the build of record; `project.yml` exists only to open the project in Xcode.
Keep dependency/version changes in sync between them.

## Tests

There's no XCTest target. Two standalone harnesses:

```sh
swift Tools/fuzz-test.swift                                        # launcher fuzzy matcher
swiftc Tinycast/Core/Calculator/*.swift Tools/calc-test.swift \
    -o /tmp/calc-test && /tmp/calc-test                           # calculator engine
```

`Tools/fuzz-test.swift` holds a **copy** of `FuzzyMatch` from `Tinycast/Core/AppIndex.swift` —
change the scoring in one and mirror it in the other. The calc harness compiles the real engine
sources, which is why `Tinycast/Core/Calculator/` must stay Foundation-only.

## Package a DMG

```sh
Packaging/build-dmg.sh        # -> build/Tinycast-<version>.dmg (release build)
```

`build-dmg.sh` always runs `make-app.sh release` first (never debug) and packages the DMG with
`diskutil image create` (the supported replacement for the deprecated `hdiutil create`).

### Channel builds

To cut a one-off channel build — a distinct app name / bundle id / version, e.g. an alpha to
hand a tester — override the defaults via env vars:

```sh
DISPLAY_NAME="Tinycast Alpha" BUNDLE_ID="com.tinycast.app.alpha" VERSION="0.1.0-alpha.1" \
    Packaging/build-dmg.sh    # -> build/Tinycast-0.1.0-alpha.1.dmg (contains "Tinycast Alpha.app")
```

- `DISPLAY_NAME` sets `CFBundleName`/`CFBundleDisplayName`, the `.app` bundle name, and the DMG's
  mounted volume name. The executable inside stays `Tinycast`.
- `BUNDLE_ID` sets `CFBundleIdentifier` (default `com.tinycast.app`) — the per-channel id is what
  lets channels install side-by-side with separate settings and permissions.
- The DMG file name is always `Tinycast-<VERSION>.dmg` (`DMG_BASE` overrides the `Tinycast`
  prefix), so release assets always carry the version.

## Signing & Gatekeeper

Tinycast is **not** signed with an Apple Developer ID and **not** notarized — deliberately, to
avoid the $99/yr account. Ad-hoc signing (what CI does) is enough to _run_ the app but gives
Gatekeeper nothing to vouch for, so users clear quarantine once after install:

```sh
xattr -dr com.apple.quarantine "/Applications/Tinycast.app"
```

When you build locally, macOS instead shows the ordinary "unidentified developer" prompt — allow
it under **System Settings → Privacy & Security → Open Anyway**.

## CI releases

`.github/workflows/release.yml` builds and publishes a DMG from GitHub Actions — no local machine
needed. Run it from the **Actions** tab (`Release` → **Run workflow**) and pick:

- **channel** — `alpha`, `beta`, or `stable`. Each builds a distinct app
  (`Tinycast Alpha.app` / `Tinycast Beta.app` / `Tinycast.app`) with its own bundle id.
  Alpha/beta get an auto-incrementing `-alpha.N`/`-beta.N` suffix (`N` = the Actions run number)
  so re-running never collides; stable ships the version as-is.
- **version** — base semver, e.g. `0.2.0`.

It builds on a `macos-26` runner with Xcode 26 and publishes a GitHub Release tagged
`v<full-version>` with a versioned DMG asset (`Tinycast-<full-version>.dmg`), marked prerelease
for alpha/beta. On success it also bumps the matching cask in the tap (below).

### Homebrew tap automation

The release job's final step rewrites the `version` + `sha256` of the channel's cask (`tinycast`,
`tinycast@alpha`, or `tinycast@beta`) in the
[`homebrew-tinycast`](https://github.com/abue-ammar/homebrew-tinycast) tap and pushes. It needs a
`HOMEBREW_TAP_TOKEN` repo secret — a fine-grained PAT with **Contents: read/write** on the tap
repo. Without the secret the step logs a warning and skips (the release still publishes).

## Website

`.github/workflows/website.yml` builds `website/` (Vite + React + TS) and deploys it to GitHub
Pages at `https://abue-ammar.github.io/tinycast/` on every push to `main` that touches
`website/`. Enable it once via **Settings → Pages → Source = GitHub Actions**.

```sh
cd website && npm install && npm run dev     # local preview
```
