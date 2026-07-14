import { Check, X } from "lucide-react";
import { compareRows, compareSource, type Cell } from "../data/comparison";
import { cn } from "../lib/cn";
import { Logo, RaycastLogo } from "./ui/icon";
import { Reveal } from "./ui/reveal";
import { Section } from "./ui/section";

// Shared column template — the label column is wider, the two value columns
// equal. Kept in one place so the header and every row line up exactly.
const cols = "grid grid-cols-[minmax(0,1.6fr)_minmax(0,1fr)_minmax(0,1fr)]";

// The Tinycast column runs 1.6/3.6 in from the left and is 1/3.6 wide; the
// highlight panel is positioned to match, so it reads as a single card behind
// the whole column rather than a tint on each cell.
const winnerLeft = "calc(100% * 1.6 / 3.6)";
const winnerWidth = "calc(100% / 3.6)";

// One cell's value: a boolean becomes a check/cross, a string prints as-is.
// `own` is Tinycast's column — its checks glow violet and its text goes white.
function Value({ value, own }: { value: Cell; own: boolean }) {
  if (typeof value === "boolean") {
    return value ? (
      <Check
        size={18}
        strokeWidth={2.4}
        className={own ? "text-violet-bright" : "text-ash"}
        aria-label="Yes"
      />
    ) : (
      <X size={17} strokeWidth={2} className="text-smoke" aria-label="No" />
    );
  }
  return (
    <span
      className={cn(
        "text-small text-balance",
        own ? "font-medium text-white" : "text-ash",
      )}
    >
      {value}
    </span>
  );
}

export function Compare() {
  return (
    <Section
      id="compare"
      eyebrow="Tinycast vs Raycast"
      title="The essentials, minus the weight."
      intro="Everything you actually reach for is here — then Tinycast wins on the things that don't show up in a feature list: size, price, and who owns your data."
    >
      <Reveal className="mx-auto max-w-4xl">
        <div className="overflow-x-auto rounded-2xl border border-border shadow-key">
          <div className="relative min-w-152">
            {/* The "winner column" — one continuous panel behind Tinycast. */}
            <div
              aria-hidden="true"
              className="pointer-events-none absolute inset-y-0 z-0 rounded-xl bg-violet/[0.07] ring-1 ring-inset ring-violet/20"
              style={{ left: winnerLeft, width: winnerWidth }}
            />

            <div className="relative z-10">
              {/* Header */}
              <div className={cn(cols, "border-b border-border")}>
                <div className="flex items-center px-5 py-4 font-mono text-eyebrow uppercase text-smoke">
                  Feature
                </div>
                <div className="flex items-center justify-center gap-1.5 px-4 py-4 text-body-lg font-medium text-white">
                  <Logo size={19} />
                  Tinycast
                </div>
                <div className="flex items-center justify-center gap-1.5 px-4 py-4 text-body-lg font-medium text-ash">
                  <RaycastLogo size={17} />
                  Raycast
                </div>
              </div>

              {/* Rows */}
              {compareRows.map((row) => (
                <div
                  key={row.label}
                  className={cn(
                    cols,
                    "border-b border-border/50 last:border-b-0",
                  )}
                >
                  <div className="flex items-center px-5 py-3.5 text-small text-ash">
                    {row.label}
                    {row.sourced && (
                      <sup className="ml-0.5 text-violet-bright">†</sup>
                    )}
                  </div>
                  <div className="flex items-center justify-center px-4 py-3.5 text-center">
                    <Value value={row.tinycast} own />
                  </div>
                  <div className="flex items-center justify-center px-4 py-3.5 text-center">
                    <Value value={row.raycast} own={false} />
                  </div>
                </div>
              ))}
            </div>
          </div>
        </div>

        {/* The one external claim, cited so it holds up. */}
        <p className="mt-4 text-center font-mono text-caption text-smoke">
          <span className="text-violet-bright">†</span> Stack and memory figures
          from{" "}
          <a
            href={compareSource.href}
            target="_blank"
            rel="noreferrer"
            className="underline decoration-border underline-offset-2 transition-colors hover:text-ash"
          >
            {compareSource.label}
          </a>
          .
        </p>
      </Reveal>
    </Section>
  );
}
