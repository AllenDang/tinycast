import type { ReactNode } from "react";

// A single keycap — the tactile motif that runs through the whole page.
export function Kbd({ children }: { children: ReactNode }) {
  return (
    <kbd className="inline-flex min-w-[20px] items-center justify-center rounded-[5px] bg-white/[0.06] px-1.5 py-0.5 font-geistmono text-[11px] leading-none text-ash shadow-[inset_0_1px_0_rgba(255,255,255,0.08),inset_0_-1px_0_rgba(0,0,0,0.4)]">
      {children}
    </kbd>
  );
}
