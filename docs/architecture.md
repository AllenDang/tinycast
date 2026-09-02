# Architecture

Tinycast uses a feature-first expression of a pure-core / effect-shell architecture. See the subsystem
documents for details: [palette](palette.md), [launcher](launcher.md),
[calculator](calculator.md), [clipboard](clipboard.md), [custom commands](custom-commands.md),
[snippets](snippets.md), [quicklinks](quicklinks.md), [hotkeys](hotkeys.md), and [UI](ui.md).

## Dependency direction

Dependencies point inward through three layers:

1. **Model** — deterministic values and computation. Harness-critical model files use Foundation only
   and receive clocks, paths, rates and other environment facts as inputs.
2. **Service** — persistence, filesystem, network and macOS APIs. Services translate platform events
   into model values or perform one-shot effects.
3. **UI and coordination** — SwiftUI views render state; feature coordinators sequence multi-step flows
   across services. Coordinators do not own duplicate stores or windows.

The folder tree makes that direction visible:

- `Features/<Name>/Model/` — pure or persistence-owning feature state.
- `Features/<Name>/Service/` — platform effects and long-lived external observers.
- `Features/<Name>/UI/` — screens, rows, menus and feature coordinators.
- `Features/<Name>/Settings/` — the feature's settings surface.
- `Palette/` — palette shell, state protocol, panel and frame-owning controller.
- `Windows/` — dialogs, HUDs, About and auxiliary-window ownership.
- `DesignSystem/` — shared visual tokens and primitives.
- `Platform/` — thin app-wide macOS shims.
- `App/` — the composition root and process entry points.

The standalone `Tools/` harnesses compile shipped model files directly. This makes forbidden AppKit or
SwiftUI dependencies a compile failure rather than a convention checked only in review.

## Composition root

`AppCore.shared` (`App/AppCore.swift`) is the `@MainActor` composition root. It creates each long-lived
store, index, monitor, session and coordinator once, then wires callbacks in `start()`.
`AppDelegate.applicationDidFinishLaunching` is the only startup entry point.

Feature coordinators own orchestration that crosses several collaborators:

- `PaletteCoordinator` — palette modes and auxiliary windows.
- `QuicklinkCoordinator` and `SnippetExpansionCoordinator` — template and argument flows.
- `SystemActionCoordinator`, `UninstallCoordinator` and `CustomCommandCoordinator` — guarded effects.
- `BackupCoordinator` — Tinycast backup and Raycast import orchestration.

`DialogController` remains single-owned by `AppCore`; coordinators present through injected closures or
the composition root, so held hotkeys cannot create competing presenters.

## Windows and palette

`TinycastApp` declares only a `MenuBarExtra`. AppKit owns every window:

- `PaletteWindowController` owns the borderless palette panel and is the sole palette-frame authority.
- `AuxWindowController` owns Settings, About and Onboarding windows.
- `DialogController` owns confirmations and reports; HUD controllers own transient feedback.

`RootPaletteView` is the palette chrome and keyboard router. Each `PaletteScreen` owns its visible row
order, rendering and row actions. A flat selection indexes that screen's `rows`, including leading
calculator or AI cards, so highlight and activation share one source of truth.

The app forces `.darkAqua`; the Liquid Glass surface is tuned only for that appearance.

## Concurrency

The target uses Swift 6 strict concurrency. UI state and platform coordination are predominantly
`@MainActor`; values crossing actor boundaries are `Sendable`. Filesystem scans, image decoding and
network work run off-main. Raw Carbon and C pointers are decoded into plain values before entering
actor-isolated code.

Block observer lifetimes use `NotificationToken`, SQLite teardown uses isolated deinitialization, and
network stores re-check consent before and after suspension points.
