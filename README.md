# Tinycast

A tiny, fully native macOS launcher — the core of Raycast, without the bloat.

- **App launcher** — fuzzy-search and launch any installed app.
- **Global hotkey** — one shortcut to summon the command palette from anywhere.
- **Per-app hotkeys** — bind a shortcut to an app; press it to toggle (focus/hide).
- **Clipboard history** — text + images, searchable, pasted back into the app you were using.

Native SwiftUI + Liquid Glass. Runs as a menu-bar accessory (no Dock icon). Zero dependencies.

## Install (Homebrew)

```sh
brew tap abue-ammar/tinycast
brew install --cask tinycast          # stable
brew install --cask tinycast@alpha    # alpha  (installs side-by-side)
brew install --cask tinycast@beta     # beta   (installs side-by-side)
```

Each channel is a **separate app** — `Tinycast.app`, `Tinycast Alpha.app`, `Tinycast Beta.app`,
with distinct bundle IDs (`com.tinycast.app{,.alpha,.beta}`) and separate settings/permissions —
so you can run stable alongside a pre-release. Because Tinycast isn't notarized, clear the
quarantine flag once after install (the cask prints this too):

```sh
xattr -dr com.apple.quarantine "/Applications/Tinycast.app"
```

## Requirements

- macOS 26 or later (Liquid Glass).
- Xcode 26 installed (provides the SwiftUI macro plugin + SDK used to build).

## Build & run

Tinycast builds with Swift Package Manager using Xcode's toolchain:

```sh
# Build a runnable, ad-hoc-signed app into ./build/Tinycast.app
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer Packaging/make-app.sh debug
open build/Tinycast.app
```

> The build is driven through `DEVELOPER_DIR` because the SwiftUI `@State`/`@FocusState`
> macros live in Xcode's macOS platform, not in the Command Line Tools. If your
> `xcode-select` already points at Xcode (`sudo xcode-select -s /Applications/Xcode.app`),
> you can drop the `DEVELOPER_DIR=` prefix.

There is also an XcodeGen `project.yml` to open the project in the Xcode IDE
(`xcodegen generate && open Tinycast.xcodeproj`) once your Xcode is healthy.

## Package a DMG

```sh
Packaging/build-dmg.sh        # -> build/Tinycast.dmg (release build)
```

To cut a one-off channel build (different app name / bundle id / version, e.g. an alpha to
hand to a tester) without touching the script, override the defaults via env vars:

```sh
DISPLAY_NAME="Tinycast Alpha" BUNDLE_ID="com.tinycast.app.alpha" VERSION="0.1.0-alpha.1" \
    Packaging/build-dmg.sh    # -> build/Tinycast-0.1.0-alpha.1.dmg (contains "Tinycast Alpha.app")
```

- `DISPLAY_NAME` sets `CFBundleName`/`CFBundleDisplayName`, the `.app` bundle name, and the
  DMG's mounted volume name. The executable inside stays `Tinycast`.
- `BUNDLE_ID` sets `CFBundleIdentifier` (default `com.tinycast.app`) — the per-channel id is
  what lets the channels install side-by-side with separate settings/permissions.
- The DMG file name is always `Tinycast-<VERSION>.dmg` (`DMG_BASE` overrides the `Tinycast`
  prefix), so release assets always carry the version.

`build-dmg.sh` always runs `make-app.sh release` first, so the DMG is a Release build,
never debug. It packages the DMG with `diskutil image create` (the supported replacement for
the deprecated `hdiutil create`).

## CI releases

`.github/workflows/release.yml` builds and publishes a DMG from GitHub Actions — no local
machine needed. Run it from the **Actions** tab (`Release` → **Run workflow**) and pick:

- **channel** — `alpha`, `beta`, or `stable`. Each channel builds a distinct app
  (`Tinycast Alpha.app` / `Tinycast Beta.app` / `Tinycast.app`) with its own bundle id.
  Alpha/beta get an auto-incrementing `-alpha.N`/`-beta.N` suffix (`N` is the Actions run
  number) so re-running never collides; stable ships the version as-is.
- **version** — base semver, e.g. `0.2.0`.

It builds on a `macos-26` runner with Xcode 26, packages the DMG (same ad-hoc/self-signed
path as a local build — no Developer ID involved), and publishes a GitHub Release tagged
`v<full-version>` with a versioned DMG asset (`Tinycast-<full-version>.dmg`), marked
prerelease for alpha/beta. On success it also bumps the matching cask in the
[`homebrew-tinycast`](https://github.com/abue-ammar/homebrew-tinycast) tap (see below).

### Homebrew tap automation

The release job's final step rewrites the `version` + `sha256` of the channel's cask
(`tinycast`, `tinycast@alpha`, or `tinycast@beta`) in the tap repo and pushes. It needs a
`HOMEBREW_TAP_TOKEN` repo secret — a fine-grained PAT with **Contents: read/write** on
`abue-ammar/homebrew-tinycast`. Without the secret the step logs a warning and skips (the
release still publishes).

### Website

`.github/workflows/website.yml` builds `website/` (Vite + React + TS) and deploys it to
GitHub Pages at `https://abue-ammar.github.io/tinycast/` on every push to `main` that
touches `website/`. Enable it once via **Settings → Pages → Source = GitHub Actions**.

## First launch (Gatekeeper)

Tinycast has no Apple Developer ID and isn't notarized — there's no $99/yr account behind
it, so macOS has nothing it can vouch for. What you'll see depends on how the app arrived:

- **Built it yourself locally** (`make-app.sh`, no transfer involved): macOS shows the
  ordinary "unidentified developer" warning. Go to **System Settings → Privacy &
  Security**, scroll to the Tinycast entry, click **Open Anyway**, then open the app again
  (the click only unlocks the permission — it doesn't launch the app).
- **Received the `.app`/DMG from someone else** (AirDrop, Messages, Slack, browser
  download): the transfer stamps a quarantine flag, and an unsigned/self-signed app under
  quarantine gets a harder block — *"Tinycast is damaged and can't be opened, move it to
  the Trash."* This is misleading; the app isn't actually corrupted. Fix it in Terminal
  (use the channel's app name — `Tinycast Alpha.app` / `Tinycast Beta.app` for pre-releases):
  ```sh
  xattr -cr "/Applications/Tinycast.app"
  ```
  then open normally. There's no GUI path around this message on modern macOS — only the
  Terminal command.

## Permissions

- **Accessibility** — required so Tinycast can paste a clipboard item into the previously
  focused app. You'll be prompted the first time you paste; grant it in
  **System Settings → Privacy & Security → Accessibility**.

## Using it

1. Open **Settings → General** and record a global shortcut to open Tinycast.
2. Press it anywhere → the palette floats in. Type to filter apps, **↩** to launch.
3. **Tab** switches between Apps and Clipboard; **↑/↓** move, **Esc** dismisses.
4. **Settings → App Hotkeys**: search an app and record a shortcut to toggle it.

## License

[GPL-3.0](LICENSE)
