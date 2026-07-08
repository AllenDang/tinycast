import {
  Calculator,
  ClipboardList,
  Globe,
  Search,
  Zap,
  type LucideIcon,
} from "lucide-react";

// Generic glyphs come from lucide-react. Feature cards reference these by
// name from the data folder; everything else imports lucide directly.
export const featureIcons = {
  launch: Search,
  calculator: Calculator,
  clipboard: ClipboardList,
  globe: Globe,
  bolt: Zap,
} satisfies Record<string, LucideIcon>;

export type IconName = keyof typeof featureIcons;
