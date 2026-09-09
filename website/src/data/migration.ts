// Drives the "Switch from Raycast" section. The steps mirror the real import
// flow (Settings → Backup → Import from Raycast), and `transfers` matches the
// app's `RaycastImportOptions` exactly — don't add anything the importer can't
// actually carry over.

export const migration = {
  eyebrow: "Coming from Raycast?",
  title: "Bring your essentials from Raycast.",
  intro:
    "Tinycast reads a Raycast export directly. Point it at your .rayconfig file, type your passphrase, and your setup comes across — no redoing shortcuts by hand.",
  steps: [
    {
      title: "Export from Raycast",
      body: "Raycast → Settings → Advanced → Export, and set a passphrase.",
    },
    {
      title: "Import into Tinycast",
      body: "Open the palette, run “Import from Raycast,” and choose the file.",
    },
    {
      title: "Pick what to bring",
      body: "Keep it all or just the parts you want — then you're set up.",
    },
  ],
  // Must match RaycastImportOptions in RaycastFormat.swift.
  transfers: [
    "Shortcuts",
    "Favorites",
    "Clipboard history",
    "Launch at login",
    "Menu-bar preference",
  ],
} as const;
