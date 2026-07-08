import { Check } from "lucide-react";
import { values } from "../data/ethos";
import { stats } from "../data/site";
import { Reveal } from "./ui/reveal";
import { Section } from "./ui/section";

export function Ethos() {
  return (
    <Section
      id="why"
      eyebrow="Why it's tiny"
      title="Built like a Mac app should be."
      intro="SwiftUI and AppKit, zero dependencies, no Electron runtime hiding underneath. It's fast because there's barely anything to it."
    >
      {/* Stat strip — the one place numbers get loud. */}
      <Reveal className="mb-10 md:mb-14">
        <div className="grid grid-cols-2 gap-px overflow-hidden rounded-2xl bg-white/5 shadow-key md:grid-cols-4">
          {stats.map((stat) => (
            <div
              key={stat.label}
              className="bg-ink px-4 py-6 text-center sm:px-6 sm:py-8"
            >
              <div className="text-stat font-medium text-white">
                {stat.value}
                {stat.unit && (
                  <span className="ml-1 text-body-lg text-ash">
                    {stat.unit}
                  </span>
                )}
              </div>
              <div className="mt-3 font-mono text-eyebrow uppercase text-smoke">
                {stat.label}
              </div>
            </div>
          ))}
        </div>
      </Reveal>

      <div className="grid gap-4 sm:grid-cols-2">
        {values.map((value, i) => (
          <Reveal key={value.title} delay={i * 60}>
            <article className="flex h-full gap-4 rounded-2xl border border-border p-4 sm:p-6">
              <span className="mt-0.5 flex size-6 shrink-0 items-center justify-center rounded-full bg-violet/15 text-violet-bright">
                <Check size={15} strokeWidth={2} />
              </span>
              <div>
                <h3 className="text-body-lg font-medium">{value.title}</h3>
                <p className="mt-1.5 text-body text-ash">{value.body}</p>
              </div>
            </article>
          </Reveal>
        ))}
      </div>
    </Section>
  );
}
