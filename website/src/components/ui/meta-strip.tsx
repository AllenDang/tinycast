import { site } from "../../data/site";
import { useLatestVersion } from "../../lib/use-version";

// Version | platform | license — the mono metadata line used under the hero
// CTAs and in the footer, so the two never drift apart.
export function MetaStrip() {
  const version = useLatestVersion();

  return (
    <p className="flex flex-wrap items-center justify-center gap-x-2.5 gap-y-1 font-mono text-caption text-smoke">
      <span>{version}</span>
      <span aria-hidden="true" className="text-white/15">
        |
      </span>
      <span>{site.platform}</span>
      <span aria-hidden="true" className="text-white/15">
        |
      </span>
      <a
        href={site.licenseUrl}
        target="_blank"
        rel="noreferrer"
        className="transition-colors hover:text-ash"
      >
        {site.license}
      </a>
    </p>
  );
}
