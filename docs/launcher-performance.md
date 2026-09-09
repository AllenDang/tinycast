# Launcher input performance

## Real UI harness

`UITests/LauncherUITests.swift` uses XCUITest against the shipped palette, search field,
selection, ranking and SwiftUI list. The `TinycastUITests` scheme selects the optimized (`-O`)
`UITesting` configuration and isolated bundle `com.tinycast.app.uitesting`.

The test build installs 300 or 3,000 deterministic Custom Command fixtures plus the built-in
catalog entries. It does not scan installed apps, start clipboard polling, install global hotkeys,
remap Caps Lock, or start network refreshes. Reopen does not trigger an app scan in this build.
Fixtures require confirmation; the activation test cancels the dialog without running the command.
Each launch resets only the test bundle's preferences and ranking data. Normal Debug and Release
builds do not include the test fixture or input probe code.

```sh
xcodebuild -project Tinycast.xcodeproj -scheme TinycastUITests -configuration UITesting \
    -destination 'platform=macOS,arch=arm64' -parallel-testing-enabled NO \
    -derivedDataPath /tmp/tinycast-ui-build \
    -resultBundlePath /tmp/tinycast-ui-results.xcresult test
```

Use a fresh result-bundle path each run. A logged-in, unlocked macOS desktop and permission to
run UI automation are required. Do not type, move the pointer, change focus or switch apps during
a run. UI tests are deliberately not part of headless pull-request CI.

The tests cover ASCII and Unicode text input, deletion and replacement, no-result queries,
in-place calculator edits, stable tied-score ordering, selection reset after editing, immediate Enter
after typing, and warm typing with two index sizes.
Unicode `typeText` is **not** a real IME composition/candidate-selection test. Clipboard paste,
cold filesystem/icon loading, real-app launch and photon/display-present latency are not measured.

## Metrics and boundaries

- **Input-to-layout:** the test-only binding timestamps an accepted text change. A background
  AppKit probe ends the sample at its next layout callback for that same input sequence. The
  interval includes model work, SwiftUI update scheduling and reaching layout, but **not** a
  guarantee that all rows have drawn, GPU work has finished or the screen has presented pixels.
- **Superseded inputs:** newer text can replace a pending sample. These are counted separately,
  never reported as completed layout samples. Always compare this count as well as percentiles.
- **CPU time/instructions:** XCUITest measures the application process, including Accessibility
  servicing. This is not a pure search benchmark.
- **Clock time:** includes XCUITest synthesis, assertions and synchronization overhead; do not
  label it per-keystroke application latency.

Each performance case attaches raw layout samples as JSON to its `.xcresult`, prints P50/P95/P99,
and records XCTest CPU/clock metrics over five measured iterations (plus XCTest warm-up).
The probe reads reset/export requests through a unique temporary request file watched by a
DispatchSource. The test waits for an acknowledgement outside the measured block. No query text is
written, and there is no polling or file writing per keystroke. The test removes its request and JSON
files after retaining the result attachment. Keyboard control chords were removed after event
synthesis timeouts; distributed notifications were rejected by the XCTest runner sandbox and are
not used. The file transport needs no extra permission or entitlement.

Signposts use subsystem `com.tinycast.perf`, category `LauncherInput`, interval
`Launcher.InputToLayout`. Use Instruments Time Profiler, SwiftUI and Animation Hitches for further
attribution and frame analysis. A SwiftUI-template CLI recording attempted on this machine failed
to finish saving within 130 seconds; its incomplete trace reported `Document Missing Template Error`.
It is excluded from the measurements below; no frame-present or hitch improvement is claimed from it.

## Paired results (M1 Max, macOS 26.6.2, 2026-09-09)

Both builds use the identical final test harness, isolation and measurement probe, without an
attached profiler. The reference uses product sources from `8f09c72`; only test instrumentation and
fixture startup are added. The optimized build uses the accompanying changes. Both reference
performance cases passed; all nine final UI tests passed. Each performance case contains 264
completed layout samples, zero superseded.

| Fixtures | Build | Layout P50 | Layout P95 | Layout P99 | CPU / iteration | Clock / iteration |
| --- | --- | ---: | ---: | ---: | ---: | ---: |
| 300 | Before | 21.651 ms | 37.077 ms | 39.640 ms | 1.520 s | 3.237 s |
| 300 | After | 19.918 ms | 33.588 ms | 35.514 ms | 1.476 s | 3.140 s |
| 3,000 | Before | 25.699 ms | 42.386 ms | 45.779 ms | 1.648 s | 3.508 s |
| 3,000 | After | 21.338 ms | 36.266 ms | 39.832 ms | 1.535 s | 3.408 s |

Layout P95 improves approximately **9.4% / 14.4%** for the two sizes. CPU decreases approximately
2.9% / 6.9%; the small-case CPU difference is close to run-to-run noise. These are fixture/UI
measurements, not a claim that physical input-to-screen latency has reached a 120 Hz budget.
The runs are saved locally as `/tmp/tinycast-ui-paired-before.xcresult` and
`/tmp/tinycast-ui-paired-after.xcresult`; use `xcrun xcresulttool export attachments` to retrieve samples.
Interrupted, failed and profiler-attached runs are excluded.

## Changes

- Keep normalized search fields inside `AppIndex`, out of every SwiftUI `AppEntry` value, equality
  comparison and row copy. Scanned fields are still normalized off-main.
- Compute localized alphabetical order when entries change; per-query stable sorting compares
  integer scores and preserves exactly that tie order.
- Skip lower-priority fields once they cannot beat the current score; identifier fields skip
  discarded subsequence scoring. Thirty thousand seeded Unicode/multi-field cases compare the
  normalized scorer with the unchanged reference path.
- Reuse a complete launcher snapshot across row-count, selection, content and footer reads, with
  query, results and actual calculator/AI payloads in the cache key.
- Resolve the matching AI command before checking its provider instead of validating every command
  repeatedly. Consent and provider/model availability remain checked.
- Check action availability without allocating the closed menu. Cache storage is reference-based,
  so populating it does not publish a SwiftUI State mutation. Card payloads invalidate list caches.
- Skip unchanged app-row bodies while preserving hover state and current activation closures.
- Preload learned ranking off-main at startup; a synchronous early access wins over a late preload.

The standalone scoring benchmark is complementary: it excludes UI, sorting and input dispatch.
On its 275-entry corpus and 19 queries, mean normalized scoring fell from 0.110 ms to 0.057 ms
(approximately 48%). Its `ms/index` column now reports the actual corpus rather than extrapolating
275 entries to 313. Always compare the same fixtures and automation, and repeat measurements rather
than treating one run as a guarantee. Real IME, cold real-app icons, frame presentation and hitch
analysis remain separate follow-up measurements, not results inferred from this harness.
