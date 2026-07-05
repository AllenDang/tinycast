import { nav, site } from "../data/site";
import { Button } from "./ui/button";
import { icons, Logo } from "./ui/icon";

export function Nav() {
  return (
    <header className="fixed inset-x-0 top-4 z-50 flex justify-center px-4">
      <nav className="flex w-full max-w-6xl items-center justify-between gap-4 rounded-xl border border-[#363739] bg-void-black/60 px-3 py-2 backdrop-blur-2xl">
        <a
          href="#top"
          className="flex items-center gap-2 pl-1 text-[14px] font-medium text-white"
        >
          <Logo size={20} />
          {site.name}
        </a>

        <div className="hidden items-center gap-1 md:flex">
          {nav.map((item) => {
            const external = item.href.startsWith("http");
            return (
              <a
                key={item.label}
                href={item.href}
                {...(external ? { target: "_blank", rel: "noreferrer" } : {})}
                className="rounded-md px-3 py-1.5 text-[13px] text-ash transition-colors hover:text-white"
              >
                {item.label}
              </a>
            );
          })}
        </div>

        <Button href="#install" className="px-3 py-1.5 text-[13px]">
          {icons.apple({ size: 15 })}
          Download
        </Button>
      </nav>
    </header>
  );
}
