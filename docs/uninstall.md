# Uninstall Application

Removes an app _and_ the files it leaves behind — caches, preferences, containers, saved state,
launch agents. Reached from the launcher's Actions menu (⌘K → **Uninstall Application**) on
any `.application` entry; it opens the `.uninstall` palette sub-screen scoped to that app.

**Everything goes to the Trash.** `FileManager.trashItem` is the only removal call in the feature —
`removeItem` never appears. That is not a detail: it is what makes the attribution rules below
tolerable at all, because a false positive costs the user a drag back out of the Trash rather than
their data. If a "delete permanently" option is ever added, display-name matching must be dropped in
the same commit.

## Layers

Same split as `WindowManagement`: a pure half that decides, an impure half that touches the disk.

| File | Role |
| --- | --- |
| `Features/Uninstall/Model/UninstallTarget.swift` | Target identity, evidence and guard rails |
| `Features/Uninstall/Model/UninstallSearchRoot.swift` | Root table, legal styles, depth and CLI roots |
| `Features/Uninstall/Model/UninstallRules.swift` | Attribution and candidate path validation |
| `Features/Uninstall/Model/AdministratorTrashPolicy.swift` | Paths the signed helper may accept |
| `Features/Uninstall/Model/UninstallProtection.swift` | `PathFacts` → `UninstallProtection` |
| `Features/Uninstall/Model/UninstallPlan.swift` | Candidates, plan and selection |
| `Features/Uninstall/Service/UninstallScanner.swift` | Filesystem, signing metadata, sizes and FDA probe |
| `Features/Uninstall/Service/UninstallRunner.swift` | Ordinary and administrator Trash orchestration |
| `Features/Uninstall/Service/AdministratorTrashRunner.swift` | System authorization prompt and helper protocol |
| `TinycastTrashHelper/main.swift` | Signed root helper; policy check plus `trashItem` |
| `Features/Uninstall/Service/UninstallSession.swift` | `@MainActor` lifecycle behind the screen |
| `Features/Uninstall/UI/UninstallView.swift` | List, row and actions menu |

The first six compile standalone into `Tools/uninstall-test.swift`, so they stay Foundation-only
and take every environment fact as a parameter. The scanner hands the rules **child names**, never
URLs, which is what makes "no filesystem access in the pure layer" structural rather than a promise.

## Attribution

Five match styles enabled per root, plus a sixth mechanism for CLI launchers. Bundle metadata first
expands the target identity with embedded app/appex/XPC/service IDs, `SMPrivilegedExecutables` keys,
the main executable name and code-signing application groups. The ordinary ID/name styles then run
against `UninstallRules.matchableForms`, which strips `.plist`, `.savedState`, `.binarycookies`,
`.lockfile` and plug-in wrappers repeatedly, so `…​.plist.lockfile` reduces too.

**`bundleID`** — exact, or a namespaced child. The primary bundle ID, embedded component IDs and
helper IDs declared by `SMPrivilegedExecutables` all participate. The boundary check is load-bearing: a plain prefix
makes `com.apple.SafariTechnologyPreview` a match for `com.apple.Safari` and trashes a different
product's entire profile. Requiring the next character to be a separator means a match can only be a
namespace _descendant_ — `com.apple.iBooksX.CacheDelete` matches `com.apple.iBooksX`,
`com.apple.iBooksXtra` does not. Both `.` and `-` count, because `-` is how vendors name release
variants: `dev.zed.Zed-Preview.plist` belongs to Zed, unless Zed Preview is itself installed, in
which case the sibling rule below hands it straight back.

Two further guards on that rule:

- **Vendor namespaces don't prefix-match.** A two-component ID like `com.adobe` names a vendor, not a
  product, so `allowsBundleIDPrefixMatch` requires three components. `com.adobe` still matches itself.
