# Raycast v2 Design System — extracted reference

Reverse-engineered from `raycast-beta-source/frontend/` (Raycast v2 beta React bundle,
extracted 2026-07). Each section cites the source file so values can be re-verified with grep.
Focus: **Raycast Dark** (Tinycast forces `.darkAqua`); other bundled themes are tabled at the end.

## TL;DR — the Raycast Dark formula

The entire "Raycast look" in dark mode reduces to five numbers:

1. **Window surface = 40% black over the OS behind-window blur.** There is no gray; the
   depth comes from the desktop showing through.
2. **Window corner radius 26px** (macOS), list rows **10–12px**.
3. **Everything on the surface is white at an alpha ramp**: 5% (hover, input fields),
   10% (selection, separators-ish, control surfaces), 20% (borders, kbd outlines),
   40% (tertiary text), 60% (secondary text), 100% (primary text).
4. **Selection = white @ 10%, hover = white @ 5%** on rounded rows.
5. **Edges don't clip, they dissolve**: a stacked progressive backdrop-blur under the
   header + a scroll-driven gradient mask on the list.

Accent (used sparingly — links, focus, AI): `#4FA3F8`. Brand red: `#FF6363`.

---

## 1. Theme system & color tokens

Source: `css-DIo7RXru.css` (token definitions), `css-DZuuGb9Q.js` (theme→CSS-var mapping),
`ipc-icon-cache-version-bFVaMBkU.js` (bundled theme values).

A theme is exactly 13 colors:
`background`, `backgroundSecondary`, `foreground`, `accent`, `selection`, `loader`,
`red`, `orange`, `yellow`, `green`, `blue`, `purple`, `magenta`.

### Raycast Dark (bundled default)

| Token | Value |
|---|---|
| background | `#000000` |
| backgroundSecondary | `#000000` |
| foreground | `#FFFFFF` |
| accent | `#4FA3F8` |
| selection | `#FFFFFF` |
| loader | `#FFFFFF` |
| red | `#FF6363` |
| orange | `#FF9217` |
| yellow | `#FFC531` |
| green | `#59D499` |
| blue | `#56C2FF` |
| purple | `#A485FF` |
| magenta | `#CF2F98` |

Brand color (fixed, theme-independent): `--color-brand: #ff6363`.

### Alpha ramps

Every theme color is exposed at fixed alpha stops via
`rgb(from var(--X) r g b / N%)`: **0, 5, 10, 20, 40, 60, 80%** (e.g. `--fg-10`,
`--selection-5`, `--accent-40`). Virtually all dark-mode surfaces are `--fg-*` or
`--selection-*` ramp values — never hardcoded grays.

### Semantic tokens (dark values with fg/selection = white)

| Semantic token | Definition | Dark resolved |
|---|---|---|
| `--color-text-primary` | `fg` | white |
| `--color-text-secondary` | `fg-60` | white 60% |
| `--color-text-tertiary` / placeholder / disabled | `fg-40` | white 40% |
| `--color-text-quaternary` | `fg-20` | white 20% |
| `--color-surface-list-selection` | `fg-10` | white 10% |
| `--color-surface-list-hover` | `fg-5` | white 5% |
| `--color-surface-control` | `fg-10` | white 10% |
| `--color-surface-token` (kbd filled) | `fg-10` | white 10% |
| `--color-surface-inner-panel` | `#ffffff1a` | white 10% |
| `--color-surface-input-field` | `#ffffff0d` | white 5% |
| `--color-surface-action-bar` | `#ffffff0d` | white 5% |
| `--color-border-secondary` (field/token borders) | `fg-20` | white 20% |
| `--color-border-separator` | `fg-10` | white 10% |
| `--color-border-tertiary` | `fg-5` | white 5% |
| `--color-window-bg` | `bg-40` | **black 40%** |
| `--color-window-bg-secondary` | `bg-secondary-40` | black 40% |
| `--color-panel-backdrop` | `#333` (dark) | opaque fallback under panels |
| `--color-panel-overlay` | `#ffffff1a` | white 10% wash on panels |
| `--color-window-base` | `#262626` (dark) | opaque base for color-mix composites |

---

## 2. Window background & materials

Source: `css-DIo7RXru.css`, `window-shell-DTtTqEk_.css`, `main-window-BC5rfd7y.css`.

### The surface

