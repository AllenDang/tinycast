import type { AnchorHTMLAttributes, ReactNode } from "react";

type Variant = "solid" | "ghost";

type ButtonProps = {
  children: ReactNode;
  variant?: Variant;
} & AnchorHTMLAttributes<HTMLAnchorElement>;

const variants: Record<Variant, string> = {
  // The only filled action in the system — neutral Mist, never chromatic.
  solid:
    "bg-mist text-iron shadow-[var(--shadow-cta)] hover:bg-white active:translate-y-px",
  // Edge-defined ghost: hairline border, fills only on hover.
  ghost:
    "text-ash border border-[#363739] hover:text-white hover:border-[#54555a] hover:bg-white/[0.03]",
};

// A link styled as a button. Everything on this page is a link (download /
// anchor / repo), so an anchor is the honest element.
export function Button({
  children,
  variant = "solid",
  className = "",
  ...props
}: ButtonProps) {
  return (
    <a
      className={`inline-flex items-center justify-center gap-2 rounded-lg px-4 py-2.5 text-[14px] font-medium transition-colors duration-150 ${variants[variant]} ${className}`}
      {...props}
    >
      {children}
    </a>
  );
}
