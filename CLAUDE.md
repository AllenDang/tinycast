# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

Tinycast is a native macOS menu-bar launcher (a minimal Raycast): fuzzy app launcher, global + per-app
hotkeys, and a text/image clipboard history. SwiftUI + AppKit, runs as an accessory (no Dock icon,
`LSUIElement`). Targets **macOS 26+** (Liquid Glass) and is built with the **Xcode 26** toolchain.

## Build & run

The app is built with **`xcodebuild`** against the committed `Tinycast.xcodeproj` (an application
target that produces the signed `.app` with icon/plist/resources natively):

```sh
open Tinycast.xcodeproj                                                            # ⌘R to run
xcodebuild -project Tinycast.xcodeproj -scheme Tinycast -configuration Debug build # or CLI
```

- `xcodebuild` needs Xcode's toolchain (the SwiftUI `@State`/`@FocusState` macros live in Xcode's
  macOS platform, not the CLT); if `xcode-select` points at the CLT, prefix
  `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`.
- `Tinycast.xcodeproj` is committed and generated from `project.yml` via XcodeGen — after editing
  `project.yml`, run `xcodegen generate` and commit. There is **no** `Package.swift`/SwiftPM.
- Builds sign with the stable `Tinycast Self-Signed` identity (project default), so the Accessibility
  grant persists across rebuilds. Create that identity once — see `docs/SIGNING.md` §1.
- VS Code code-intelligence (SourceKit-LSP) is driven by a git-ignored `buildServer.json` from
  `xcode-build-server` (setup in `docs/DEVELOPMENT.md`); the `.vscode` build task / F5 build to the
  fixed `build/DerivedData` so LSP indexes what you build. The test harnesses use `swiftc` directly.

**Releases** are built entirely by `.github/workflows/release.yml` (xcodebuild + `diskutil` DMG,
signed with the stable "Tinycast Self-Signed" identity from the `SIGNING_P12_*` secrets), per channel
(beta/stable). There is no local packaging script. See `docs/SIGNING.md` for the signing model.

## Tests

No XCTest target. The launcher matcher has a standalone harness:

```sh
swift Tools/fuzz-test.swift
```

`Tools/fuzz-test.swift` contains a **copy** of `FuzzyMatch` from `Tinycast/Core/AppIndex.swift`. If you
change the scoring in one, mirror it in the other or the test is meaningless.

The calculator engine harness compiles the **real** engine sources — no copy to keep in sync, which
is why `Tinycast/Core/Calculator/` must stay Foundation-only (no AppKit/SwiftUI imports):

```sh
swiftc Tinycast/Core/Calculator/*.swift Tools/calc-test.swift -o /tmp/calc-test && /tmp/calc-test
```

The emoji catalog/grid harness works the same way (the tested `Core/Emoji/` files stay AppKit/SwiftUI-free;
`EmojiData.generated.swift` is emitted by `node Tools/gen-emoji.js` (Node 18+ for global `fetch`), never edited by hand):

```sh
swiftc Tinycast/Core/Emoji/EmojiCatalog.swift Tinycast/Core/Emoji/EmojiGridGeometry.swift \
  Tinycast/Core/Emoji/EmojiData.generated.swift Tools/emoji-test.swift -o /tmp/emoji-test && /tmp/emoji-test
```

## Architecture

**Single-owner core.** `AppCore.shared` (`Core/AppCore.swift`) is a `@MainActor` singleton that owns
every long-lived manager (`AppIndex`, `ClipboardStore`, `ClipboardManager`, `HotKeyManager`,
`AppSettings`, `FavoritesStore`, `VisibilityStore`, `CalculatorHistoryStore`, `RunningAppsMonitor`,
`PaletteViewModel`) plus the window controllers. `AppDelegate.applicationDidFinishLaunching` calls
`AppCore.shared.start()` and nothing else; that's the one wiring point. All palette/paste/launch actions
are methods on `AppCore` that the SwiftUI views call.