```css
.theme-root:before {
  background-image: linear-gradient(to bottom,
    var(--color-window-bg),            /* bg @ 40% */
    var(--color-window-bg-secondary)); /* bg-secondary @ 40% */
  position: absolute; inset: 0;
}
```

- The gradient sits **over the OS behind-window blur** (native, not CSS). Raycast Dark has
  bg == bgSecondary == black, so the "gradient" is a flat **40% black scrim**; themed skins
  (Sky, Sunset…) get a real two-color vertical gradient from the same mechanism.
- On macOS the **main window** removes the CSS layer
  (`.theme-root[macos]:has(#main-window-root):before { background-image: none }`) — the
  native NSWindow supplies the tint there; auxiliary windows keep the CSS gradient.
- `.main-window-stabilizer` — a full-window `backdrop-filter: blur(.1px) saturate()` layer at
  `z-index:-1` whose only job is to force a stable compositing/backdrop snapshot.

### Liquid Glass usage (macOS 26)

`-apple-visual-effect: -apple-system-glass-material` (WKWebView-only CSS) is applied **only
to floating chrome**, never the main surface: popovers, toasts, sidebars, HUDs, alerts.
Variants: `-subdued` (tinted controls), `-media-controls` (small controls).

### Inactive (key-window lost) state

Attribute `[window-blurred]`:

- Glass elements switch to a flat dimmed color:
  `--tahoe-dimmed-bg: hsla(from color-mix(in srgb, var(--bg) 50%, var(--bg-secondary)) h calc(s * .35) 15%)`
  (dark; light uses `s * .85` and 95% lightness), and drop their shadows.
- Controls dim to `opacity: .4`.

### Reduced transparency fallback

Windows-only in the bundle (`.no-transparency` → opaque `#333`-ish backdrop), but the
pattern to copy: when "Reduce transparency" is on, swap scrim → opaque `--color-panel-backdrop`.

---

## 3. Progressive edge blur (the "edge dissolve")

Source: `progressive-blur-DqVGxuMv.js` (algorithm), `progressive-blur-hleJHwXZ.css` (masks).

A **stack of 9 full-size `backdrop-filter: blur()` layers**, each masked to a narrow
horizontal band, so blur radius ramps smoothly with distance from the edge:

```
blurLevels = [0.25, 0.5, 0.75, 1, 1.4, 1.8, 2.3, 2.9, 3.6]  // px
```

Layer masks for `position: top` (mirror for bottom); each band is 12.5% of the
component height, sliding toward the edge as blur increases:

| Layer | blur px | mask (linear-gradient, black = visible) |
|---|---|---|
| first (nearest content) | 0.25 | `transparent 62.5%, black 75%–87.5%, transparent 100%` |
| middle i = 1…7 | 0.5…2.9 | `transparent i·12.5%, black (i+1)·12.5%–(i+2)·12.5%, transparent (i+3)·12.5%` (toward edge) |
| last (at edge) | 3.6 | `black 0%, transparent 12.5%` |

Notes:

- Blur values are tiny (max 3.6px) — the effect reads as "content melting under the header",
  not frosted glass.
- Container: `position: absolute; inset-inline: 0; pointer-events: none; z-index: 0`, placed
  **inside the header at `z-index: -1`**, `height: var(--window-header-height)` (≈64px in the
  main window) or 60px for toolbars. There is no opaque header background — only this stack
  plus the scrim behind everything.
- `position: both` variant exists (masks `transparent 0%, black 5%–95%, transparent 100%`).

---

## 4. Scroll edge fade (mask, complements the blur)

Source: `query-keys-DWSZswzH.css` (`scroll-area__wrapper`), `main-window-BC5rfd7y.css`.

The scroll container itself gets a `mask-image` whose strength follows scroll position:

```css
mask-image: linear-gradient(to bottom,
  transparent 0px,
  rgba(0,0,0, var(--top-fade-opacity))    var(--top-fade-midpoint),
  black var(--top-fade-height),
  black calc(100% - var(--bottom-fade-height)),
  rgba(0,0,0, var(--bottom-fade-opacity)) var(--bottom-fade-midpoint),
  transparent 100%);
```

Driving math (all CSS calc, fed by `--top/bottom-fade-scroll-distance` from JS):

