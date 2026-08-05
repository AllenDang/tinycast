# Refactor Roadmap

Execution order, dependencies, effort and risk for all 35 phases.
Source of rationale: [`docs/architecture-review.md`](../architecture-review.md).
**Compatibility rules: [`POLICY.md`](POLICY.md) — it overrides anything below.**

**Legend**
Effort: **S** ≤ 2 h · **M** 2–4 h · **L** 4–8 h (operator time including review, not Claude time)
Risk: **Low** structure only · **Med** touches behaviour-adjacent code · **High** touches a
documented invariant
Context: expected share of one Claude conversation — **Low** < 25 % · **Med** 25–50 % · **High** 50–75 %

---

## Milestones

| #      | Milestone      | Phases | Ships what                                                                                  |
| ------ | -------------- | ------ | ------------------------------------------------------------------------------------------- |
| **M0** | Baselines      | 01     | Permanent signposts + recorded numbers. Nothing else changes.                               |
| **M1** | Zero-risk wins | 02–10  | Every measurable performance fix in the review, at near-zero risk.                          |
| **M2** | Observation    | 11–18  | The largest CPU + RAM win. Removes ~30 `assumeIsolated` hazards.                            |
| **M3** | Palette split  | 19–23  | `RootPaletteView` 1126 → ~350 lines. Adding a mode becomes one file.                        |
| **M4** | AppCore split  | 24–26  | `AppCore` 1348 → ~250 lines. Kills the merge-conflict bottleneck.                           |
| **M5** | Structure      | 27–29  | Feature-first tree, `Core/` deleted. Navigability.                                          |
| **M6** | Consistency    | 30–33  | One naming vocabulary, compiler-enforced exhaustiveness, harness coverage.                  |
| **M7** | Close out      | 34–35  | Comment budget, final measurement, docs, and deleting the now-dead compatibility machinery. |

**Stop points.** Every phase is a valid stopping point. The natural ones are the milestone boundaries:
after **10**, after **18**, after **23**, after **26**, after **29**. Each of those leaves a coherent,
shippable, self-consistent codebase.

---

## Phase table

| #   | Phase                                                        | Review ref    | Depends on | Effort | Risk     | Context |
| --- | ------------------------------------------------------------ | ------------- | ---------- | ------ | -------- | ------- |
| 01  | Instrumentation and baselines                                | W0            | —          | S      | Low      | Low     |
| 02  | Async icons in the Settings launcher list                    | H-3           | 01         | S      | Low      | Low     |
| 03  | Named paste-timing constants                                 | L-7           | 01         | S      | Low      | Low     |
| 04  | Retire the last `NSAlert`                                    | K-6           | 01         | S      | Med      | Low     |
| 05  | `AppPaths` — one channel-directory helper                    | M-5           | 01         | S      | Low      | Low     |
| 06  | HotKey binding cache                                         | M-4           | 01         | M      | Low      | Med     |
| 07  | Settings-pane scan cache                                     | H-2           | 01         | M      | Low      | Med     |
| 08  | Parallel uninstall scan                                      | H-4           | 01         | M      | Med      | Med     |
| 09  | `Memo` primitive and launcher result memoization             | M-7, M-3      | 01         | M      | Med      | Med     |
| 10  | Health-timer consolidation                                   | M-2           | 01         | M      | Med      | Med     |
| 11  | Observation pilot — `FavoritesStore`                         | C-3           | 01         | S      | Med      | Low     |
| 12  | Observation wave A — sessions and value state                | C-3           | 11         | M      | Low      | Med     |
| 13  | Observation wave A — leaf stores                             | C-3           | 11         | M      | Low      | Med     |
| 14  | Observation wave A — monitors and indices                    | C-3           | 11         | M      | Med      | Med     |
| 15  | Observation — `HotKeyManager`                                | C-3, M-4      | 06, 11     | M      | Med      | Med     |
| 16  | Observation — `AppSettings`                                  | C-3           | 11         | L      | Med      | Med     |
| 17  | Observation — `AppIndex` and the persisted stores            | C-3           | 09, 11     | L      | High     | High    |
| 18  | Observation — palette, `AppCore`, retire the Combine sinks   | C-3, K-1      | 16, 17     | L      | High     | High    |
| 19  | `PaletteScreen` scaffold and the selection harness           | C-2           | 18         | M      | Low      | Med     |
| 20  | Screens — `quicklinkArguments` and `uninstall`               | C-2           | 19         | M      | Med      | Med     |
| 21  | Screens — `quicklinks` and `emoji`                           | C-2           | 20         | M      | Med      | Med     |
| 22  | Screens — `clipboard` and `calculatorHistory`                | C-2           | 21         | M      | Med      | High    |
| 23  | Screen — `launcher`, and collapsing the calc offset          | C-2           | 22         | L      | **High** | High    |
| 24  | `QuicklinkCoordinator` and `SnippetExpansionCoordinator`     | C-1           | 23         | L      | Med      | High    |
| 25  | Palette, SystemAction, Uninstall, CustomCommand coordinators | C-1           | 24         | L      | Med      | High    |
| 26  | Fix the three dependency inversions                          | §2.3          | 15, 25     | M      | Med      | Med     |
| 27  | Extract `DesignSystem/` and `Platform/`                      | M-1           | 26         | M      | Low      | Med     |
| 28  | Extract `Windows/`, `Palette/` and `App/`                    | M-1, M-9      | 27         | M      | Low      | Med     |
| 29  | Feature folders and the Settings shell                       | M-1, M-8, H-5 | 28         | L      | Low      | High    |
| 30  | Naming vocabulary renames                                    | §4.1          | 29         | M      | Low      | Med     |
| 31  | `AppEntry.Kind` exhaustiveness and `KindDescriptor`          | H-6           | 29         | M      | Med      | Med     |
| 32  | Retire `AppCore` forwarders, adopt `@Environment`            | §2.3          | 25, 29     | M      | Med      | Med     |
| 33  | `SettingsBackup` completeness harness                        | M-6           | 16         | M      | Low      | Med     |
| 34  | Comment budget, comment pass, final measurement              | H-1, W8       | 33         | L      | Low      | High    |
| 35  | Retire the compatibility machinery                           | POLICY        | 29, 30, 34 | M      | Low      | Med     |