**Two entry points, mostly AppKit windows.** `TinycastApp` (`@main`) declares only a `MenuBarExtra`
scene; everything visible is driven imperatively from AppKit. The command palette is a borderless
floating `NSPanel` (`Core/PalettePanel.swift`) hosting SwiftUI via `NSHostingView`, managed by
`PaletteWindowController`. It toggles between a compact bar and the full launcher by resizing the
window: `PaletteWindowController` solely owns the frame (resolved once per show to a top-left anchor so
it grows downward), and the hosting view sets `sizingOptions = []` so SwiftUI never drives the window
size — without that the hosting view resizes the panel to fit content and the top edge drifts on the
compact↔expanded swap. Settings/About are plain `NSWindow`s via `AuxWindowController`
(in `Features/About/AboutView.swift`) — the SwiftUI `Settings`/`Window` scenes are unreliable for
accessory apps, so this is deliberate. The app forces `.darkAqua` appearance globally; the Liquid Glass
material is tuned for a dark surface only.

**Palette state flow.** `PaletteViewModel` (mode/query/selection/`focusToken`) is the bridge between the
panel and `AppCore`. Showing the palette calls `prepare(mode:)`, which resets state and bumps
`focusToken` (a UUID) so the SwiftUI search field re-focuses. `RootPaletteView` switches its content on
`mode` (`.launcher` → `LauncherList`, `.clipboard` → `ClipboardList` + preview, `.calculatorHistory` →
`CalculatorHistoryList`); Clipboard and Calculator History are sub-screens reached from the launcher
(Tab, a command, or a hotkey) and back out to it. The panel auto-dismisses on `windowDidResignKey`. The
flat `selection` index is the single source of truth for highlight/activation and must always match the
visible row order, including the inline calculator card at index 0 when present (see below).

**Inline calculator.** `Core/Calculator/` is a Foundation-only engine fronted by `CalcMemo`, a one-deep
memo mirroring `AppIndex`'s. `CalcEngine.evaluate` runs a pipeline: natural-language date/time
(`CalcDateTime`, e.g. `hrs till 9am`, `days till 9april`, `today + 3 weeks`) → numeric reject →
tokenize → base conversion → explicit unit conversion (`10km to mi`) → **bare-unit auto-conversion**
(`1m` → feet+inches, `1hr` → 60 min, via `CalcUnits.parseBareConversion` + the `autoTargets` map) →
plain arithmetic. Date/time depends on the clock, so it takes an injected `now`/`calendar` — the public
`evaluate(_:)` uses the live clock, and `evaluate(_:now:calendar:)` lets `calc-test.swift` assert exact
strings against a fixed clock. `CalcResult` carries an `expression` (left), a `display`/`copyText`
payload (right), and optional `sourceBadge`/`targetBadge` word-name pills; `CalculatorCard` renders it as
a two-column card. When the launcher or Calculator History query evaluates to a result the card is
pinned at the top of the list (flat selection index 0, shifting rows by one) and Enter copies the answer
+ records it to `CalculatorHistoryStore`. Keep the whole engine (incl. `CalcDateTime`) AppKit/SwiftUI-free
so the `calc-test.swift` harness compiles the real sources.

**Visual design.** The palette/settings look — forced-dark, white-alpha ramp, floating transparent
bars, scroll-driven edge dissolve, Liquid Glass only on floating controls — is documented in
`DESIGN.md` at the repo root. `Core/Theme.swift` is the single token source; read `DESIGN.md` before
any restyle or new view.

**Scrollbars.** The palette lists (App Launcher, Clipboard history, Emoji, Calculator history) use the SwiftUI `.thinScrollbar()` + `.hideNativeScrollers()`; the Clipboard preview (right pane) and every Settings pane use the native `.overlayScroller()`.

**Focus restoration is load-bearing.** `PaletteWindowController` records `previousApp` (the frontmost
app) on show. Paste then targets that app: `Paster.paste` activates it and posts a synthetic ⌘V via
`CGEvent`; `Paster.pasteInPlace` posts ⌘V straight to the app's PID _without_ activating it, so the
palette can stay open and frontmost (used by "paste keeping window open"). Both require the Accessibility
permission (`Permissions.ensureAccessibility()`).

