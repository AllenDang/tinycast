import { features } from "../data/features";
import type { Feature } from "../data/features";
import { featureIcons } from "./ui/feature-icons";
import { Reveal } from "./ui/reveal";
import { Section } from "./ui/section";

function FeatureCard({ icon, title, body }: Feature) {
  const Icon = featureIcons[icon];
  return (
    <article className="group flex h-full flex-col gap-4 rounded-2xl bg-ink/40 p-4 shadow-key transition-shadow duration-200 hover:shadow-key-hover sm:p-6">
      <span className="flex size-11 items-center justify-center rounded-full bg-white/5 text-violet-bright shadow-highlight transition-colors group-hover:bg-violet/10">
        <Icon size={22} strokeWidth={1.6} />
      </span>
      <h3 className="text-subheading font-medium">{title}</h3>
      <p className="text-body text-ash">{body}</p>
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
        {features.map((feature, i) => (
          <Reveal
            key={feature.title}
            delay={i * 60}
            className={feature.wide ? "sm:col-span-2" : undefined}
          >
            <FeatureCard {...feature} />
          </Reveal>
        ))}
      </div>
    </Section>
  );
}
