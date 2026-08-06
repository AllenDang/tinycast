# AI commands

A user-authored `<keyword> <text>` command: typing a keyword and a space in the launcher, then some
text, recognizes it — `trans hello` — and Enter runs that text through the user's own
OpenAI-compatible endpoint. What the command actually does (translate, fix grammar, summarize,
anything else) is entirely the user's `promptTemplate`; Tinycast ships no commands and bakes in no
provider name or URL. The catalog is authored in **Settings → AI Commands**, the same pane that holds
the endpoint, model and API key.

## Recognition happens at the raw query string

`AICommand.firstMatch(in:query:)` (`Core/AI/AICommand.swift`) parses the palette's query the same way
`CalcEngine.evaluate` parses `"5+3"` — at the raw string, before any fuzzy match runs, not by
searching over already-ranked rows. The first whitespace-delimited word is the keyword; everything
after the first space, trimmed, is the input. A bare keyword with no trailing space (`"trans"`, still
being typed) matches nothing yet, because there is no text to act on and firing on every keyword-shaped
word the user happens to type would be worse than firing on none. Matching is case-insensitive; the
store's own validation (mirroring `Core/CustomCommand.swift`'s shape — `Codable, Hashable, Identifiable,
Sendable`, `add`/`update`/`remove`/`replace(with:)`) additionally enforces that a keyword contains no
whitespace and is unique case-insensitively, so two commands can never both claim `trans`.

