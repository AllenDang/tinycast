import { site } from "../data/site";
import { useLatestVersion } from "../lib/use-version";
import { Button } from "./ui/button";
import { icons } from "./ui/icon";
import { Kbd } from "./ui/kbd";
import { AppShot } from "./app-shot";

// The one place the system breaks its own austerity: a soft violet/cyan
// atmospheric wash borrowed from the app icon, then the page goes quiet.
function Atmosphere() {
  return (
    <div className="pointer-events-none absolute inset-0 -z-10 overflow-hidden" aria-hidden="true">
      <div
        className="absolute left-1/2 top-[-10%] h-[520px] w-[820px] -translate-x-1/2 rounded-full blur-[110px]"
        style={{
          background:
            "radial-gradient(closest-side, rgba(134,59,255,0.32), rgba(126,20,255,0.10), transparent)",
        }}
      />
      <div
        className="absolute left-[18%] top-[24%] h-[280px] w-[420px] -translate-x-1/2 rounded-full blur-[100px]"
        style={{ background: "radial-gradient(closest-side, rgba(71,191,255,0.16), transparent)" }}
      />
      {/* Hairline grid fade for the 'engineered surface' feel. */}
      <div
        className="absolute inset-0 opacity-[0.5]"
        style={{
          backgroundImage:
            "linear-gradient(to bottom, transparent, var(--color-void-black) 78%)",
        }}
      />
    </div>
  );
}

export function Hero() {
  const version = useLatestVersion();

  return (
    <section id="top" className="relative overflow-hidden pb-8 pt-40 md:pt-48">
      <Atmosphere />
      <div className="container-page flex flex-col items-center text-center">
        <p className="rise font-geistmono text-[11px] uppercase tracking-[0.16em] text-ash" style={{ animationDelay: "0ms" }}>
          Native macOS launcher
        </p>

        <h1
          className="rise mt-6 max-w-3xl text-[40px] font-normal leading-[1.08] tracking-[0.2px] sm:text-[52px] md:text-[64px]"
          style={{ animationDelay: "80ms" }}
        >
          Your shortcut to
          <br className="hidden sm:block" /> everything on your Mac.
        </h1>

        <p
          className="rise mt-6 max-w-xl text-[17px] leading-relaxed text-ash"
          style={{ animationDelay: "160ms" }}
        >
          {site.name} is a tiny, fully native launcher — fuzzy app search, a
          calculator, clipboard history, and global hotkeys. Around a megabyte on
          disk. No Electron, no account, no telemetry.
        </p>

        <div
          className="rise mt-9 flex flex-wrap items-center justify-center gap-3"
          style={{ animationDelay: "240ms" }}
        >
          <Button href="#install">
            {icons.apple({ size: 16 })}
            Download for Mac
          </Button>
          <Button href={site.repo} variant="ghost" target="_blank" rel="noreferrer">
            {icons.github({ size: 16 })}
            View source
          </Button>
        </div>

        <p
          className="rise mt-6 flex flex-wrap items-center justify-center gap-x-2.5 gap-y-1 font-geistmono text-[12px] text-smoke"
          style={{ animationDelay: "300ms" }}
        >
          <span>{version}</span>
          <span className="text-white/15">|</span>
          <span>{site.platform}</span>
          <span className="text-white/15">|</span>
          <span>{site.license}</span>
        </p>

        <div
          className="rise mt-16 flex w-full flex-col items-center"
          style={{ animationDelay: "380ms" }}
        >
          <AppShot />
          <p className="mt-5 flex items-center gap-2 text-[13px] text-smoke">
            Press <Kbd>⌥</Kbd> <Kbd>Space</Kbd> to summon it from anywhere
          </p>
        </div>
      </div>
    </section>
  );
}
