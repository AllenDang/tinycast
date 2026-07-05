import { useState } from "react";
import { channels, quarantineCommand, site } from "../data/site";
import { Button } from "./ui/button";
import { icons } from "./ui/icon";
import { Section } from "./ui/section";

// A terminal-style command line with a copy button. The mono treatment signals
// "this is a command to run," and copy is the one action people want here.
function CopyCommand({ command }: { command: string }) {
  const [copied, setCopied] = useState(false);

  async function copy() {
    try {
      await navigator.clipboard.writeText(command);
      setCopied(true);
      setTimeout(() => setCopied(false), 1600);
    } catch {
      // Clipboard blocked (e.g. insecure context) — the text stays selectable.
    }
  }

  return (
    <div className="flex items-center gap-3 rounded-lg bg-obsidian px-4 py-3 shadow-[var(--shadow-subtle-3)]">
      <span className="select-none text-smoke">{icons.terminal({ size: 16 })}</span>
      <code className="flex-1 overflow-x-auto whitespace-nowrap font-geistmono text-[13px] text-white">
        {command}
      </code>
      <button
        type="button"
        onClick={copy}
        className="shrink-0 rounded-md px-2 py-1 font-geistmono text-[12px] text-ash transition-colors hover:bg-white/[0.06] hover:text-white"
        aria-label={copied ? "Copied" : "Copy command"}
      >
        {copied ? "Copied" : "Copy"}
      </button>
    </div>
  );
}

export function Install() {
  const [active, setActive] = useState(0);
  const channel = channels[active];

  return (
    <Section
      id="install"
      eyebrow="Get it"
      title="Install with Homebrew."
      intro="One command and you're running. Pick a channel — each installs as its own app, so a pre-release can live next to stable."
    >
      <div className="mx-auto max-w-2xl">
        {/* Channel picker */}
        <div className="mb-3 inline-flex rounded-lg bg-white/[0.04] p-1">
          {channels.map((c, i) => (
            <button
              key={c.id}
              type="button"
              onClick={() => setActive(i)}
              className={`rounded-md px-4 py-1.5 text-[13px] font-medium transition-colors ${
                i === active
                  ? "bg-mist text-iron"
                  : "text-ash hover:text-white"
              }`}
            >
              {c.label}
            </button>
          ))}
        </div>

        <div className="mb-3 flex items-center gap-2 font-geistmono text-[12px] text-smoke">
          <span className="rounded bg-graphite px-1.5 py-0.5 text-ash">
            {channel.note}
          </span>
        </div>

        <CopyCommand command={channel.command} />

        {/* The one manual step, stated plainly rather than hidden. */}
        <div className="mt-8 rounded-2xl border border-[#363739] p-6">
          <h3 className="text-[16px] font-medium">One-time: clear the quarantine flag</h3>
          <p className="mt-2 text-[14px] leading-relaxed text-ash">
            Tinycast isn't notarized — there's no paid Developer ID behind it — so
            macOS quarantines it on first launch. Run this once to let it open:
          </p>
          <div className="mt-4">
            <CopyCommand command={quarantineCommand} />
          </div>
        </div>

        <div className="mt-8 flex flex-wrap justify-center gap-3">
          <Button href={`${site.repo}/releases`} variant="ghost" target="_blank" rel="noreferrer">
            {icons.arrowUpRight({ size: 16 })}
            Or grab the .dmg from Releases
          </Button>
        </div>
      </div>
    </Section>
  );
}
