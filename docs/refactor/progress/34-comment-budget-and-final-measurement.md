# Phase 34 — Comment budget and final measurement

## Status

| Field | Value |
| --- | --- |
| Status | Complete; user-approved inherited exceptions |
| Date | 2026-09-01 |
| Commit | none — orchestration explicitly forbids commits |

## Comment pass

The six-rule budget is now in `AGENTS.md` and the executable checks are in the review checklist.
Generated files and the two off-limits scrolling primitives were excluded exactly as the phase requires.

| Metric | Review baseline | Before phase 34 | Now | Delta from phase start |
| --- | ---: | ---: | ---: | ---: |
| Non-generated source lines in budget scope | 26,379 | 29,582 | 28,271 | -1,311 |
| Leading comment lines in budget scope | 1,850 | 2,023 | 712 | -1,311 |
| All comment-bearing lines, including inline | unavailable | unavailable | 765 | current scanner coverage |
| Stacked comment blocks | 181 | 217 | 0 | -217 |
| Comment lines over 100 bytes, including inline | 953 | 886 leading-only | 0 | target met |
| Leading comments over 120 characters | 572 | 512 | 0 | target met |

The two off-limits files contain 52 comment lines, including 23 over 100 characters. They contain no
stacked blocks and remain byte-identical to their original Core paths.

The pass removed 1,318 leading comment-only lines, then retained seven short rationale lines when five
trailing comments were moved above their statements. Existing subsystem documentation carries the
permission, coordinate-system, consent, storage and selection invariants that the removed prose
repeated. No code statement changed.

### Reproducible comment-only proof

Before the pass, this command wrote one `digest  path` record per file while retaining blank lines,
whitespace and inline comments:

```bash
python3 - <<'PY' > docs/refactor/progress/34-prepass-full-line-comment-stripped.sha256
from pathlib import Path
import hashlib
files = [p for p in Path("Tinycast").rglob("*.swift")
         if not p.name.endswith(".generated.swift")
         and p.name not in {"EdgeDissolve.swift", "ThinScrollbar.swift"}]
for path in sorted(files):
    lines = path.read_text().splitlines(keepends=True)
    kept = (line for line in lines if not line.lstrip().startswith("//"))
    digest = hashlib.sha256("".join(kept).encode()).hexdigest()
    print(f"{digest}  {path}")
PY
```

The 194-entry artifact digest is
`cd3475ad13e63f26c57225026906c32da85ddd7f10915533b8ad0e05f03235ce`.
The seven-entry inline artifact digest is
`824c9dcb839e0b04f210099fb7bc1fba977f5e02ccbcc0e4d64ac2a1410ffde4`.

The complete strict reconstruction script is the durable progress artifact
`34-verify-comment-evidence.py`. It validates both artifact digests and every `prefix_sha256`, requires
each prefix to occur exactly once and in order, restores each original inline `line` in memory, and
uses the same full-line-comment stripper before comparing every per-file digest. This command
regenerates the manifest byte-for-byte in `digest  path` format:

```bash
python3 docs/refactor/progress/34-verify-comment-evidence.py \
  /tmp/phase34-regenerated.sha256
cmp docs/refactor/progress/34-prepass-full-line-comment-stripped.sha256 \
  /tmp/phase34-regenerated.sha256
shasum -a 256 /tmp/phase34-regenerated.sha256
```

Verified output:

```text
manifest_artifact_sha256=cd3475ad13e63f26c57225026906c32da85ddd7f10915533b8ad0e05f03235ce
inline_artifact_sha256=824c9dcb839e0b04f210099fb7bc1fba977f5e02ccbcc0e4d64ac2a1410ffde4
manifest_entries=194
inline_prefixes=7
unique_prefixes=PASS
prefix_order=PASS
reconstructed_file_digests=PASS
byte_for_byte_manifest_regeneration=PASS
```

A prior report said four blank lines were collapsed. That was an intermediate-state observation; the
necessary section separators were restored, and the pre-pass manifest is the authoritative proof of
zero non-comment/whitespace differences before the approved inline-comment follow-up.

## Final measurement

Phase 01 did not capture Instruments or RSS baselines. Those rows are reported as unavailable rather
than inventing before/after numbers.

| Metric | Phase 01 baseline | Now | Delta / result |
| --- | ---: | ---: | --- |
| Release binary size | 3,471,592 B | 4,936,336 B | Pre-existing overage; user-approved exception |
| Cold launch, median of 3 | unavailable | not measured | no baseline; requires Instruments/manual launch |
| `AppCore.start` | unavailable | not measured | signpost remains available |
| `AppIndex.scan` cold / warm | unavailable | not measured | signpost remains available |
| `PaletteWindowController.show` | unavailable | not measured | signpost remains available |
| `UninstallScanner.scan` | unavailable | not measured | signpost remains available |
| RSS after 10 palette opens | unavailable | not measured | requires manual Activity Monitor run |
| RSS after 50 clipboard images | unavailable | not measured | requires manual fixture and Activity Monitor |
| `RootPaletteView` line count | 1,126 | 589 | -537 (-47.7%) |
| `AppCore` line count | 1,348 | 542 | -806 (-59.8%) |
| Comments / source lines | 1,850 / 26,379 | 712 / 28,271 | leading-only baseline; 2.52% |
| Stacked blocks | 181 | 0 | target met |
| Comment-bearing lines over 100 bytes | 953 | 0 | target met, including inline comments |