---

## Dependency graph

```
                                     01 ─── Baselines
                                      │
        ┌───────┬───────┬───────┬─────┼─────┬───────┬───────┬───────┬───────┐
        │       │       │       │     │     │       │       │       │       │
       02      03      04      05    06    07      08      09      10      11
     icons   delays  dialog  paths  keys  panes  uninst  memo    timers  pilot
                                      │                   │       │       │
                                      │                   │       │  ┌────┼────┬────┐
                                      │                   │       │  │    │    │    │
                                      │                   │       │ 12   13   14   16
                                      │                   │       │ sess leaf mon  settings
                                      └───────────────────┼───────┼──┴─── 15       │
                                                          │       │      hotkeys   │
                                                          └───────┴──── 17 ────────┘
                                                                     stores
                                                                        │
                                                                       18 ─── palette+core, retire Combine
                                                                        │
                                    19 ── 20 ── 21 ── 22 ── 23   (M3, strictly sequential)
                                                             │
                                                            24 ── 25   (M4)
                                                                   │
                                                            15 ────┴── 26   inversions
                                                                        │
                                                            27 ── 28 ── 29   (M5, strictly sequential)
                                                                        │
                                              ┌───────┬─────────────────┤
                                             30      31                32
                                           naming   kinds          forwarders
                                              │      │                 │
                                    16 ─── 33 ┴──────┴─────────────────┘
                                        backup harness
                                              │
                                             34 ─── comments + final measurement
                                              │
                                             35 ─── retire the dead compatibility code
```

**Reading it.** Phases 02–11 fan out from 01 and are mutually independent — run them in any order, or in
parallel across branches if more than one person is working. Everything from 17 onward is a chain: each
phase assumes the previous one merged.

---

## Parallelisation

If two engineers are working:

- **M1 (02–10) parallelises cleanly.** Nine independent phases, disjoint file sets except 09/17 (both
  touch `AppIndex`) — do 09 before anyone starts 17.
- **M2 waves A (12, 13, 14) parallelise** once 11 has merged and established the pattern.
- **M3, M4, M5 do not parallelise.** Each phase rewrites the file the next one edits. One engineer,
  sequential, no exceptions.
- **M6 (30, 31, 32) parallelises** after 29, with 33 independent from 16 onward.

---

## Risk register

