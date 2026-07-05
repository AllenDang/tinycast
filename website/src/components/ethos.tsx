import { site, stats } from "../data/site";
import { icons } from "./ui/icon";
import { Section } from "./ui/section";

// The values that make Tinycast Tinycast. Each is a plain promise, not a pitch.
const values = [
  {
    title: "Free and open source",
    body: `Every line is public under the ${site.license} license. Read it, fork it, build it yourself.`,
  },
  {
    title: "Local by design",
    body: "Your apps, clipboard, and shortcuts stay on your Mac. Nothing is uploaded, ever.",
  },
  {
    title: "No account, no sign-in",
    body: "Install it and it works. There's no login, no paywall, and no pro tier.",
  },
  {
    title: "Zero telemetry",
    body: "No analytics, no crash pings, no background phone-home. It does nothing you didn't ask for.",
  },
];

export function Ethos() {
  return (
    <Section
      id="why"
      eyebrow="Why it's tiny"
      title="Built like a Mac app should be."
      intro="SwiftUI and AppKit, zero dependencies, no Electron runtime hiding underneath. It's fast because there's barely anything to it."
    >
      {/* Stat strip — SF Pro numerals, the one place numbers get loud. */}
      <div
        className="mb-14 grid grid-cols-2 gap-px overflow-hidden rounded-2xl bg-white/[0.06] md:grid-cols-4"
        style={{ boxShadow: "var(--shadow-key)" }}
      >
        {stats.map((stat) => (
          <div key={stat.label} className="bg-ink px-6 py-8 text-center">
            <div className="font-sf-pro-text text-[38px] font-medium leading-none text-white">
              {stat.value}
              {stat.unit && (
                <span className="ml-1 text-[18px] text-ash">{stat.unit}</span>
              )}
            </div>
            <div className="mt-3 font-geistmono text-[12px] uppercase tracking-[0.08em] text-smoke">
              {stat.label}
            </div>
          </div>
        ))}
      </div>

      <div className="grid gap-4 sm:grid-cols-2">
        {values.map((value) => (
          <article
            key={value.title}
            className="flex gap-4 rounded-2xl border border-[#363739] p-6"
          >
            <span className="mt-0.5 flex size-6 shrink-0 items-center justify-center rounded-full bg-violet/[0.14] text-violet-bright">
              {icons.check({ size: 15, strokeWidth: 2 })}
            </span>
            <div>
              <h3 className="text-[17px] font-medium">{value.title}</h3>
              <p className="mt-1.5 text-[15px] leading-relaxed text-ash">
                {value.body}
              </p>
            </div>
          </article>
        ))}
      </div>
    </Section>
  );
}
