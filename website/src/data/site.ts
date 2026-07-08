// Single source of truth for links, install commands, and metadata used across
// the page. Update these in one place rather than hunting through components.

export const site = {
  name: "Tinycast",
  tagline: "The essentials, without the bloat.",
  repo: "https://github.com/abue-ammar/tinycast",
  version: "v0.1.0",
  platform: "macOS 26+",
  license: "GPL-3.0",
  licenseUrl: "https://github.com/abue-ammar/tinycast/blob/main/LICENSE",
} as const;

export const nav = [
  { label: "Features", href: "#features" },
  { label: "Why tiny", href: "#why" },
  { label: "Install", href: "#install" },
  { label: "Source", href: site.repo },
] as const;

// Homebrew install channels. Each is a separate app that runs side by side.
export const channels = [
  {
    id: "stable",
    label: "Stable",
    command: "brew install --cask tinycast",
    note: "Recommended",
  },
  {
    id: "beta",
    label: "Beta",
    command: "brew install --cask tinycast@beta",
    note: "Side-by-side",
  },
  {
    id: "alpha",
    label: "Alpha",
    command: "brew install --cask tinycast@alpha",
    note: "Side-by-side",
  },
] as const;

// The one manual step: Tinycast isn't notarized (no $99/yr Developer ID), so
// macOS quarantines it. Clearing the flag once is expected.
export const quarantineCommand =
  'xattr -dr com.apple.quarantine "/Applications/Tinycast.app"';

// Headline numbers for the "why it's tiny" band. Kept honest, from the README.
export const stats = [
  { value: "~3", unit: "MB", label: "On disk" },
  { value: "<100", unit: "MB", label: "Memory" },
  { value: "0", unit: "", label: "Dependencies" },
  { value: "0", unit: "", label: "Telemetry" },
] as const;