- `progress = clamp(0, scrollDistance / fadeHeight, 1)`
- `top-fade-opacity    = 1 − (1 − 0.15) · progress` → fades **to** 0.15, not to 0
- `bottom-fade-opacity = 1 − (1 − 0.25) · progress` → min 0.25
- midpoint slides from the edge to `fadeHeight · 0.5` as progress → 1

So: nothing scrolled = no fade; once content is under the edge, rows dissolve through a
soft ramp that never goes fully invisible until the very edge. `scroll-padding-top/bottom`
is set to the fade heights so keyboard selection never lands inside the faded zone.

Static variant for detail panes: `mask-image: linear-gradient(transparent 0%, black 8%–92%, transparent 100%)`.

---

## 5. Chrome: radii, blur scale, shadows, separators, loader

Source: `css-DIo7RXru.css`, `action-bar-ui-DHTvPY2t.css`, `command-panel-mEPNri7j.css`.

### Radii

| Use | Value |
|---|---|
| Window (macOS) | **26px** (`--radius-window`) |
| List row | 12px (large rows) / 10px (default) — set from JS |
| Controls, kbd, icons | 4–8px |
| Scale | 2, 4, 6, 8, 10, 12, 16, 18, 20, 26, full(9999) |

### Blur scale (macOS)

`--blur-1: 6px`, `--blur-2: 12px`, `--blur-3: 24px`, `--blur-4: 36px`.
(Panels/popovers use `blur-4`; nav controls `blur-2`.)

### Window/panel shadow (macOS)

```
0  1px  1px -1px rgba(0,0,0,.05),
0  4px  2px -3px rgba(0,0,0,.05),
0  8px  4px -6px rgba(0,0,0,.05),
0 12px 40px -12px rgba(0,0,0,.10),
0 24px 64px -24px rgba(0,0,0,.20)
```

macOS panels have **no inset border** (the glass provides the rim); Windows adds
`inset 0 0 0 1px var(--fg-20)`.

### Separators

- Header bar: 1px line at its **bottom**, `--color-border-separator` (white 10%).
- Action bar / footer: line at its **top** — main-window footer uses **0.5px** height with
  `margin: 0 1px` (inset past the window border).
- In-list separators: `--color-border-separator`, inset 1px.
- macOS dark adds `--window-border-offset: 1px` — hairlines are inset 1px from window edges.

### Loader (the top-edge shimmer)

1px-tall gradient at the window top, animated 1.5s infinite:

- classic: `linear-gradient(to right, loader-0 25%, loader, loader-0 75%)` sweeping
- glow: `linear-gradient(to right, loader-0, loader, loader-0)`, fade in over .7s

`loader` = white in Raycast Dark.

---

## 6. Lists, selection, search, kbd chips

Source: `window-shell-DTtTqEk_.css` (`list__*`, `standard-list-item__*`),
`search-input-BFowgM3R.css`, `command-panel-mEPNri7j.css`, `query-keys-DWSZswzH.css` (`shortcut__*`).

### Main window metrics (logical px, scaled by `--zoom`)

| Metric | Value |
|---|---|
| Window | 750 × 475 |
| Header (search bar) height | 64 (macOS) |
| Footer height | 44 (macOS default) / 42 |
| Row height | JS-driven per item (≈40 default) |
| Row inner padding-x | 8 |
| Row content gap | 8 (small icons) / 12 (large) |
| Icons | 16 (small) / 22 (large) |
| Section header | own row, `fg-40`-style tertiary text, extra top margin |

### Selection / hover

```css
row                     { background: transparent; }
row.hover               { background: var(--selection-5);  }  /* white 5%  */
row[data-state=selected]{ background: var(--selection-10); }  /* white 10% */
```

- Radius 10–12px, rows inset from window edges (margin-inline = list padding).
- "Split" items (e.g. AI command rows) idle at `rgb(from var(--selection) r g b / 3%)`.
- Row content gets a right-edge `mask-image` fade (~100px ramp) instead of ellipsis when
  accessories/hotkey hints overlap.

### Search field

- No box, no border: a bare input on the surface, placeholder `--color-text-tertiary`
  (white 40%), caret `--fg`. The header is just input + 1px bottom separator + progressive blur.
- Boxed variant (settings sidebar): `bg-20` fill, focus brightens via
  `color-mix(…, white 5%)`.

### kbd / shortcut chips