Additional structure checks: `Tinycast/Core/` is absent, six literal `AppCore.shared` references remain
only in the two application entry-point files, and the harness suite contains 19 commands.

## Automated gate resolution

`SearchScopes.appBundles` intentionally scans direct apps and one real subfolder while treating an
`.app` as a leaf. The stale flat-scan fixture was aligned with upstream contract fix `c898e9a`; it now
asserts direct, depth-one, depth-two exclusion and bundle-leaf behavior separately. Production
`SearchScopes.swift` was not changed in this gate-clearing pass, and all 19 harnesses pass.

The current 4,936,336 B artifact and clean-HEAD 4,946,440 B artifact both exceed 4 MiB. Investigation
attributed about 778 KB of live linked code to the existing MarkdownUI stack. The user explicitly
accepted that pre-existing overage rather than alter AI Markdown rendering or its dependency.

## Verification

- Debug build: PASS (`CODE_SIGNING_ALLOWED=NO`).
- Release build: PASS (`CODE_SIGNING_ALLOWED=NO`).
- Harnesses: all 19 PASS, including the depth-specific `scopes-test` contract.
- Mandatory harness acceptance: PASS.
- Full UI/pixel acceptance: NOT RUN; the user explicitly waived it to continue the final phase.
- Instruments and RSS acceptance: NOT RUN; no Phase 01 baseline exists and the user waived it.
- Binary-size acceptance: user-approved exception; no UI or dependency change was made.
- Settings backup completeness harness: PASS.
- XcodeGen: stable across consecutive runs.
- `git diff --check`: PASS.
- SwiftLint: two pre-existing `ClipboardScreen` closure-parameter findings; no phase-34 finding.
- Comment gate: `python3` scanner from `checklists/review.md`, including inline comments, PASS.
- Release artifact: `build/DerivedData/Build/Products/Release/Tinycast.app/Contents/MacOS/Tinycast`.
- `stat -f '%N %z'` output: artifact path followed by `4936336`.
- Off-limits SHA-256: `EdgeDissolve` `dc02f39793014c2b4a15fc8b1d81b65736fccc3acd0cd9c3324cc43d5b7161e6`.
- Off-limits SHA-256: `ThinScrollbar` `fdcef6ec3126d70eb378286c96575293be91f5eb15854cb9c0aea571f01b04c1`.
- Generated and off-limits files were verified by paired HEAD/current content hashes below.
- Staged files: none.

### Generated and off-limits content proof

`git show` was redirected to temporary files before hashing so blob and filesystem bytes use the same
`shasum` path:

```bash
tmp=$(mktemp -d)
git show HEAD:Tinycast/Core/Calculator/CurrencyData.generated.swift > "$tmp/currency"
git show HEAD:Tinycast/Core/Emoji/EmojiData.generated.swift > "$tmp/emoji"
git show HEAD:Tinycast/Core/EdgeDissolve.swift > "$tmp/edge"
git show HEAD:Tinycast/Core/ThinScrollbar.swift > "$tmp/thin"
shasum -a 256 "$tmp/currency" Tinycast/Features/Calculator/Model/CurrencyData.generated.swift
shasum -a 256 "$tmp/emoji" Tinycast/Features/Emoji/Model/EmojiData.generated.swift
shasum -a 256 "$tmp/edge" Tinycast/DesignSystem/Scrolling/EdgeDissolve.swift
shasum -a 256 "$tmp/thin" Tinycast/DesignSystem/Scrolling/ThinScrollbar.swift
rm -rf "$tmp"
```

| Pair | HEAD old path hash | Current path hash | Result |
| --- | --- | --- | --- |
| Currency generated data | `4e8b77a72e7381390cce3ea2ea12e50e4eb2ee3593b933b1193ea895717d0922` | `4e8b77a72e7381390cce3ea2ea12e50e4eb2ee3593b933b1193ea895717d0922` | equal |
| Emoji generated data | `9bcce093b180120820587c61152a62feabd6669db384dca0f4c40bf2230dddce` | `9bcce093b180120820587c61152a62feabd6669db384dca0f4c40bf2230dddce` | equal |
| EdgeDissolve | `dc02f39793014c2b4a15fc8b1d81b65736fccc3acd0cd9c3324cc43d5b7161e6` | `dc02f39793014c2b4a15fc8b1d81b65736fccc3acd0cd9c3324cc43d5b7161e6` | equal |
| ThinScrollbar | `fdcef6ec3126d70eb378286c96575293be91f5eb15854cb9c0aea571f01b04c1` | `fdcef6ec3126d70eb378286c96575293be91f5eb15854cb9c0aea571f01b04c1` | equal |

## Residual risks

- The full manual UI regression checklist, launch/RSS measurements and pixel comparison were not run;
  the user explicitly waived these unavailable manual gates before Phase 35.
- The release executable is 4,936,336 B; pristine HEAD is 4,946,440 B. The user explicitly accepted
  this pre-existing MarkdownUI-dominated overage rather than changing the AI result UI or dependency.
- Removing redundant comments at this scale relies on the existing subsystem documentation retaining
  the architectural rationale; independent reviewers spot-checked the highest-risk subsystems.
