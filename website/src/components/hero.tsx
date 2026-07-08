import { site } from "../data/site";
import { AppShot } from "./app-shot";
import { Button } from "./ui/button";
import { AppleLogo, GitHubLogo } from "./ui/icon";
import { Kbd } from "./ui/kbd";
import { MetaStrip } from "./ui/meta-strip";

// The one place the system breaks its own austerity: a soft violet/cyan
// atmospheric wash borrowed from the app icon, then the page goes quiet.
// The glow styles live in index.css so they derive from the color tokens.
function Atmosphere() {
  return (
    <div
      className="pointer-events-none absolute inset-0 -z-10 overflow-hidden"
      aria-hidden="true"
    >
      <div className="hero-glow-violet" />
      <div className="hero-glow-cyan" />
      <div className="hero-fade" />
    </div>
  );
}

export function Hero() {
  return (
    <section id="top" className="relative overflow-hidden pb-8 pt-36 md:pt-48">
      <Atmosphere />
      <div className="container-page flex flex-col items-center text-center">
        <p
          className="rise font-mono text-eyebrow uppercase text-ash"
          style={{ animationDelay: "0ms" }}
        >
          Native macOS launcher
        </p>

        <h1
          className="rise mt-6 max-w-3xl text-display"
          style={{ animationDelay: "80ms" }}
        >
          Your shortcut to
          <br className="hidden sm:block" /> everything on your Mac.
        </h1>

        <p
          className="rise mt-6 max-w-xl text-body-lg text-ash"
          style={{ animationDelay: "160ms" }}
        >
          {site.name} is a tiny, fully native launcher — fuzzy app search, a
          calculator, clipboard history, and global hotkeys. Around a megabyte
          on disk. No Electron, no account, no telemetry.
        </p>

        <div
          className="rise mt-9 flex flex-wrap items-center justify-center gap-3"
          style={{ animationDelay: "240ms" }}
        >
          <Button href="#install">
            <AppleLogo size={16} />
            Download for Mac
          </Button>
          <Button
            href={site.repo}
            variant="ghost"
            target="_blank"
            rel="noreferrer"
          >
            <GitHubLogo size={16} />
            View source
          </Button>
        </div>

        <div className="rise mt-6" style={{ animationDelay: "300ms" }}>
          <MetaStrip />
        </div>

        <div
          className="rise mt-12 flex w-full flex-col items-center md:mt-16"
          style={{ animationDelay: "380ms" }}
        >
          <AppShot />
          <p className="mt-5 flex items-center gap-2 text-small text-smoke">
            Press <Kbd>⌥</Kbd> <Kbd>Space</Kbd> to summon it from anywhere
          </p>
        </div>
      </div>
    </section>
  );
}