- min-width/height 18px (small, 10px font) or 20px (medium), padding-x 4px, gap 2px between keys.
- Outline variant: text `fg-60`, `box-shadow: inset 0 0 0 1px var(--fg-20)`, no fill.
- Prominent variant: text `fg`, fill `fg-10`, no border.
- Success/error variants: `green`/`red` text on `green-10`/`red-10`.

### Footer / action bar

- Height 40–44, content: app icon 16px + name left; actions right.
- Action buttons: text `fg`, hover `fg-5` fill; subtle/disabled `fg-60`; gap 4.

---

## 7. Typography & spacing

Source: `css-DIo7RXru.css`.

- **InterVariable** (100–900), features `liga, calt, kern, ss03`; **JetBrains Mono** for code.
- Base 13px / weight 400. Size scale: 8, 11, 13, 16, 18, 24 — all `round(calc(N * --spx), 1px)`
  where `--spx = 1px * --zoom` (every metric in the app scales through this).
- macOS: `-webkit-font-smoothing: subpixel-antialiased`; `font-synthesis: none`.
- Spacing scale: 2, 4, 6, 8, 12, 16, 24, 32, 40, 48, 56.
- Easing: `--easing-ease-out-expo: cubic-bezier(.16, 1, .3, 1)`; selection mask transitions
  ~0.1–0.25s ease-out.

---

## 8. Other bundled themes (reference)

Source: `ipc-icon-cache-version-bFVaMBkU.js`. Accent is `#4FA3F8` unless noted.
Format: bg → bgSecondary; the window scrim is always these at 40% over blur.

| Theme | Mode | bg → bgSecondary | fg | selection | loader | red / orange / yellow / green / blue / purple / magenta |
|---|---|---|---|---|---|---|
| Raycast Dark | dark | `#000000` → `#000000` | `#FFFFFF` | `#FFFFFF` | `#FFFFFF` | `#FF6363` `#FF9217` `#FFC531` `#59D499` `#56C2FF` `#A485FF` `#CF2F98` |
| Raycast Light | light | `#FFFFFF` → `#FFFFFF` | `#000000` | `#000000` | `#000000` | `#B12424` `#C75D07` `#F8A300` `#006B4F` `#138AF2` (accent `#138AF2`) `#6A3DEC` `#9A1B6E` |
| Sky | dark | `#0E1C3F` → `#173036` | `#D7F0F4` | `#6688FF` | `#47FFFF` | `#ED5959` `#ED8659` `#EDD559` `#47FF91` `#1A9FFF` `#7759ED` `#ED59B2` |
| Sunset | dark | `#451A08` → `#0A3943` | `#FADDD1` | `#7698EF` | `#47E0FF` | `#ED5959` `#ED8659` `#EDD559` `#59ED7A` `#30BBE8` `#7759ED` `#ED59B2` |
| Midnight | dark | `#070034` → `#11005B` | `#FAF0FF` | `#B1A7FF` | `#F4C4FF` | `#F84141` `#FFC100` `#FEFF7F` `#63BA89` `#6AB7FB` `#C58AFA` `#FF5DB3` |
| Dawn | light | `#FFF1F7` → `#D0C1FF` | `#120032` | `#602AFF` | `#5A00FF` | `#E14848` `#E5753C` `#B7B400` `#00AC5D` `#4F80FF` `#9454FF` `#D756BF` |
| Overcast | light | `#D9F9FF` → `#C7E0FC` | `#002369` | `#0075FF` | `#0019FF` | `#EE5050` `#FA8542` `#EBA200` `#30B475` `#5271D8` `#B35AEB` `#DD43A7` |
| Noon | light | `#FFE7C6` → `#FCBFA5` | `#1E003C` | `#7B46FF` | `#6100FF` | `#DA4C4C` `#D76F33` `#D49200` `#09B664` `#5876D8` `#A543E3` `#C4228B` |

---

## 9. Tinycast translation recipes

How to reproduce each effect in the palette panel (`Core/PalettePanel.swift` +
`Features/`). All colors below assume Raycast Dark.

### 9.1 Window surface (replaces the tuned Liquid Glass material)

- Behind-window `NSVisualEffectView` (`.behindWindow`, `.hudWindow`/`.fullScreenUI`-class
  material — pick the one with the strongest desktop blur, state `.active`).
- On top: a plain scrim layer `NSColor.black.withAlphaComponent(0.4)` (SwiftUI:
  `Color.black.opacity(0.4)`). That single layer *is* the Raycast background.