- **An installed sibling owns its own artifacts.** If any _other_ installed app's bundle ID is an
  equal or longer match for the same component, the artifact is ambiguous or belongs to that app. Without this, uninstalling `com.tinycast.app`
  would also trash `com.tinycast.app.beta` and `…​.dev` — separate products that merely share a
  namespace, which is exactly the channel-isolation invariant in reverse.

**`groupContainer`** — strips a leading `group.` and/or a 10-character Team ID (uppercase
alphanumerics only, which is what stops an arbitrary `something.com.foo.Bar` being read as a
container), then applies the bundle-ID rule to the remainder.

**`applicationGroup`** — exact evidence from the target's code-signing
`com.apple.security.application-groups` entitlement. This catches shared containers whose authored ID
has no textual relationship to the app's bundle ID; unlike the fallback group-container rule it never
prefix-matches. Because groups are designed for sharing, a group claimed by any other installed app
is excluded rather than attributed to either member.

**`displayName`** — the weak one, and the only one hedged. Exact, case- and diacritic-folded equality;
never a prefix or substring, so "Books" and "Books Reader" cannot claim each other's folders in either
direction. On top of that a name must be ≥ 3 folded characters, must not be a standard Library
subdirectory name (`Preferences`, `Caches`, `Containers`, …), and **must not be shared with another
installed app** — a second app called "Mail" is precisely what makes `~/Library/Application Support/Mail`
unattributable. Three, not four, is the floor: Zed, IINA and Xee all name their own folders, and the
safety comes from those three guards rather than from length. Enabled in the human-named roots
(`Application Support`, `Caches`, `Logs`) and the plug-in wells; everywhere else a child is a bundle
ID by construction, so a name match there would be a false positive by definition.

A `.displayName` match **is** checked by default, and the row says "matched by name" so the weaker
evidence is visible before confirming. It earns that because the match is exact, confined, and never
claims a name another installed app answers to — and because the feature only ever moves to the
Trash, so an unwanted row costs a drag back rather than data.

**`executableArtifact`** — diagnostic reports in `Logs/{DiagnosticReports,CrashReporter}` whose
`.ips`, `.crash`, `.hang` or `.diag` stem starts with the app executable followed by `-` or `_`. The
separator and extension allowlist stop `Foo` claiming `FooHelper.txt`; an executable name shared by
another installed app disables this evidence entirely. The row identifies itself as a diagnostic
report.

**`binSymlink`** — a launcher in `/usr/local/bin`, `/opt/homebrew/bin`, `~/.local/bin` or `~/bin`
whose symlink resolves inside the app bundle. Attribution is by **link target, never by name**: `zed`
in `/usr/local/bin` is Zed's because it points at `Zed.app/Contents/MacOS/cli`, not because of what
it is called. On a stock Mac `/usr/local/bin` is root-owned, so the row renders locked; where
Homebrew has made it user-owned it is removable, and the classifier reaches that from the facts
without a special case.

`UninstallIdentity.make` returns `nil` — refusing the whole uninstall — when the target is Tinycast
itself, by bundle ID _or_ bundle URL, compared against the **running** identity so the Dev channel
refuses itself too.

### Roots

The **home directory itself is not a root**, and that is a decision rather than an oversight. Every
root lives under `~/Library` or `/Library`; nothing directly in `~` is ever a candidate. Claiming
`~/<name>` would rest on a name match, and `~` is the one place where a wrong match costs the user
their own work instead of an app's cache — VS Code's `CFBundleName` is literally `Code`, and `~/Code`
is a source tree on a great many machines. Narrowing it to dot-folders only moves the problem: an app
named "Local" would then claim `~/.local`, and screening for that needs a hand-kept blocklist with no
source of truth — the same reasoning that keeps slang out of `CalcCurrency.contested`. Measured
against 62 installed apps the entire root was worth one 115 kB folder, so it bought almost nothing
and carried the only catastrophic failure mode in the design. Raycast does list `~/OrbStack`; we
deliberately don't.

