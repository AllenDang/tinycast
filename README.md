# Tinycast

A tiny, fully native macOS launcher — the core of Raycast, without the bloat.

- **App launcher** — fuzzy-search and launch any installed app.
- **Global hotkey** — one shortcut to summon the command palette from anywhere.
- **Per-app hotkeys** — bind a shortcut to an app; press it to toggle (focus/hide).
- **Clipboard history** — text + images, searchable, pasted back into the app you were using.

Native SwiftUI + Liquid Glass. Runs as a menu-bar accessory (no Dock icon). One small
dependency: [KeyboardShortcuts](https://github.com/sindresorhus/KeyboardShortcuts).

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

To cut a one-off test build (different display name/version, e.g. an alpha to hand to a
tester) without touching the script, override the defaults via env vars:

```sh
DISPLAY_NAME="Tinycast Alpha" VERSION="0.1.0-alpha.1" DMG_NAME="Tinycast-Alpha" \
    Packaging/build-dmg.sh    # -> build/Tinycast-Alpha.dmg
```

`build-dmg.sh` always runs `make-app.sh release` first, so the DMG is a Release build,
never debug.

## CI releases

`.github/workflows/release.yml` builds and publishes a DMG from GitHub Actions — no local
machine needed. Run it from the **Actions** tab (`Release` → **Run workflow**) and pick:

- **channel** — `alpha`, `beta`, or `stable`. Alpha/beta get an auto-incrementing
  `-alpha.N`/`-beta.N` suffix (`N` is the Actions run number) so re-running never collides;
  stable ships the version as-is.
- **version** — base semver, e.g. `0.2.0`.

It builds on a `macos-26` runner with Xcode 26, packages the DMG (same ad-hoc/self-signed
path as a local build — no Developer ID involved), and publishes a GitHub Release tagged
`v<version>` with the DMG attached, marked prerelease for alpha/beta.

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
  the Trash."* This is misleading; the app isn't actually corrupted. Fix it in Terminal:
  ```sh
  xattr -cr /Applications/Tinycast.app
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