- For themed gradients later: `LinearGradient(top: bg.opacity(0.4), bottom: bgSecondary.opacity(0.4))`.
- Corner radius 26 on the panel. Keep the existing corner-masking approach: the
  behind-window VEV needs a `maskImage` for the 26px corners, and any edge-blur layers must
  be inset past the corner arcs (CABackdropLayer cornerRadius clipping leaves white corners —
  verify over a light desktop, per project memory).
- Inactive panel (if ever shown non-key): dim content to 40% opacity and flatten the scrim
  toward `hsl(h, s·0.35, 15%)` of the bg.

### 9.2 Progressive edge blur under the header

Two viable routes:

1. **Native variable blur (preferred)**: a `CABackdropLayer`-based edge blur (the existing
   `EdgeBlur` machinery) with a vertical gradient mask; target max blur ≈ 3.6pt at the edge
   falling to 0 over the header height (~64pt). Raycast's ramp is roughly quadratic
   (0.25→3.6 over 9 steps).
2. **Literal port**: stack 9 blur layers, each a backdrop blur of
   `[0.25, 0.5, 0.75, 1, 1.4, 1.8, 2.3, 2.9, 3.6]` pt masked by a `CAGradientLayer` band
   12.5% of the header height wide (band slides toward the edge as radius grows; outermost
   layer's mask is solid at the edge fading out at 12.5%).

Either way: the layer lives *behind* the header content, above the list; header has no
opaque fill of its own — just the 1px white-10% separator at its bottom.

### 9.3 Scroll edge fade

SwiftUI `.mask` on the scroll view, driven by scroll offset (offset observable via the
existing list scroll machinery or an `onScrollGeometryChange` handler on macOS 26):

- fade zones: top = header overlap height, bottom ≈ footer overlap.
- opacity at edge: `1 − 0.85 · progress` (top), `1 − 0.75 · progress` (bottom), where
  `progress = clamp(scrolledDistance / fadeHeight, 0, 1)` — i.e. floor at 0.15 / 0.25.
- gradient stops: `clear at 0 → white(opacity) at midpoint → white at fadeHeight`, midpoint
  sliding from 0 to `fadeHeight/2` with progress.
- Mirror Raycast's `scroll-padding`: ensure keyboard selection scrolls rows clear of the
  faded zones (`ScrollViewProxy.scrollTo` with anchor padding).

### 9.4 Rows, selection, text

- Row: height ≈ 40pt, corner radius 10–12, horizontal content padding 8, icon 22pt for apps.
- Selected: `Color.white.opacity(0.10)`; hover: `0.05`; pressed can reuse selected.
- Text: primary `.white`, subtitle `.white.opacity(0.6)`, section headers & placeholders
  `.white.opacity(0.4)`, disabled `0.4`, faint `0.2`.
- Right-edge overflow: prefer a 100pt gradient mask fade over truncation for accessory overlap.

### 9.5 Footer / action bar

- 42–44pt tall, separator on top: 0.5pt white-10% line inset 1pt from edges.
- Buttons: label white, hover fill white-5%, radius 6–8.
- kbd chips: 18–20pt square-ish, radius ~4–6; either outline (white-20% 1pt inset stroke,
  text white-60%) or filled (white-10% fill, text white).

### 9.6 Shadows & panel border

- NSPanel shadow ≈ the 5-layer stack in §5; practically: keep the system shadow, or set
  `layer.shadowRadius ≈ 32, shadowOpacity ≈ 0.3, shadowOffset (0, -12)` for the dominant term.
- No border stroke on macOS (glass rim only). If a rim is needed over busy desktops, use
  white-10% at 0.5pt inside the 26px radius.

### 9.7 Typography

- SF Pro is the right substitute; don't port Inter. Base 13pt regular, secondary 13pt,
  section headers 11–13pt medium at white-40%, search field 16–18pt.
- Monospaced digits for hotkey hints (`.monospacedDigit()`).

### What deliberately NOT to copy

- Inter font + `ss03` glyph alternates (web-specific).
- `--zoom`-based pixel rounding (`round(calc(N * --spx), 1px)`) — AppKit handles scaling.
- The `.main-window-stabilizer` hack (WKWebView compositing workaround).
- Windows-specific fallbacks (`#333c` backdrop, 8px radius, inset borders).
