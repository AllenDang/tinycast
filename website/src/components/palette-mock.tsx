import type { IconName } from "./ui/icon";
import { icons } from "./ui/icon";
import { Kbd } from "./ui/kbd";

type Row = {
  icon: IconName;
  name: string;
  meta: string;
  tint: string;
  running?: boolean;
};

// A faux launcher view: what you see the instant the palette floats in.
// Not wired to anything — it's the product, rendered as the hero.
const rows: Row[] = [
  { icon: "terminal", name: "Terminal", meta: "Application", tint: "#3a3d42", running: true },
  { icon: "globe", name: "Safari", meta: "Application", tint: "#1f4a63" },
  { icon: "calculator", name: "Calculator", meta: "Application", tint: "#2a2140" },
  { icon: "clipboard", name: "Clipboard History", meta: "Command", tint: "#2e2f31" },
  { icon: "check", name: "Reminders", meta: "Application", tint: "#1e3a2c" },
];

function AppTile({ icon, tint }: { icon: IconName; tint: string }) {
  return (
    <span
      className="flex size-[34px] shrink-0 items-center justify-center rounded-[9px] text-white/90 shadow-[inset_0_1px_0_rgba(255,255,255,0.12),inset_0_0_0_1px_rgba(0,0,0,0.3)]"
      style={{ background: `linear-gradient(160deg, ${tint}, #16171a)` }}
    >
      {icons[icon]({ size: 18, strokeWidth: 1.7 })}
    </span>
  );
}

export function PaletteMock() {
  return (
    <div
      className="relative w-full max-w-[560px] overflow-hidden rounded-2xl bg-ink/95 backdrop-blur-xl"
      style={{ boxShadow: "var(--shadow-key), var(--shadow-xl)" }}
      role="img"
      aria-label="The Tinycast command palette showing an app search with results and keyboard hints"
    >
      {/* Search field */}
      <div className="flex items-center gap-3 px-5 pb-3 pt-4">
        <span className="text-smoke">{icons.launch({ size: 20 })}</span>
        <div className="flex flex-1 items-center text-[17px] text-smoke">
          <span>Search apps and commands</span>
          <span className="caret ml-0.5 inline-block h-[19px] w-px bg-violet-bright" />
        </div>
        <span className="rounded-md bg-white/[0.06] px-2 py-1 font-geistmono text-[11px] text-ash">
          Apps
        </span>
      </div>

      <div className="h-px bg-white/[0.07]" />

      {/* Results */}
      <ul className="p-2">
        {rows.map((row, i) => {
          const selected = i === 0;
          return (
            <li
              key={row.name}
              className={`relative flex items-center gap-3 rounded-[10px] px-3 py-2 ${
                selected ? "bg-violet/[0.16]" : ""
              }`}
            >
              {selected && (
                <span className="absolute left-0 top-1/2 h-5 -translate-y-1/2 rounded-full bg-violet-bright" style={{ width: 3 }} />
              )}
              <AppTile icon={row.icon} tint={row.tint} />
              <span className="flex-1 text-[15px] text-white">{row.name}</span>
              {row.running && (
                <span className="size-1.5 rounded-full bg-success-green shadow-[0_0_6px_var(--color-success-green)]" />
              )}
              <span className="font-geistmono text-[12px] text-smoke">
                {row.meta}
              </span>
            </li>
          );
        })}
      </ul>

      {/* Action bar */}
      <div className="flex items-center justify-between border-t border-white/[0.07] px-4 py-2.5 text-[12px] text-smoke">
        <div className="flex items-center gap-1.5">
          <Kbd>↩</Kbd>
          <span>Open</span>
        </div>
        <div className="flex items-center gap-4">
          <span className="flex items-center gap-1.5">
            <Kbd>⇥</Kbd> Clipboard
          </span>
          <span className="flex items-center gap-1.5">
            <Kbd>⌘</Kbd>
            <Kbd>,</Kbd> Settings
          </span>
        </div>
      </div>
    </div>
  );
}
