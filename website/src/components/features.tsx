import { features } from "../data/features";
import type { Feature } from "../data/features";
import { icons } from "./ui/icon";
import { Section } from "./ui/section";

function FeatureCard({ icon, title, body, wide }: Feature) {
  return (
    <article
      className={`group flex flex-col gap-4 rounded-2xl bg-ink/40 p-6 transition-shadow duration-200 ${
        wide ? "sm:col-span-2" : ""
      }`}
      style={{ boxShadow: "var(--shadow-key)" }}
    >
      <span className="flex size-11 items-center justify-center rounded-full bg-white/[0.04] text-violet-bright shadow-[inset_0_1px_0_rgba(255,255,255,0.08)] transition-colors group-hover:bg-violet/[0.12]">
        {icons[icon]({ size: 22 })}
      </span>
      <h3 className="text-[20px] font-medium">{title}</h3>
      <p className="text-[15px] leading-relaxed text-ash">{body}</p>
    </article>
  );
}

export function Features() {
  return (
    <Section
      id="features"
      eyebrow="What it does"
      title="Everything you reach for, one keystroke away."
      intro="Five focused tools in a single palette — the launcher you actually use, without the surface area you don't."
    >
      <div className="grid gap-4 sm:grid-cols-2 lg:grid-cols-3">
        {features.map((feature) => (
          <FeatureCard key={feature.title} {...feature} />
        ))}
      </div>
    </Section>
  );
}
