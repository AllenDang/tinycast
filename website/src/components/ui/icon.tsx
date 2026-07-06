import type { SVGProps } from "react";

// The Tinycast mark — the lightning-Z from the app icon, filled with the brand
// violet gradient. Single flat path (the app icon's blurred layers are dropped).
export function Logo({
  size = 22,
  ...props
}: { size?: number } & SVGProps<SVGSVGElement>) {
  return (
    <svg
      width={size}
      height={(size * 46) / 48}
      viewBox="0 0 48 46"
      fill="none"
      aria-hidden="true"
      {...props}
    >
      <defs>
        <linearGradient
          id="tc-mark"
          x1="0"
          y1="0"
          x2="40"
          y2="46"
          gradientUnits="userSpaceOnUse"
        >
          <stop stopColor="#a875ff" />
          <stop offset="0.6" stopColor="#863bff" />
          <stop offset="1" stopColor="#7e14ff" />
        </linearGradient>
      </defs>
      <path
        fill="url(#tc-mark)"
        d="M25.842 44.938c-.664.844-2.021.375-2.021-.698V33.937a2.26 2.26 0 0 0-2.262-2.262H10.183c-.92 0-1.456-1.04-.92-1.788l7.48-10.471c1.07-1.498 0-3.579-1.842-3.579H1.133c-.92 0-1.456-1.04-.92-1.787L9.91.473c.214-.297.556-.474.92-.474h28.894c.92 0 1.456 1.04.92 1.788l-7.48 10.471c-1.07 1.498 0 3.578 1.842 3.578h11.377c.943 0 1.473 1.088.89 1.832L25.843 44.94z"
      />
    </svg>
  );
}

type IconProps = { size?: number } & SVGProps<SVGSVGElement>;

function base(size: number, props: SVGProps<SVGSVGElement>) {
  return {
    width: size,
    height: size,
    viewBox: "0 0 24 24",
    fill: "none",
    stroke: "currentColor",
    strokeWidth: 1.6,
    strokeLinecap: "round" as const,
    strokeLinejoin: "round" as const,
    "aria-hidden": true,
    ...props,
  };
}

export const icons = {
  launch: ({ size = 24, ...p }: IconProps) => (
    <svg {...base(size, p)}>
      <circle cx="11" cy="11" r="7" />
      <path d="m20 20-3.5-3.5" />
    </svg>
  ),
  calculator: ({ size = 24, ...p }: IconProps) => (
    <svg {...base(size, p)}>
      <rect x="5" y="3" width="14" height="18" rx="2" />
      <path d="M9 7h6M8.5 12h.01M12 12h.01M15.5 12h.01M8.5 16h.01M12 16h.01M15.5 16h.01" />
    </svg>
  ),
  clipboard: ({ size = 24, ...p }: IconProps) => (
    <svg {...base(size, p)}>
      <rect x="5" y="4" width="14" height="17" rx="2" />
      <path d="M9 4a3 3 0 0 1 6 0" />
      <path d="M9 11h6M9 15h4" />
    </svg>
  ),
  globe: ({ size = 24, ...p }: IconProps) => (
    <svg {...base(size, p)}>
      <circle cx="12" cy="12" r="8" />
      <path d="M4 12h16M12 4c2.5 2.2 2.5 13.8 0 16M12 4c-2.5 2.2-2.5 13.8 0 16" />
    </svg>
  ),
  bolt: ({ size = 24, ...p }: IconProps) => (
    <svg {...base(size, p)}>
      <path d="M13 3 5 13h5l-1 8 8-10h-5l1-8Z" />
    </svg>
  ),
  apple: ({ size = 24, ...p }: IconProps) => (
    <svg {...base(size, p)} stroke="none" fill="currentColor">
      <path d="M16.4 12.9c0-2.3 1.9-3.4 2-3.5-1.1-1.6-2.8-1.8-3.4-1.8-1.4-.1-2.8.9-3.5.9s-1.8-.8-3-.8c-1.5 0-3 .9-3.8 2.3-1.6 2.8-.4 7 1.2 9.3.8 1.1 1.7 2.4 2.9 2.3 1.2 0 1.6-.7 3-.7s1.8.7 3 .7 2-1.1 2.8-2.2c.9-1.3 1.2-2.5 1.3-2.6-.1 0-2.4-.9-2.4-3.6Zm-2.3-6.6c.6-.8 1.1-1.9 1-3-1 0-2.1.6-2.8 1.4-.6.7-1.1 1.8-1 2.9 1.1.1 2.2-.6 2.8-1.3Z" />
    </svg>
  ),
  github: ({ size = 24, ...p }: IconProps) => (
    <svg {...base(size, p)} stroke="none" fill="currentColor">
      <path d="M12 2a10 10 0 0 0-3.16 19.49c.5.09.68-.22.68-.48v-1.7c-2.78.6-3.37-1.34-3.37-1.34-.45-1.16-1.11-1.47-1.11-1.47-.91-.62.07-.6.07-.6 1 .07 1.53 1.03 1.53 1.03.89 1.53 2.34 1.09 2.91.83.09-.65.35-1.09.63-1.34-2.22-.25-4.55-1.11-4.55-4.94 0-1.09.39-1.98 1.03-2.68-.1-.25-.45-1.27.1-2.65 0 0 .84-.27 2.75 1.02a9.5 9.5 0 0 1 5 0c1.91-1.29 2.75-1.02 2.75-1.02.55 1.38.2 2.4.1 2.65.64.7 1.03 1.59 1.03 2.68 0 3.84-2.34 4.68-4.57 4.93.36.31.68.92.68 1.85v2.74c0 .27.18.58.69.48A10 10 0 0 0 12 2Z" />
    </svg>
  ),
  arrow: ({ size = 24, ...p }: IconProps) => (
    <svg {...base(size, p)}>
      <path d="M5 12h14M13 6l6 6-6 6" />
    </svg>
  ),
  arrowUpRight: ({ size = 24, ...p }: IconProps) => (
    <svg {...base(size, p)}>
      <path d="M7 17 17 7M8 7h9v9" />
    </svg>
  ),
  check: ({ size = 24, ...p }: IconProps) => (
    <svg {...base(size, p)}>
      <path d="m4 12 5 5L20 6" />
    </svg>
  ),
  shield: ({ size = 24, ...p }: IconProps) => (
    <svg {...base(size, p)}>
      <path d="M12 3 5 6v5c0 4.5 3 7.5 7 9 4-1.5 7-4.5 7-9V6l-7-3Z" />
      <path d="m9 12 2 2 4-4" />
    </svg>
  ),
  terminal: ({ size = 24, ...p }: IconProps) => (
    <svg {...base(size, p)}>
      <rect x="3" y="4" width="18" height="16" rx="2" />
      <path d="m7 9 3 3-3 3M13 15h4" />
    </svg>
  ),
} as const;

export type IconName = keyof typeof icons;