**Clipboard capture is poll-based.** `ClipboardManager` runs a 0.5s `Timer` watching
`NSPasteboard.general.changeCount`. To avoid re-capturing Tinycast's own writes, every write stamps a
private `internalType` marker on the pasteboard and the poller skips anything carrying it.
`ClipboardStore` is SQLite-backed: rows plus a trigram FTS5 index in `clipboard.sqlite3`, with image
blobs as loose PNG files, all under `~/Library/Caches/<bundle-id>/`. The newest 1000 rows are mirrored
in the `@Published items` window; FTS search reaches older rows. A database that won't open is deleted
and recreated (worst case the store degrades to session-only in-memory history). Image capture
(TIFF→PNG re-encode + blob write) runs off the main actor via detached tasks; row inserts, search, and
pruning stay on the main actor.

**App index & fuzzy match.** `AppIndex.scan()` runs off-main, enumerates the standard `/Applications`
dirs, dedups by bundle ID (first dir wins). `FuzzyMatch.score` is a tiered scorer (exact → prefix →
substring/word-start → subsequence with consecutive/word-boundary bonuses); rankings are memoized one
query deep. Icons go through a count-capped `NSCache` (`IconCache`).

**Hotkeys are in-house (zero dependencies).** `Core/HotKey/` holds `KeyShortcut` (Sendable model,
Carbon keycode+modifiers, layout-aware glyphs via `UCKeyTranslate`) and `HotKeyCenter` (the Carbon
`RegisterEventHotKey` layer, pausable). `HotKeyManager` owns both: persistence, conflict lookup, and
dispatch. Shortcuts persist as JSON strings under `KeyboardShortcuts_<name>` UserDefaults keys — a
legacy format from the removed KeyboardShortcuts package, kept so old bindings survive; the set of
bound bundle IDs lives in `boundAppBundleIDs` and is re-registered on launch. The settings recorder
(`Features/Settings/ShortcutRecorder.swift`) is deliberately not a focusable control: the active
recorder is `HotKeyManager.recordingAction` state, and keys are captured by local NSEvent monitors
while all Carbon registrations are paused.

## Layout

- `Tinycast/Core/` — managers, stores, windows, AppKit glue (no view bodies beyond hosting); `Core/Calculator/` is the Foundation-only calc engine, `Core/Theme.swift` the design tokens.
- `Tinycast/Features/` — SwiftUI views: `RootPaletteView`, `Launcher/`, `Clipboard/`, `Calculator/`, `Settings/`, `About/`, plus shared `PopoverMenu`.
- `Tinycast/App/` — `@main` app + delegate.
- `.github/workflows/release.yml` — the entire release pipeline (xcodebuild + DMG + GitHub Release + cask bump); signing setup lives in `docs/SIGNING.md`.
- `DESIGN.md` (repo root) — the visual design system: tokens, panel chrome, edge dissolve, rules for restyles.

## Concurrency

The target builds in **Swift 6 language mode** (tools version 6.0, no language-mode override), so
data-race safety violations are hard errors. Almost everything is `@MainActor`; cross-actor model
types are `Sendable`. Heavy/IO work (app scan, image decode) is deliberately pushed off-main via
`Task.detached` / `nonisolated`. Keep that boundary when adding code. House idioms for the sharp
edges: block-observer lifetimes go through the RAII `NotificationToken` (`Core/NotificationToken.swift`)
instead of removal in a `deinit`; `ClipboardStore` uses `isolated deinit` for its SQLite teardown;
raw Carbon/C pointers get decoded to plain values before crossing into actor code (see
`hotKeyCarbonEventHandler`).

## Comments

Keep comments to a **single line** — no stacked/multi-line comment blocks. Condense a multi-line
explanation into one line, or drop it. Don't write comments that restate the code; only comment the
non-obvious (a `why`, a gotcha, a load-bearing invariant).
