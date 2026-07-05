import { useEffect, useState } from "react";
import { site } from "../data/site";

// Resolve the GitHub releases API URL from the repo link, so there's still a
// single source of truth (site.repo) rather than a second hardcoded slug.
const match = site.repo.match(/github\.com\/([^/]+)\/([^/]+)/);
const apiUrl = match
  ? `https://api.github.com/repos/${match[1]}/${match[2]}/releases/latest`
  : null;

// Deduped across every hook consumer: fetch the tag at most once per page load.
let cached: string | null = null;
let inflight: Promise<string> | null = null;

async function fetchLatest(): Promise<string> {
  if (!apiUrl) return site.version;
  const res = await fetch(apiUrl, {
    headers: { Accept: "application/vnd.github+json" },
  });
  if (!res.ok) throw new Error(`GitHub API ${res.status}`);
  const data: unknown = await res.json();
  const tag =
    data && typeof data === "object" && "tag_name" in data
      ? String((data as { tag_name: unknown }).tag_name)
      : "";
  return tag || site.version;
}

/**
 * The latest published release tag (e.g. "v0.2.1"), falling back to the pinned
 * `site.version` while the request is in flight or if it fails (no releases,
 * offline, rate-limited). Renders the fallback first, so there's no flash.
 */
export function useLatestVersion(): string {
  const [version, setVersion] = useState(cached ?? site.version);

  useEffect(() => {
    if (cached) {
      setVersion(cached);
      return;
    }
    let active = true;
    inflight ??= fetchLatest().then((v) => (cached = v));
    inflight.then((v) => active && setVersion(v)).catch(() => {});
    return () => {
      active = false;
    };
  }, []);

  return version;
}
