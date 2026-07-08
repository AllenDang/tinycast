import { site } from "./site";

// The values that make Tinycast Tinycast. Each is a plain promise, not a pitch.
export const values = [
  {
    title: "Free and open source",
    body: `Every line is public under the ${site.license} license. Read it, fork it, build it yourself.`,
  },
  {
    title: "Local by design",
    body: "Your apps, clipboard, and shortcuts stay on your Mac. Nothing is uploaded, ever.",
  },
  {
    title: "No account, no sign-in",
    body: "Install it and it works. There's no login, no paywall, and no pro tier.",
  },
  {
    title: "Zero telemetry",
    body: "No analytics, no crash pings, no background phone-home. It does nothing you didn't ask for.",
  },
] as const;
