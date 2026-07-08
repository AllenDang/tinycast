import type { ReactNode } from "react";

// A single keycap — the tactile motif that runs through the whole page.
export function Kbd({ children }: { children: ReactNode }) {
  return (
    <kbd className="inline-flex min-w-5 items-center justify-center rounded-md bg-white/5 px-1.5 py-0.5 font-mono text-caption leading-none text-ash shadow-keycap">
      {children}
    </kbd>
  );
}
