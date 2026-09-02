# Launcher Search Performance Optimization

## Data (from `/tmp/tinycast-perf.log`)

313 entries indexed. Every keystroke scores ALL 313 entries via `SearchRelevance.score`.

| Query | rank time | scored | bottleneck |
| ------- | ----------- | -------- | ------------ |
| "a" | 5.6ms | 266→200 | score loop |
| "p" | 17.9ms | 217→200 | score loop |
| "ar" | 14.7ms | 86 | score loop |
| "arc" | 21.5ms | 9 | score loop |
| empty | 3.0ms | - | computeRows sections (9 filter passes) |

Each `score` call normalizes candidate strings (lowercase + strip format scalars) then runs up to 5 fuzzy match tiers. 313 entries × ~3 fields = ~1000 normalizations per keystroke.

## Phase 1: Pre-normalized Search Fields

**Impact: ~50% reduction in scoring time.** Eliminates the `normalized()` call on every candidate.
Normalization is done once at scan time (already off-main), never at query time.

**Changes:**

- `Features/Launcher/Model/SearchRelevance.swift`: add `FuzzyMatch.match(_:normalizedCandidate:)` that skips normalization
- `Features/Launcher/Service/AppIndex.swift`: store pre-normalized `SearchFields` in `AppEntry`, computed during scan
- `FuzzyMatch.normalized` becomes a scan-time concern only

## Phase 2: Character Pre-filter

**Impact: 2-6x reduction in candidates scored.** A quick set-membership check rejects entries that don't contain all query characters before the expensive fuzzy match runs.

For "arc": 313 → ~50 candidates → 6x fewer `score` calls.
For "p": 313 → ~200 candidates → 1.5x fewer.

**Changes:**

- `Features/Launcher/Service/AppIndex.swift`: pre-compute a character `Set<Character>` per entry at scan time
- `AppIndex.rank`: before `score`, check if all query characters are in the entry's char set; skip if not

## Phase 3: Single-pass Sectioning

**Impact: 3ms → ~0.3ms for empty-query sectioned render.** Current code does 9 separate `filter` passes over the results array. Replace with one pass that buckets by `kind`.

**Changes:**

- `Features/Launcher/UI/LauncherList.swift`: `computeRows` sectioned path — one loop instead of 9 filters

## Phase 4: Memoize computeRows

**Impact: eliminates redundant row computation on SwiftUI's double-render.** Every keystroke triggers two body renders; the second one re-runs `computeRows` unnecessarily.

**Changes:**

- `Features/Launcher/UI/LauncherList.swift`: add `Memo` keyed on `(results, favoriteCount, showSections, funcSuggestions, calc, ai, aiPending)`

## Implementation Order

1. Phase 1 (pre-normalized fields) — single biggest win, touches core types
2. Phase 2 (char pre-filter) — additive, no type changes
3. Phase 3 (single-pass sections) — isolated to `computeRows`
4. Phase 4 (computeRows memo) — isolated, trivial
