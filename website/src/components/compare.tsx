import { Check, X } from "lucide-react";
import {
  compareRows,
  compareSource,
  type Cell,
} from "../data/comparison";
import { cn } from "../lib/cn";
import { Logo } from "./ui/icon";
import { Reveal } from "./ui/reveal";
import { Section } from "./ui/section";

// One cell's value: a boolean becomes a check/cross, a string prints as-is.
// `own` is Tinycast's column — its checks glow violet and its text goes white.
function Value({ value, own }: { value: Cell; own: boolean }) {
  if (typeof value === "boolean") {
    return value ? (
      <Check
        size={17}
        strokeWidth={2.4}
        className={own ? "text-violet-bright" : "text-ash"}
        aria-label="Yes"
      />
    ) : (
      <X
        size={16}
        strokeWidth={2}
        className="text-smoke"
        aria-label="No"
      />
    );
  }
  return (
    <span
      className={cn("text-small", own ? "font-medium text-white" : "text-ash")}
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
      <Reveal className="mx-auto max-w-3xl">
        <div className="overflow-x-auto rounded-2xl border border-border shadow-key">
          <div className="min-w-[34rem]">
            {/* Header */}
            <div className="grid grid-cols-[minmax(0,1.5fr)_minmax(0,1fr)_minmax(0,1fr)] items-center border-b border-border">
              <div className="px-4 py-4 font-mono text-eyebrow uppercase text-smoke">
                Feature
              </div>
              <div className="flex items-center justify-center gap-1.5 bg-violet/[0.06] px-4 py-4 text-body font-medium text-white">
                <Logo size={18} />
                Tinycast
              </div>
              <div className="px-4 py-4 text-center text-body font-medium text-ash">
                Raycast
              </div>
            </div>

            {/* Rows */}
            {compareRows.map((row) => (
              <div
                key={row.label}
                className="grid grid-cols-[minmax(0,1.5fr)_minmax(0,1fr)_minmax(0,1fr)] items-center border-b border-border/60 last:border-b-0"
              >
                <div className="px-4 py-3 text-small text-ash">
                  {row.label}
                  {row.sourced && (
                    <sup className="ml-0.5 text-violet-bright">†</sup>
                  )}
                </div>
                <div className="flex items-center justify-center bg-violet/[0.06] px-4 py-3 text-center">
                  <Value value={row.tinycast} own />
                </div>
                <div className="flex items-center justify-center px-4 py-3 text-center">
                  <Value value={row.raycast} own={false} />
                </div>
              </div>
            ))}
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
