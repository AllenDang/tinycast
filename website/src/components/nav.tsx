import { Menu, X } from "lucide-react";
import { useState } from "react";
import { nav, site } from "../data/site";
import { Button } from "./ui/button";
import { AppleLogo, Logo } from "./ui/icon";

function navLinkProps(href: string) {
  return href.startsWith("http")
    ? { target: "_blank", rel: "noreferrer" as const }
    : {};
}

export function Nav() {
  const [open, setOpen] = useState(false);

  return (
    <header className="fixed inset-x-0 top-4 z-50">
      <div className="container-page">
        <nav className="rounded-xl border border-border bg-void-black/60 backdrop-blur-2xl">
          <div className="flex items-center justify-between gap-4 px-3 py-2">
            <a
              href="#top"
              className="flex items-center gap-2 pl-1 text-body font-semibold text-white"
              onClick={() => setOpen(false)}
            >
              <Logo size={20} />
              {site.name}
            </a>

            <div className="hidden items-center gap-1 md:flex">
              {nav.map((item) => (
                <a
                  key={item.label}
                  href={item.href}
                  {...navLinkProps(item.href)}
                  className="rounded-md px-3 py-1.5 text-small font-medium text-ash transition-colors hover:text-white"
                >
                  {item.label}
                </a>
              ))}
            </div>

            <div className="flex items-center gap-2">
              <Button href="#install" size="sm" onClick={() => setOpen(false)}>
                <AppleLogo size={14} />
                Download
              </Button>
              <button
                type="button"
                onClick={() => setOpen((o) => !o)}
                aria-expanded={open}
                aria-controls="mobile-nav"
                aria-label={open ? "Close menu" : "Open menu"}
                className="flex size-8 items-center justify-center rounded-md text-ash transition-colors hover:bg-white/5 hover:text-white md:hidden"
              >
                {open ? <X size={18} /> : <Menu size={18} />}
              </button>
            </div>
          </div>

          {/* Mobile menu — the pill expands downward, Raycast-style. */}
          {open && (
            <div id="mobile-nav" className="border-t border-border p-2 md:hidden">
              {nav.map((item) => (
                <a
                  key={item.label}
                  href={item.href}
                  {...navLinkProps(item.href)}
                  onClick={() => setOpen(false)}
                  className="block rounded-lg px-3 py-2.5 text-body font-medium text-ash transition-colors hover:bg-white/5 hover:text-white"
                >
                  {item.label}
                </a>
              ))}
            </div>
          )}
        </nav>
      </div>
    </header>
  );
}
