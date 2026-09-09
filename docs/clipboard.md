# Clipboard history

## Poll-based capture

`ClipboardMonitor` runs a 0.5s `Timer` watching `NSPasteboard.general.changeCount`. To avoid
re-capturing Tinycast's own writes, every write stamps a private `internalType` marker on the
pasteboard and the poller skips anything carrying it.

## Store

`ClipboardStore` is SQLite-backed: rows plus a trigram FTS5 index in `clipboard.sqlite3`, with image
blobs as loose PNG files, all under `~/Library/Caches/<bundle-id>/`. The newest 1000 rows are mirrored
in the `@Published items` window; FTS search reaches older rows.

A database that won't open is deleted and recreated (worst case the store degrades to session-only
in-memory history).

Image capture (TIFF→PNG re-encode + blob write) runs off the main actor via detached tasks; row
inserts, search, and pruning stay on the main actor.

## Pinned entries

A row's ⌘K Actions menu carries **Pin Entry / Unpin Entry** (⌘P), persisted as a `pinned_at` column
in the fresh `items` schema — a stamp rather than a flag, because the Pinned section is ordered by
_when you pinned_, not by recency.

Pins change four things:

- **Order.** `search` returns pinned rows first — for the empty query and for FTS hits alike — under
  one "Pinned" section above the date buckets, in pin order with the oldest pin at the top, so a new
  pin joins the end of the section instead of displacing the ones already there. `items` itself stays
  in pure recency order; the display split is memoized next to the search memo and invalidated with
  it. Pinned rows are matched **in memory**
  rather than taken from the FTS result, since the statement's `LIMIT` could otherwise drop one out
  of a busy query's matches — which holds because every pinned row is resident in `items`, however
  old (`load` fetches them all, and neither the window trim nor pruning drops one).
- **Unpinning re-recencies.** An unpinned row rejoins the history as its _newest_ entry (Raycast does
  the same) rather than dropping back into the date bucket it came from, which would scroll the list
  out from under the selection. It's the same delete + re-insert `promote` uses.
- **Retention.** Pruning skips pinned rows (`AND pinned_at IS NULL`), so a pin outlives the retention
  window. "Clear History" still deletes everything after `ClipboardCoordinator` confirms through the
  app-owned dialog presenter.
- **Selection.** Pinning lifts a row out of its date bucket, so `ClipboardCoordinator.togglePinned` moves the
  palette selection to the row's new index in the _current_ results and bumps `palette.followToken`,
  which is what makes the list scroll the highlight back into view.

Pasting a pinned entry deliberately does **not** promote it: it holds its place in the Pinned
section, so `promote` skips pinned rows instead of rewriting the row and its FTS entry for no
visible change.

`load` reads every pinned row plus the newest 1000 unpinned ones as two indexed branches over a
partial index on `pinned_at` (`Tools/clipboard-test.swift` covers the shape). The single
`pinned_at IS NOT NULL OR rowid >= ?` form reads better but cannot be driven from an index while
holding row order, so it scans the whole table — ~12ms against ~1ms at 200k rows, on the main actor
at launch.

## Bulk import deduplication

Import retains only the incoming UTF-8 keys and streams existing history once through
`SELECT text, image_path FROM items`. Borrowed SQLite buffers are used only during a lookup; retained
matches come from owned incoming keys. Memory therefore scales with incoming payloads, not unlimited
history. No persistent equality index, schema migration or extra on-disk copy of long text is added.

Historical equality remains SQLite BINARY text equality. Incoming lookup keys mirror the current
`sqlite3_bind_text(..., -1, ...)` first-NUL truncation, whereas existing database values are compared
at their full byte length. The original within-batch `Set<String>` deliberately still uses Swift
canonical Unicode equality. Successful inserts update both text and image-path lookup sets, including
records carrying both fields. Oldest-first insertion, pin/source metadata and load order are unchanged.

A failed BEGIN returns without touching another transaction. A history-scan failure resets its
statement, rolls back the owned transaction and returns zero without inserting or reloading. The
existing API's count quirk is retained: it counts attempted inserts even when a UUID constraint
rejects one, and its within-batch seen set still suppresses a later identical attempt. Regression
tests pin this behavior rather than changing import semantics as part of a performance optimization.

### Reproduce the isolated benchmark

```sh
swiftc -O -swift-version 6 Tinycast/Features/Clipboard/Model/ClipboardStore.swift \
    Tools/clipboard-import-benchmark.swift -o /tmp/clipboard-import-benchmark
/tmp/clipboard-import-benchmark 20000 2000 50
/tmp/clipboard-import-benchmark 50000 5000 10
/tmp/clipboard-import-benchmark 50000 5000 90
```

Arguments are existing rows, incoming base rows, and the percentage matching existing history. An
additional within-batch duplicate is appended every ten incoming rows. Fixtures use 10% image paths
and 5% long text (about 16.5 KiB each); all database/filesystem effects stay in fresh temporary roots.
The timed interval is `importEntries`, including inserts, FTS maintenance, commit, load and pruning;
fixture setup is excluded. These are synthetic store measurements, **not UI latency**.

Measured with Xcode 26.6, optimized Swift 6 builds on the development Mac:

| Existing | Incoming including repeats | Existing duplicates | Inserted | Before | After |
| ---: | ---: | ---: | ---: | ---: | ---: |
| 20,000 | 2,200 | 50% | 1,000 | 7.022 s | 0.917 s |
| 50,000 | 5,500 | 10% | 4,500 | 63.434 s | 2.676 s |
| 50,000 | 5,500 | 90% | 500 | 30.272 s | 2.224 s |

A separate instrumented 20,000/2,200 run measured `SQLITE_STMTSTATUS_FULLSCAN_STEP` across import
lookups: **31,467,000 → 19,999**. Equality EXPLAIN still says `SCAN items`, because no equality index
was added; those repeated equality statements are no longer used by import.

Process peak RSS was about 51.9 MiB for the first fixture and 94.3 MiB for both larger fixtures, for
both implementations. The fixture-setup high-water mark was not exceeded during import, so these
figures do not isolate transient key-allocation overhead. Key retention is bounded by incoming bytes
plus hash-table entries; SQLite streams historical pages rather than retaining every historical text.
Database sizes after import remained about 41.4 / 106.5 / 99.1 MiB respectively. Small differences
between runs reflect fresh UUID/B-tree layout, not a new index. A full-history set or permanent
long-text index would retain another history-sized representation; neither is necessary here.
