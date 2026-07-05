import type { ReactNode } from "react";

type SectionProps = {
  id?: string;
  eyebrow?: string;
  title?: ReactNode;
  intro?: ReactNode;
  children: ReactNode;
  className?: string;
};

// A contained page section with the shared vertical rhythm and an optional
// eyebrow/title/intro header. Keeps every band spaced and aligned identically.
export function Section({
  id,
  eyebrow,
  title,
  intro,
  children,
  className = "",
}: SectionProps) {
  return (
    <section id={id} className={`container-page py-20 md:py-28 ${className}`}>
      {(eyebrow || title || intro) && (
        <header className="mx-auto mb-14 max-w-2xl text-center">
          {eyebrow && (
            <p className="mb-4 font-geistmono text-[11px] uppercase tracking-[0.14em] text-violet-bright">
              {eyebrow}
            </p>
          )}
          {title && (
            <h2 className="text-[32px] font-normal leading-tight md:text-[40px]">
              {title}
            </h2>
          )}
          {intro && (
            <p className="mt-4 text-[17px] leading-relaxed text-ash">{intro}</p>
          )}
        </header>
      )}
      {children}
    </section>
  );
}
