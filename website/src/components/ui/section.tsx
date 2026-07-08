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
    <section id={id} className={`container-page py-16 md:py-24 ${className}`}>
      {(eyebrow || title || intro) && (
        <header className="mx-auto mb-10 max-w-2xl text-center md:mb-14">
          {eyebrow && (
            <p className="mb-4 font-mono text-eyebrow uppercase text-violet-bright">
              {eyebrow}
            </p>
          )}
          {title && <h2 className="text-heading font-normal">{title}</h2>}
          {intro && <p className="mt-4 text-body-lg text-ash">{intro}</p>}
        </header>
      )}
      {children}
    </section>
  );
}
