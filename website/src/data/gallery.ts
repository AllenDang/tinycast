// Drives the "Tinycast in action" gallery + lightbox. Each item is a tile in
// the grid and a slide in the lightbox. `src`/`thumb`/`poster` are resolved
// against import.meta.env.BASE_URL in the component, so give plain filenames
// that live in `public/` (e.g. "screenshot.png").
//
// DUMMY CONTENT: these reuse the two screenshots we already ship so the grid
// looks full. Swap in real captures/clips later. To add a clip, use the video
// shape shown in the commented template at the bottom — the lightbox already
// loads the video plugin.

export type GalleryItem = {
  type: "image" | "video";
  // Full-size media shown in the lightbox (image src, or video file for clips).
  src: string;
  // Grid thumbnail; falls back to `src`/`poster` when omitted.
  thumb?: string;
  // Poster frame for video tiles/slides.
  poster?: string;
  title: string;
  caption: string;
  width: number;
  height: number;
};

export const galleryItems: GalleryItem[] = [
  {
    type: "image",
    src: "screenshot.png",
    title: "App launcher",
    caption: "Fuzzy-search every app and open it with a keystroke.",
    width: 2451,
    height: 1510,
  },
  {
    type: "image",
    src: "import.png",
    title: "Import from Raycast",
    caption: "Bring your whole setup across in one click.",
    width: 1800,
    height: 1192,
  },
  {
    type: "image",
    src: "screenshot.png",
    title: "Clipboard history",
    caption: "Text and images, full-text searchable, always local.",
    width: 2451,
    height: 1510,
  },
  {
    type: "image",
    src: "import.png",
    title: "Inline calculator",
    caption: "Math and unit conversions right in the palette.",
    width: 1800,
    height: 1192,
  },
  {
    type: "image",
    src: "screenshot.png",
    title: "Emoji & symbols",
    caption: "Search the full set; your most-used float to the top.",
    width: 2451,
    height: 1510,
  },
  {
    type: "image",
    src: "import.png",
    title: "Hyper key",
    caption: "Turn Caps Lock into a whole extra shortcut layer.",
    width: 1800,
    height: 1192,
  },
];

// Video template — drop the .mp4 (and a poster frame) into `public/`, then copy
// an entry like this into the array above:
//
// {
//   type: "video",
//   src: "demo.mp4",
//   poster: "demo-poster.png",
//   title: "Live demo",
//   caption: "Watch the launcher in motion.",
//   width: 1920,
//   height: 1080,
// },
