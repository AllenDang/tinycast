import type { IconName } from "../components/ui/icon";

export type Feature = {
  icon: IconName;
  title: string;
  body: string;
  // `wide` features span two columns in the bento grid.
  wide?: boolean;
};

// The five things Tinycast does, in plain language. Sourced from the README so
// the copy stays true to what the app actually ships.
export const features: Feature[] = [
  {
    icon: "launch",
    title: "App launcher",
    body: "Fuzzy-search every app on your Mac and open it with a keystroke. Pin the ones you reach for, and see what's already running at a glance.",
    wide: true,
  },
  {
    icon: "clipboard",
    title: "Clipboard history",
    body: "Text and images, searchable, pasted straight back into the app you came from.",
  },
  {
    icon: "calculator",
    title: "Inline calculator",
    body: "Type math or unit conversions right in the palette and read the answer as you go.",
  },
  {
    icon: "globe",
    title: "Global hotkey",
    body: "One shortcut summons the palette from anywhere — over any app, full-screen or not.",
  },
  {
    icon: "bolt",
    title: "Per-app hotkeys",
    body: "Bind a key to an app to toggle it: press once to focus, again to hide.",
  },
];
