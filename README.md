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
Packaging/build-dmg.sh        # -> build/Tinycast.dmg
```

## First launch (Gatekeeper)

Tinycast is ad-hoc signed, not notarized. The first time you open it macOS will block it.
Go to **System Settings → Privacy & Security**, scroll to the Tinycast warning, and click
**Open Anyway**. (On macOS 15+ this replaces the old right-click → Open trick.)

## Permissions

- **Accessibility** — required so Tinycast can paste a clipboard item into the previously
  focused app. You'll be prompted the first time you paste; grant it in
  **System Settings → Privacy & Security → Accessibility**.

## Using it

1. Open **Settings → General** and record a global shortcut to open Tinycast.
2. Press it anywhere → the palette floats in. Type to filter apps, **↩** to launch.
3. **Tab** switches between Apps and Clipboard; **↑/↓** move, **Esc** dismisses.
4. **Settings → App Hotkeys**: search an app and record a shortcut to toggle it.
