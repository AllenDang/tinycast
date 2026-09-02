# Tinycast Performance & Stability Improvements

## Overview

Eight targeted improvements ordered by impact, each verified with before/after data.

## Prerequisites

Each item needs:

1. **Baseline**: measure current performance with a reproducible benchmark
2. **Implementation**: make the change
3. **Verification**: re-run the same benchmark, confirm improvement
4. **Commit**: one commit per item with the baseline/after data in the message

## Measurement Strategy

- **AppIndex scan**: `Signposts.interval("AppIndex.scan")` already instruments this. We'll add a lightweight measurement harness in `Tools/perf-baseline.swift` that exercises the scan and reports timing.
- **Calculator**: `Tools/calc-test.swift` is the existing harness. We'll add a `--bench` mode that runs representative queries many times and reports aggregate timing.
- **Clipboard prune**: `Tools/clipboard-test.swift` exists. We'll measure insert throughput.
- **Ranking writes**: measure `didMutate()` call frequency and file write latency.
- **Emoji load**: measure `EmojiCatalog.parse()` time with the existing harness.

## Items

### Item 1: AppIndex incremental scan (HIGH)

- **File**: `Features/Launcher/Service/AppIndex.swift`
- **Problem**: Every launcher open rescans all app bundles (Bundle init + Spotlight query) even for unchanged apps.
- **Fix**: Cache bundle metadata keyed on (path, modificationDate), skip re-reading unchanged bundles.
- **Expected**: 50-80% reduction in scan time on re-open (warm cache).
- **Baseline**: Time `AppIndex.scan()` with 200+ apps, cold and warm.
- **Risk**: Low — the cache is keyed on modification date, same pattern already used by `SpotlightNames.Cache`.

### Item 2: Calculator pre-filter (HIGH)

- **File**: `Features/Calculator/Model/CalcEngine.swift`
- **Problem**: Full calculator pipeline runs on every keystroke even for plain app-name queries.
- **Fix**: Add a fast `couldBeCalculatorInput()` check at the top of `evaluate()` that rejects queries lacking digits, operators, or known unit/currency keywords.
- **Expected**: Near-zero cost for non-calculator queries (the common case).
- **Baseline**: Time `evaluate()` with 1000 app-name-style queries vs 1000 calc queries.
- **Risk**: Low — the pre-filter is conservative (rejects only clearly non-calc input).

### Item 3: Emoji lazy loading (HIGH)

- **File**: `App/AppCore.swift`, `Features/Emoji/Service/EmojiIndex.swift`
- **Problem**: Emoji catalog parsed on every startup regardless of whether emoji is ever used.
- **Fix**: Remove the unconditional `Task { await emojiIndex.load() }` from `start()`, load on first use in `showPalette(mode: .emoji)`.
- **Expected**: Reduced startup work; emoji first-open latency unchanged (it was already async).
- **Baseline**: Measure `EmojiCatalog.parse()` time and startup time with/without emoji load.
- **Risk**: Low — already async, just deferred.

### Item 4: Ranking data async load (HIGH)

- **File**: `Features/Launcher/Model/LauncherRankingStore.swift`
- **Problem**: `init()` sync-reads JSON from disk on the main actor, blocking startup.
- **Fix**: Defer load to first access, or load async in `start()`.
- **Expected**: ~1-5ms removed from startup path.
- **Baseline**: Time `LauncherRankingStore.init()` with 1000 records.
- **Risk**: Medium — callers must handle the unloaded state. `AppIndex.rank()` already handles empty records.

### Item 5: Clipboard prune throttling (MEDIUM)

- **File**: `Features/Clipboard/Model/ClipboardStore.swift`
- **Problem**: `prune()` runs on every insert (every 0.5s during active copying).
- **Fix**: Batch prune every N inserts or every 30 seconds.
- **Expected**: Reduced SQLite traffic during rapid copy bursts.
- **Baseline**: Measure insert throughput (inserts/sec) with and without per-insert pruning.
- **Risk**: Low — the in-memory window is already capped, and load-time pruning is the safety net.

### Item 6: Ranking write debounce (MEDIUM)

- **File**: `Features/Launcher/Model/LauncherRankingStore.swift`
- **Problem**: `didMutate()` writes entire ranking JSON to disk on every launcher selection.
- **Fix**: Add a 2-3 second debounce before writing to disk.
- **Expected**: Fewer disk writes during rapid launcher use.
- **Baseline**: Count `didMutate()` calls and file writes during a 10-selection burst.
- **Risk**: Medium — ensure the write happens before app termination. Use `prepareForTermination()` to flush.

### Item 7: exists() statement caching (MEDIUM)

- **File**: `Features/Clipboard/Model/ClipboardStore.swift`
- **Problem**: `exists(column:value:)` prepares and finalizes a statement on every call.
- **Fix**: Cache two persistent prepared statements in `openDatabase()`.
- **Expected**: Faster bulk imports (Raycast import path).
- **Baseline**: Time `importEntries()` with 1000 entries before and after.
- **Risk**: Low — same pattern already used by other statements.

### Item 8: SnippetStore file descriptor optimization (LOW)

- **File**: `Features/Snippets/Service/SnippetsStore.swift`
- **Problem**: Each snippet file gets its own `DispatchSource` watcher, risking fd exhaustion.
- **Fix**: Consolidate to directory-level watcher only, diff on change.
- **Expected**: Constant fd usage regardless of snippet count.
- **Baseline**: Count open fds with 100+ snippets before and after.
- **Risk**: Medium — the file-level watchers provide finer-grained event detection. The directory-only approach may miss some edge cases.

## Execution Order

Items 1-4 are independent and can run in any order. Items 5, 6, 7 depend on files touched by earlier items but are logically independent. Item 8 is last due to higher risk.

Recommended order: 1 → 2 → 3 → 4 → 5 → 6 → 7 → 8
