import {
  Archive,
  Calculator,
  ClipboardList,
  Globe,
  Search,
  Smile,
  Sparkles,
  Zap,
  type LucideIcon,
} from "lucide-react";

// Generic glyphs come from lucide-react. Feature cards reference these by
// name from the data folder; everything else imports lucide directly.
export const featureIcons = {
  launch: Search,
  calculator: Calculator,
  clipboard: ClipboardList,
  emoji: Smile,
  globe: Globe,
  bolt: Zap,
  hyper: Sparkles,
  backup: Archive,
} satisfies Record<string, LucideIcon>;

export type IconName = keyof typeof featureIcons;