| Phase | The specific risk                                                                                                                                                                                     | Mitigation                                                                                                                                                                                |
| ----- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| 04    | The snippets consent dialog is also the Accessibility permission gate. Changing its presentation could change _when_ the permission is requested.                                                     | Phase doc pins the exact ordering: consent → `settings.snippetsEnabled = true` → `Permissions.ensureAccessibility()`. Manual verification requires a fresh TCC state.                     |
| 05    | Channel isolation breaks and a Dev build writes into the stable app's directory. (Path _changes_ are now fine — data is disposable.)                                                                  | Every path stays keyed by `Bundle.main.bundleIdentifier`; clean-install verification.                                                                                                     |
| 08    | Parallel scan could reorder the uninstall list or race the `seen` dedup set.                                                                                                                          | Index-ordered writeback is a hard acceptance criterion; dedup must run after the gather. Verify list order against a pre-change screenshot.                                               |
| 16    | A missed `didSet` silently stops persisting a setting. Worse: the eight absence-vs-`false` checks _look_ like dead legacy code under the new policy and are not — they encode fresh-install defaults. | AC enumerates every key; verification wipes the channel and walks all 14 panes to confirm defaults, then relaunches to confirm persistence.                                               |
| 17    | `ClipboardStore` and `QuicklinkStore` are harness-compiled; `@Observable` must not break that.                                                                                                        | `Tools/clipboard-test.swift` and `Tools/quicklink-test.swift` are mandatory gates.                                                                                                        |
| 18    | Deleting the Combine sinks changes _when_ feature-presence reconciliation runs (`@Published` fires before the write; `@Observable` after).                                                            | Phase doc requires removing the deferral `Task {}` wrappers in the same change, and verification toggles every feature switch.                                                            |
| 23    | The launcher screen owns the flat-selection invariant, favourites pinning, section ordering and the calc card offset. Highest-risk phase in the plan.                                                 | Phase 19 lands `Tools/palette-selection-test.swift` first. Phase 23 cannot start until that harness is green and covers the launcher.                                                     |
| 25    | `PaletteCoordinator` moves pop-to-root and compact-mode logic, which interact with window sizing.                                                                                                     | Verification includes the compact↔expanded swap and the pop-to-root timeout at every setting value.                                                                                       |
| 29    | Moving 13 feature folders breaks the `Tools/` harness command lines.                                                                                                                                  | Every move PR updates `docs/development.md` and `AGENTS.md` in the same commit; `checklists/testing.md` runs all 17 harnesses.                                                            |
| 29    | A file with no obvious owner gets parked in a leftover `Core/`, and the flat namespace grows back.                                                                                                    | AC6 requires `Tinycast/Core/` to be **deleted**. Every current file is assigned a home in phase 27, 28 or 29; a file that looks homeless is a gap in the phase doc to raise, not to park. |
| 34    | A comment pass can delete a load-bearing explanation.                                                                                                                                                 | Triage rule is delete/compress/**relocate** — relocation to `docs/` is the default for anything explaining an invariant.                                                                  |
| 35    | Raycast import or the snippet Markdown format is deleted as "legacy". It is neither — those are formats Tinycast does not own.                                                                        | Both on the must-not-change list; `raycast-test` and `snippets-test` are gates.                                                                                                           |

---

## Effort summary

| Milestone | Phases | Total effort |
| --------- | ------ | ------------ |
| M0        | 1      | ~2 h         |
| M1        | 9      | ~20 h        |
| M2        | 8      | ~28 h        |
| M3        | 5      | ~20 h        |
| M4        | 3      | ~16 h        |
| M5        | 3      | ~14 h        |
| M6        | 4      | ~14 h        |
| M7        | 2      | ~10 h        |
| **Total** | **35** | **~124 h**   |

Operator time, including review and manual verification. Claude's own working time is not the
constraint — your review capacity is. Budget one to two phases per working day, no more.

---

## Status tracking

Update this table as phases land. `Blocked` requires a note in the phase's progress file.

| #   | Status      | Branch / commit                            | Date       | Notes                                                                                                                                                                                                                                  |
| --- | ----------- | ------------------------------------------ | ---------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| 01  | Complete    | `399189b` (#157)                           | 2026-08-05 | Merged. **Instruments baselines never captured** — later phases have no before-numbers to compare against; see `progress/01`.                                                                                                          |
| 02  | Complete    | `40bab1f` (#158)                           | 2026-08-05 | Merged. `AppEntry.icon` retained — two callers in `AppPickerPopover`, so AC5 not met; follow-ups in `progress/02`.                                                                                                                     |
| 03  | Complete    | `refactor/03-named-paste-timing-constants` | 2026-08-05 | Two constants, four call sites (doc said three). Values unchanged; paste verified into fast and slow apps.                                                                                                                             |
| 04  | Complete    | `refactor/04-retire-the-last-nsalert`      | 2026-08-05 | One call site converted; text and consent→persist→permission ordering unchanged. **AC1 not met** — a second `NSAlert` remains in `SnippetArgumentsPrompt`, outside this phase's files; see `progress/04`.                              |
| 05  | Complete    | `refactor/05-app-paths`                    | 2026-08-05 | `AppPaths` adopted in the four non-harness stores; the four harness-compiled ones keep their injected parameter. No resolved path changed.                                                                                             |
| 06  | Complete    | `refactor/06-hotkey-binding-cache`         | 2026-08-05 | Map populated after the prunes, written through in `setBinding`; `candidateActions` cached. Diff +16/−4 against an expected +55/−25. Release binary +16,528 B (+0.476 %) — the new `Dictionary` specialization. **Unblocks phase 15.** |
| 07  | Complete    | `refactor/07-settings-pane-scan-cache`     | 2026-08-05 | Value-threaded like `alternateNameCache`; no static, no lock. Warm scan 16.5 ms → 0.014 ms; 52 panes identical in id, name and order. Diff +24/−8 against an expected +45/−15. AC3 (mtime invalidation) reasoned, not triggerable.      |
| 08  | Complete    | `refactor/08-parallel-uninstall-scan`      | 2026-08-05 | Both gathers are index-keyed task groups; dedup is one pass after them. Output byte-identical on 13 apps. Win is target-shaped: ~6× on many-leftover apps, ~0 % on Xcode (one 4 GB bundle walk dominates). Cancellation now actually reaches the scan — `Task.detached` replaced by a structured child. Binary +17,552 B (+0.503 %). |
| 09  | Complete    | `refactor/09-memo-and-launcher-memoization` | 2026-08-05 | One 11-line `Memo`, four adoptions; `ClipboardStore` untouched. Results key carries a fifth term (`entriesRevision`) the doc omits — without it a republish strands a stale list. Diff +101/−53 against an expected +110/−70. AC8 unmeasurable (no phase-01 baseline). |
| 10  | Complete    | `refactor/10-health-timer-consolidation`   | 2026-08-05 | One `HealthTicker`, weak subscribers, no timer while none is registered; the three `healthCheck()` bodies are byte-identical. Clipboard poll gains `tolerance = 0.1` and a session suspend that re-baselines on resume. The two tap checks move from the default runloop mode to `.common`. `snippets-test` now also compiles `Core/HealthTicker.swift`. Diff +65/−56 against an expected +90/−70. |
| 11  | Complete    | `refactor/11-observation-pilot-favorites-store` | 2026-08-05 | One type, two consumers, +5/−4 against an expected +12/−12. No import changed — Foundation already re-exports `Observation`. `revision` stays tracked; it moves with `keys`. **The recipe is in `progress/11`** — phases 12–18 follow it. AC7 (`_printChanges`) not run. **Unblocks phases 12–18.** |
| 12  | Complete    | `refactor/12-observation-sessions-and-value-state` | 2026-08-05 | All four types migrated; none dropped. 11 files, not the 13 the doc lists — `ShortcutRecorder` and `DialogController` needed no change. Diff +30/−27 against an expected +45/−50. **Release binary −16,464 B (−0.465 %)** — dropping `@Published` sheds more specialization than the registrar adds, so M2 should keep shrinking it. `UninstallSession.app` is now tracked where it previously was not (moves with `state`, so no extra invalidation). |
| 13  | Complete    | `refactor/13-observation-leaf-stores`      | 2026-08-05 | `VisibilityStore`, `CalculatorHistoryStore` and `FrequentEmojiStore`; four injection sites (3 palette + 1 Settings). Both memos take `@ObservationIgnored` but their `revision` keys stay **tracked** — on a memo hit `search()`/`top()` read only `revision`, so ignoring it would silently stall both lists. Diff +22/−19 against an expected +40/−45. Warning baseline captured: 0 → 0. **`regression.md` not run** — interactive verification waived, so AC3–AC7 are unverified. |
| 14  | Complete    | `refactor/14-observation-monitors-and-indices` | 2026-08-05 | `RunningAppsMonitor`, `EmojiIndex` and `CurrencyRateStore`; three palette injections plus two Settings views. All four currency consent guards and the running-apps equality guard are outside the diff. `RootPaletteView`'s `@EnvironmentObject` count went 7 → 5 — its two `runningApps` reads sit in deferred closures, off the `body` path, so AC4 holds. Diff +22/−19 against an expected +35/−45. Warning baseline measured: 0 → 0. **`regression.md` not run** — interactive verification waived, so AC5–AC8 are unverified, including the currency-off network check. |
| 15  | Complete    | `refactor/15-observation-hotkey-manager`   | 2026-08-05 | **The last `objectWillChange.send()` in the tree is gone** — the grep is now empty. Phase 06's `bindings` map is the observed state; `recordingAction`'s `didSet` is byte-identical. 7 files, not the 5 the doc lists — `QuicklinkListView` and `OnboardingView` are unlisted consumers the compiler forced. `candidateActionsCache` took `@ObservationIgnored` per phase 11's recipe §4, approved before implementing. Diff +11/−11 against an expected +18/−22. **`regression.md` not run** — interactive verification waived, so AC3–AC5 are unexercised, including the recording-pause check. |
| 16  | Complete    | `refactor/16-observation-app-settings`     | 2026-08-05 | All 26 `@Published` gone; `init` has **zero diff lines**, so all 25 keys and the **nine** (not eight — the doc miscounts) absence-vs-`false` checks are byte-identical. The three `settings.$x` sinks became re-arming `withObservationTracking`, keeping `assumeIsolated` + the deferral `Task` for 18; `HyperKeyTap` needed its no-`dropFirst` initial `applyKey` written out by hand. 8 panes → `@Bindable`; `AppRow` and `ShortcutRecorder` lost observation-only properties (their keycap reads track through `KeyShortcut`). Diff +108/−111 against an expected +90/−110. Warning baseline measured on-branch: 0 → 0. **`regression.md` not run** — interactive verification waived, so AC5, AC6 and AC8 are unverified, including the wipe-and-relaunch default check the phase calls primary. |
| 17  | Complete    | `refactor/17-observation-app-index-and-stores` | 2026-08-05 | All four migrated; the three harnesses (plus `raycast-test`, an unlisted fourth) compile them standalone with no command-line change. `didSet`-survives-`@Observable` and the harness constraint were both proven empirically *before* editing. **The migration alone did not deliver the headline win** — `RootPaletteView.body` read `store.items` unconditionally, so a capture still re-ran the whole palette in every mode; scoped to `.clipboard` mode in one operator-approved line beyond the phase's stated edits. `entriesRevision` stays **tracked** (memo hits read only it); both memos and every SQLite/dispatch/Task handle took `@ObservationIgnored`. No `@Bindable` needed — all four expose only `private(set)`. 14 files, not the doc's 13: `QuicklinkListView` is listed but unaffected, `QuicklinkEditorSheet` and `AppPickerPopover` are unlisted consumers. Diff +56/−53 against an expected +70/−90. Warning baseline measured on-branch: 0 → 0. **Clean install verified** (channel wiped, all four stores built from nothing, live capture + relaunch). **`_printChanges` not run** and the interactive sweep waived, so AC6 is partial and AC8 unverified. |
| 18  | Not started |                                            |            |                                                                                                                                                                                                                                        |
| 19  | Not started |                                            |            |                                                                                                                                                                                                                                        |
| 20  | Not started |                                            |            |                                                                                                                                                                                                                                        |
| 21  | Not started |                                            |            |                                                                                                                                                                                                                                        |
| 22  | Not started |                                            |            |                                                                                                                                                                                                                                        |
| 23  | Not started |                                            |            |                                                                                                                                                                                                                                        |
| 24  | Not started |                                            |            |                                                                                                                                                                                                                                        |
| 25  | Not started |                                            |            |                                                                                                                                                                                                                                        |
| 26  | Not started |                                            |            |                                                                                                                                                                                                                                        |
| 27  | Not started |                                            |            |                                                                                                                                                                                                                                        |
| 28  | Not started |                                            |            |                                                                                                                                                                                                                                        |
| 29  | Not started |                                            |            |                                                                                                                                                                                                                                        |
| 30  | Not started |                                            |            |                                                                                                                                                                                                                                        |
| 31  | Not started |                                            |            |                                                                                                                                                                                                                                        |
| 32  | Not started |                                            |            |                                                                                                                                                                                                                                        |
| 33  | Not started |                                            |            |                                                                                                                                                                                                                                        |
| 34  | Not started |                                            |            |                                                                                                                                                                                                                                        |
| 35  | Not started |                                            |            |                                                                                                                                                                                                                                        |