`RootPaletteView.aiCommandMatch` runs this only in `.launcher` mode and only when
`calcResult == nil` — the calculator card wins if a query somehow parses as both, which in practice
never happens since no unit or currency name is also a plausible AI-command keyword. It also re-checks
`aiProvider.isConfigured` right there: with the provider off, or on but missing a base URL, model or
key, this must read as though the feature doesn't exist — no card, not even a "not configured" hint —
the same way `.off` currency conversion produces no card at all rather than leaking that the feature
exists (see [calculator.md](calculator.md#consent)).

## The intent card is a preview, not an answer

`AICommandCard` (`Features/Launcher/AICommandCardView.swift`) occupies flat selection index 0 exactly
where `CalculatorCard` does, and for the same reason: `Tools/palette-selection-test.swift`'s row-order
contract has no separate slot for a second kind of leading card, so `LauncherList` treats them as
mutually exclusive alternatives at the one slot the flat index reserves for a "special" row (the
caller — `RootPaletteView` — never sets both `calc` and `aiIntent` at once).

The difference that matters: `CalculatorCard` **is** the answer, computed synchronously and locally by
a pure Foundation engine — nothing to wait for, nothing that can fail after the fact. `AICommandCard`
only shows intent — "use *Translate* on 'hello'" — because the real answer requires a network round
trip that must never start while the user is still typing. Only committing the card (Enter, or a
click) calls `AppCore.beginAICommand`, which is the one and only place a request actually goes out.

### The keyword-recognized-but-no-argument-yet hint

An AI command is never an `AppEntry` (see Settings below), so typing just its keyword — `"trans"`,
nothing after it — has no fuzzy-matched row to fall back on the way a custom command or quicklink
would. Without a second signal, that reads as a dead end: nothing in the list acknowledges the keyword
exists until the user has already typed a space and an argument, blind.

`AICommand.pendingKeyword(in:query:)` is that second signal. It fires exactly when `firstMatch` does
not — the query, up to the first whitespace (or the whole query, if there isn't one yet), spells a
configured keyword exactly, but there's no argument text after it yet (`"trans"` or `"trans "`, not
`"tra"` — a partial keyword still doesn't match anything, the same restraint `firstMatch` already
applies to an empty argument). `AICommandHintCard` renders it in the same flat-index-0 slot as
`AICommandCard` and `CalculatorCard`, mutually exclusive with both, but it is **selectable and never
actionable** — the same shape an error `CalculatorCard` already has. Enter does nothing (the existing
`selection - calcCount` arithmetic already lands on an out-of-range index, the same guard that makes
Enter a no-op on an error card), and the pill/⌘K action group hides entirely rather than showing a
misleading label.

## Provider consent

`AIProviderStore` (`Core/AI/AIProviderStore.swift`) mirrors `CurrencyRateStore`, the app's reference
shape for a networked feature (see [calculator.md](calculator.md#consent) and AGENTS.md's "every
networked feature ships off" invariant), with one difference: currency conversion polls a fixed
provider on a schedule, so it owns a refresh loop; an AI command is one request per Enter, so there is
no loop to start or stop — only the consent flag and the user's own endpoint configuration.

- **Ships off.** `isEnabled` defaults to `false` (`UserDefaults.bool` reads absent as `false`).
- **Not in `AppSettings`.** The flag lives on `AIProviderStore` alone, so `SettingsBackup` — which
  mirrors `AppSettings` field-for-field — can never import a config that silently grants network
  access.
- **The dialog names what leaves the machine.** Unlike Frankfurter, there is no fixed provider name to
  cite — the endpoint is whatever the user types into Base URL — so the consent dialog says "the
  endpoint you configure below" instead. It goes through `AppCore.confirmEnablingAIProvider`, which
  calls `DialogController` via `AppCore.confirm` like every other confirmation in the app; this feature
  never uses `NSAlert` or a plain SwiftUI `.sheet`, even though some older Settings panes still do.
- **Every entry point re-checks `isEnabled` (by way of `isConfigured`).** The card's own recognizer
  (above), `AppCore.beginAICommand` right before firing the request, and `AICommandSession`'s task both
  before the network call and immediately after the `await` returns — consent can be withdrawn while a
  response is in flight, and a late answer must never be shown or become copyable.
- **A private, cacheless `URLSession`.** `AIChatClient` uses `.ephemeral` with `urlCache = nil`, never
  `URLSession.shared`, so a request or response can never leave a second copy in the shared on-disk
  `URLCache`.
- **Turning it off keeps the user's configuration.** Unlike `CurrencyRateStore.setEnabled(false)`,
  which deletes the cached rates, disabling AI commands does not clear the base URL, model or API key —
  those are the user's own typed-in configuration, not something Tinycast downloaded, so there is
  nothing to "leave behind." Only the ability to match a keyword or fire a request stops.

## Why the API key lives in the Keychain

Every other persisted value in Tinycast is a UserDefaults key, a plist, or a file under Application
Support — none of them encrypted, none of them appropriate for a bearer token that grants access to a
paid account. `Core/AI/AIKeychain.swift` is a thin `Security.framework` wrapper (`SecItemAdd` /
`SecItemCopyMatching` / `SecItemUpdate` / `SecItemDelete`), styled like the other small utility enums
(`AppPaths`, `Permissions`) rather than a class with state — there is nothing to hold, only a
service/account pair to query. The service string is suffixed onto `Bundle.main.bundleIdentifier`, the
same channel-isolation rule every other persisted value in Tinycast follows: Dev (`com.tinycast.app.dev`),
beta and stable each get an independent Keychain item, so clearing one channel's key can never touch
another's. Base URL and model are not secrets, so — unlike the key — they live in plain
`UserDefaults` on `AIProviderStore` alongside the consent flag.

## The prompt template reuses the one template engine

There is no second parser. A command's `promptTemplate` expands through
[`SnippetTemplateEngine`](snippets.md#template-tokens) — the same engine Snippets and Quicklinks
expand through — via a new `{input}` token added to `SnippetTemplateEngine.ExpansionContext` rather
than a second ad hoc string-replace. `{input}` was added, instead of reusing an existing token, because
neither existing candidate means the same thing: `{selection}` is a captured *app* selection read
through Accessibility, not text typed into the palette, and `{argument}` always prompts for a missing
value — which would turn every AI command into a second-step form, defeating the point of recognizing
`<keyword> <text>` as one gesture. `{input}` defaults to the empty string for every other caller
(snippets, quicklinks), so it costs nothing outside this feature, and every other token the engine
understands — `{date}`, `{clipboard}`, `{uuid}` — still works inside a prompt template, since it is the
same expansion.

`AICommandSession.begin` captures the expansion context once, at the moment the request starts (the
same rule `QuicklinkArgumentSession` follows for its own captured context), with an empty clipboard
history and selection — an AI command's whole point is the typed `{input}`, so there is no captured app
state to read and no Accessibility permission this feature needs to ask for.

## The screen: loading → answer, never mid-keystroke

Committing the card calls `AppCore.beginAICommand`, which starts `AICommandSession`'s request and
flips `PaletteViewModel.mode` to `.aiCommand`. `AICommandScreen` (`Features/AI/AICommandScreen.swift`)
is a `PaletteScreen` like `UninstallScreen` and `QuicklinkArgumentsScreen` — reached only this way,
never entered directly, never in the Tab cycle.

The search field itself freezes for the same duration: `AICommandSession.begin` already captured the
query that matched the command as its `input` before the request went out, so the field stays
focused and showing that text (never resigning first responder), but further edits do nothing — the
request already ran on the input it captured. This reuses the same mechanism the footer's popover
menus freeze the field with; see [palette.md](palette.md#search-field-input-freeze).

`AICommandSession.state` is the whole state machine:

- **`.loading`** — the request is in flight. `rows` is empty, so the footer's "Copy Result" pill and
  Enter have nothing to do yet; the screen shows a spinner and the command's name.
- **`.result(String)`** — the answer landed. `rows` becomes one row, the pill appears, and Enter (or
  a click) calls `AppCore.finishAICommand`, which copies the text with `Paster.copyPlainText`, cancels
  the session, and hides the palette — the same three steps `copyCalculatorResult` takes for its own
  inline answer.
- **`.failed(String)`** — the request errored, consent was withdrawn mid-flight, or the endpoint
  returned something unreadable. The screen shows the message; there is nothing to copy.

Esc is the one place this screen's behavior deliberately differs from every other sub-screen's. Every
other screen's Esc just hides the palette (`core.hidePalette()`), preserving state for Pop to Root
Search — a quick reopen resumes exactly where the user left off, argument prompt or scan included. An
AI command's Esc instead calls `AppCore.cancelAICommand()` (which cancels the in-flight `Task`, if any)
and pops straight back to the launcher root. The request already reaches the network and already costs
the endpoint a call; "cancel" has to mean the request actually stops, not merely that its window is
hidden while it keeps running in the background and could resurrect itself on the next reopen. Leaving
the screen any other way — Tab, the back chevron, a fresh summon — cancels it too, via the same
`vm.mode` change handler `UninstallSession.cancel()` and `AppCore.cancelQuicklinkArguments()` already
use.

## Settings

**Settings → AI Commands** is its own tab (`SettingsTab.aiCommands`) rather than folding into
Miscellaneous: the provider configuration (Base URL, Model, API Key, the master switch) plus the
command catalog's own add/edit/delete list is comparable in size to the Quicklinks or Snippets panes,
which each earned their own tab over sharing Commands'.

The command list's add/edit/delete UI is **not** built on `LauncherItemsCard` — that component reads
`AppIndex`/`VisibilityStore` to toggle an existing `AppEntry`'s launcher visibility and hotkey, which
doesn't apply here: an AI command is never an `AppEntry` (nothing to launch with zero arguments — it
always needs the typed text after its keyword), so it never enters `AppIndex.publishEntries()` or
`LauncherList.rows`'s section list, and adding a case to `AppEntry.Kind` for something unselectable
from the launcher would be exactly the kind of category invented by sniffing a shape rather than the
thing actually being a category of launcher entry (see AGENTS.md's `AppEntry.Kind` invariant). Instead
the pane mirrors `CommandsSettingsView`'s own **custom commands** section — a `SettingsCard` with one
row per command (`AICommandSettingsRow`), an "Add…" row opening `AICommandEditorSheet` (styled after
`CustomCommandEditorSheet`), and delete behind a confirmation.

## Standalone harness

`Tools/ai-command-test.swift` compiles the real `AICommand.swift` — the model, `AICommandStore`'s
CRUD/validation, and `AICommand.firstMatch` — standalone:

```sh
swiftc -swift-version 6 Tinycast/Core/AI/AICommand.swift Tools/ai-command-test.swift \
    -o /tmp/ai-command-test && /tmp/ai-command-test
```

`AIKeychain`, `AIProviderStore`, `AIChatClient` and `AICommandSession` are deliberately not part of
this harness — they touch the Keychain, the network and `Foundation`'s `Task`, none of which the other
pure-Foundation harnesses attempt to fake, so they are covered by the app build instead, the same way
`RaycastImportV1` (AppKit-dependent) is covered by the build rather than the Raycast harness.
