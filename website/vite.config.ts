import { defineConfig } from "vite";
import react from "@vitejs/plugin-react";

// Served as a GitHub Pages *project* site at https://abue-ammar.github.io/tinycast/,
// so all asset URLs must be prefixed with the repo path.
export default defineConfig({
  base: "/tinycast/",
  plugins: [react()],
});