Most roots inspect immediate children. `Application Support`, `Caches`, `Caches/Metadata`, `Logs` and
`Metadata` also inspect one additional level, which catches vendor-nested layouts without turning the
scan into AppCleaner's broad Library walk. If an immediate child already matches it is emitted as one
row and its descendants are not duplicated. The pure path gate receives the root's depth limit and
rejects anything deeper.

Beyond the `~/Library` and `/Library` staples the table covers the plug-in wells — `QuickLook`,
`Services`, `PreferencePanes`, `Screen Savers`, `Internet Plug-Ins`, `Spotlight`, `Automator`,
`Input Methods`, contextual menus, Mail bundles, QuickTime, Widgets, ColorPickers, PDF Services,
keyboard layouts, scripting additions, audio VST/VST3/components/HAL and CoreMediaIO DAL. Their
children are wrappers named after the product that installed them, which is why
`strippedExtensions` drops their wrapper extensions. `.app` is deliberately **not** in that list. Deliberately out of scope, and worth
keeping out: `/private/var/db/receipts` (root-owned, and deleting a receipt
corrupts the installer's view of the system), `~/Library/Keychains`, `/Library/Extensions`, and every
user-document location. `/usr/local` is reached **only** through `binDirectories`, and only for
symlinks that resolve into the bundle — never by name, and never recursively.

`UninstallRules.isAcceptableCandidate` is belt and braces over whatever matched: within its
root's explicit depth limit, never the home directory or `/`, no relative components, and no overlap
with the app bundle (which is emitted separately).

## Locking

`UninstallProtection` is **advisory, not a security boundary** — TCC is evaluated at the syscall, so
it can be wrong in both directions. It exists to gray a row with an honest reason and to skip
obviously doomed attempts; `UninstallRunner` still reports per-item failure.

Precedence, asserted by the harness:

1. `!exists` → `.missing` (dropped from the plan)
2. `SF_RESTRICTED`/`SF_IMMUTABLE`, or a read-only volume → `.systemProtected` — this is what locks
   `/System/Applications/Books.app`, and it falls out of the facts rather than a hardcoded `/System`
   prefix
3. `UF_IMMUTABLE` → `.userLocked` (its own case: the user can clear it in Get Info)
4. a TCC-gated path without Full Disk Access → `.needsFullDiskAccess`
5. parent `SF_NOUNLINK` or not writable → `.requiresAdministrator` for a policy-approved path,
   otherwise `.parentNotWritable`
6. sticky parent _and_ not owned by the current user → `.notOwned`
7. → `.removable`

Steps 5 and 6 are the whole ownership story, and the order is deliberate. Removing a directory entry
is governed by the **enclosing directory**, not by who owns the item. A root-owned file in an ordinary
writable folder needs no elevation; a parent with `SF_NOUNLINK` (the `sunlnk` flag on `/Applications`)
or without write permission does. A path accepted by `AdministratorTrashPolicy` remains selectable
and is marked “administrator”; every other unwritable path stays locked. Ownership decides exactly
one case, a sticky parent (`S_ISVTX`, the `/tmp` rule), where only an owner may unlink.

This is why `/usr/local/bin/code` and a root-owned App Store app in `/Applications` remain checked but
carry the administrator label, while `/opt/homebrew/bin/orb` normally needs no elevation. The first
set cannot be moved by the user process; the second lives in Homebrew's writable prefix.

A locked candidate can never enter the checked set. `.requiresAdministrator` is not locked: it is an
explicitly selectable removal mode whose path already passed the same root/depth policy the helper
will enforce again. Every selection mutation still funnels through `plan.removableIDs`, so re-scanning
drops a row that has become genuinely locked.

The TCC list is **measured, not assumed.** A probe that creates and then trashes a throwaway
directory in each candidate location shows that `~/Library/Containers`, `~/Library/Group Containers`
and `~/Library/Cookies` refuse the move, while `~/Library/Application Scripts` and
`~/Library/Autosave Information` allow it — which is why Books' five `Application Scripts` rows are
checkable while the five `Containers` rows beside them are locked. Note that _listing_ a directory is
not the test: both container roots enumerate fine and still refuse the trash. Re-measure before
adding an entry.

**Administrator removal is narrow and one-shot.** The Tinycast confirmation states that a password
will be needed. Immediately before invoking `/usr/bin/osascript` for the system authorization dialog,
`AdministratorTrashRunner` validates the sealed app against the running process's designated
requirement and hashes the embedded helper. The privileged shell copies it into a root-owned temporary
directory and verifies that hash before execution, so the mutable app path is never executed after a
validation race. The signed helper accepts only paths admitted by `AdministratorTrashPolicy`, rejects
symlinked ancestors, reconstructs the invoking user's identity, calls `FileManager.trashItem`, and
returns one JSON outcome per path. It has no arbitrary command mode and is not installed as a
persistent daemon. Canceling authentication is a normal per-item failure; already-trashed ordinary
items remain reported honestly.

**Full Disk Access is detected, never requested.** The probe opens
`~/Library/Application Support/com.apple.TCC/TCC.db` — TCC denies that read _silently_, with no
prompt, which is what makes it usable under the rule that this feature asks for no permissions. It
runs once per scan, not once per candidate, and can only under-report (a per-folder grant reads as
"no access"), which just leaves a row locked.

Symlinks are never followed: `lstat`, and no descent when sizing. A symlinked candidate is judged and
trashed as the link.

## The screen

A `PaletteMode` case like Clipboard and Calculator History, so the back chevron, Escape,
bare-backspace exit, arrow nav and the menu-open input freeze all come from the shared contract (see
[palette.md](palette.md)). It does **not** join the Tab cycle. The search field filters candidates by
name or location; there is no sort control, and the footer's leading corner keeps the standard menu
circle. The primary pill is the one rendered in `Theme.Colors.destructive`.

↵ uninstalls, ⌘↵ toggles the highlighted row, clicking the checkbox toggles, double-clicking a row
toggles. ⌘K carries Uninstall, Select/Unselect File, Copy Path, Show in Finder and Show Info in
Finder. There is no launcher keybinding for Uninstall — it is a menu action only. Copy Path stays on the screen (losing a whole scan to copy one path is a bad
trade); the two Finder actions hand focus to Finder and so hide the palette. Show Info has no AppKit
route and drives Finder over Apple events, which raises the system Automation prompt on first use.

`AppCore.performUninstall()` is the one funnel, so neither ↵ nor the menu row can skip the
confirmation. It quits the app first if it's running, trashes, and **only clears the app's hotkey,
favorite, visibility and ranking when the bundle itself went** — a leftovers-only cleanup leaves the
app installed. The bundle is trashed last: either order can leave a partial state, but with the
bundle still in place the user can re-run the uninstall to retry, and once it's gone the launcher
entry that reaches this screen is gone with it. Success shows the message pill; partial failure names
what stayed behind.

## Tests

```sh
swiftc -swift-version 6 Tinycast/Features/Uninstall/Model/UninstallTarget.swift \
    Tinycast/Features/Uninstall/Model/UninstallSearchRoot.swift Tinycast/Features/Uninstall/Model/UninstallRules.swift \
    Tinycast/Features/Uninstall/Model/AdministratorTrashPolicy.swift \
    Tinycast/Features/Uninstall/Model/UninstallProtection.swift Tinycast/Features/Uninstall/Model/UninstallPlan.swift \
    Tools/uninstall-test.swift -o /tmp/uninstall-test && /tmp/uninstall-test
```

No filesystem, no temp directories — every input is a `String` or a `PathFacts`. Beyond the per-rule
assertions it ends with a cross-identity sweep: for a set of realistic apps × every root × every
artifact shape, no app's artifacts may ever be attributed to another. That is the one test that
catches a regression in the matcher as a whole rather than in a single rule.
