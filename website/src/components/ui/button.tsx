import type { AnchorHTMLAttributes, ReactNode } from "react";

type Variant = "solid" | "ghost";
type Size = "sm" | "md";

type ButtonProps = {
  children: ReactNode;
  variant?: Variant;
  size?: Size;
} & AnchorHTMLAttributes<HTMLAnchorElement>;

const variants: Record<Variant, string> = {
  // The only filled action in the system — neutral Mist, never chromatic.
  solid:
    "bg-mist text-iron shadow-cta hover:bg-white active:translate-y-px",
  // Edge-defined ghost: hairline border, fills only on hover.
  ghost:
    "text-ash border border-border hover:text-white hover:border-border-strong hover:bg-white/5",
};

const sizes: Record<Size, string> = {
  sm: "px-3 py-1.5",
  md: "px-4 py-2.5",
};

// A link styled as a button. Everything on this page is a link (download /
// anchor / repo), so an anchor is the honest element.
export function Button({
  children,
  variant = "solid",
  size = "md",
  className = "",
  ...props
}: ButtonProps) {
  return (
    <a
      className={`inline-flex items-center justify-center gap-2 rounded-lg text-small font-medium transition-colors duration-150 ${variants[variant]} ${sizes[size]} ${className}`}
      {...props}
    >
      {children}
    </a>
  );
}
