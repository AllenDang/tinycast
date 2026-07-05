import { site } from "../data/site";
import { useLatestVersion } from "../lib/use-version";
import { icons, Logo } from "./ui/icon";

export function Footer() {
  const version = useLatestVersion();

  return (
    <footer className="border-t border-white/[0.06]">
      <div className="container-page flex flex-col items-center gap-6 py-14 text-center">
        <a href="#top" className="flex items-center gap-2 text-[15px] font-medium text-white">
          <Logo size={20} />
          {site.name}
        </a>

        {/* Meta strip — mono, pipe-separated, signalling technical metadata. */}
        <p className="flex flex-wrap items-center justify-center gap-x-2.5 gap-y-1 font-geistmono text-[12px] text-smoke">
          <span>{version}</span>
          <span className="text-white/15">|</span>
          <span>{site.platform}</span>
          <span className="text-white/15">|</span>
          <a href={site.licenseUrl} target="_blank" rel="noreferrer" className="transition-colors hover:text-ash">
            {site.license}
          </a>
          <span className="text-white/15">|</span>
          <span>Made for people who like their Mac fast</span>
        </p>

        <a
          href={site.repo}
          target="_blank"
          rel="noreferrer"
          className="flex items-center gap-2 text-[13px] text-ash transition-colors hover:text-white"
        >
          {icons.github({ size: 16 })}
          github.com/abue-ammar/tinycast
        </a>
      </div>
    </footer>
  );
}
