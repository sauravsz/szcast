# Implementation plan — szcast launcher features

Implemented 2026-11-10. Decisions held: **widen-in-place** (files stay after app/fallback rows, not files-first) and **file-search-enabled-only** gating (space prefix overrides the ambient "show file results in Launcher" toggle, but archives everything behind the master `fileSearchEnabled` switch).
One deliberate deviation from the plan below: space mode uses a **1-char** threshold instead of the ≥3 char rule. A one-character query is the whole point of Alfred quick search.

## Goal

Two Alfred-style features in the root launcher of `szcast`
(`/Users/sz/AIOS/Github Repos/szcast`), plus the delivered security audit (audit-only until a
separate go-ahead).

## Feature 1 — leading-space file search

Behaviour: opening the palette and pressing a space *first* (` ` then `query`) widens results to
files/folders, Alfred Quick-Search style. No Tab, no mode switch.

Confirmed mechanics:

- **No existing behaviour to gate behind.** `FileSearchQuery.answersLauncher` is always-false for
  space-prefixed queries (trimmed length ≥ 3 required). `prepare`/`terms` drop the leading space
  internally, but the coordinator's session search is skipped for space-prefixed queries today.
- **Delimiter is U+0020 only**, not tabs, and only exactly-one-space-prefix (`query.hasPrefix(" ")`).
  Apps are unaffected: `AppIndex` trims the query before matching (line 703 / 736).
- **Widen in place** (user-chosen): file matches stay *after* app/fallback rows in `rows`
  (`pinnedFavorites + results(.entry) + files(.file) + fallbacks(.fallback)`), limit stays 5,
  threshold stays 3 chars — the space trigger only makes a space-prefixed query answer when the
  trimmed text is ≥ 3 chars.
- **Gate:** `settings.fileSearchEnabled` only (user-chosen): the space prefix is explicit
  intent, so the ambient `fileSearchShowInLauncher` toggle is *not* consulted in space mode.
  Non-space mode keeps the existing `showsFilesInLauncher` gate untouched.
- **Home screen unchanged:** `pinsFavorites` is true while the trimmed query is whitespace-only,
  so a bare ` ` shows favorites exactly as today (no new empty state, no mode-switch).

### Edits

### Interaction note (added)
File rows in `FileSearchList` use `onRowClick` (double-click activates) while launcher rows use
`onRowTap` (single tap activates), so the same action feels different between windows. Left
unchanged: `onRowTap` exists so drag-out never activates — on launcher rows a drag is an intent,
so single-tap-to-open was the deliberate choice there. If unified feel is later wanted, the seam
is swapping `onRowTap` for `onRowClick` on the launcher's file rows — the semantics already
exist on the file screen.
1. `szcast/Features/FileSearch/Model/FileSearchQuery.swift`
   - Add a single parser: `static func fileTerms(_ query: String) -> (isSpacePrefixed: Bool, term: String)`
     — `isSpacePrefixed = query.hasPrefix(" ")`; `term = String(query.dropFirst()).trimmingCharacters(in: .whitespacesAndNewlines)`.
     Everything downstream uses `(isSpacePrefixed, term)` instead of the raw query.
   - `answersLauncher` unchanged for the non-prefixed path (≥ 3 trimmed chars), gains a
     space-prefixed branch where the trimmed remainder must be ≥ 3 chars (per the user's
     widen-in-place choice, no 1–2-char shortcut).
   - `launcherResults` consumes the parsed term so favorites can still filter by terms and the
     indexed results can still cap at `launcherLimit = 5`.
   - `prepare`/`terms` need no changes (they already drop the leading whitespace).

2. `szcast/Features/FileSearch/UI/FileSearchCoordinator.swift`
   - `searchFromLauncher(_ query:)` — if the query is space-prefixed, skip the
     `showsFilesInLauncher` ambient gate but still require `settings.fileSearchEnabled`;
     search the **trimmed remainder** so the index never sees the prefix.
   - `launcherFiles(for:)` — space-prefixed: require `fileSearchEnabled` only, read
     `session.results`, delegate to the new `launcherResults` with the parsed term.
     Non-prefixed path unchanged (`showsFilesInLauncher` still required).
   - `applyLauncherFiles()` — keep the launcher-only guard; it will start working for
     space-prefixed queries automatically once the two above accept them.

3. `szcast/Features/Launcher/UI/LauncherScreen.swift`
   - Line 77: `let files = pinned == nil ? core.fileSearchCoordinator.launcherFiles(for: vm.query) : []`
     — no change needed; the coordinator parses the prefix internally.
   - Line 79 (`pinsFavorites` via `trimmingCharacters(...).isEmpty`) and the `files`
     appended last in `entries` (lines 84–86) are **unchanged** under the widen-in-place choice.

4. `szcast/Palette/RootPaletteView.swift`
   - `.onChange(of: vm.query)` (line 427) calls `searchFromLauncher(vm.query)` unchanged —
     the coordinator now interprets the prefix. No new dispatch case.
   - Compact-mode interaction: `PaletteCoordinator.queryIsBlank` trims `.whitespaces`, so a
     leading space alone cannot silently expand the bar; typing after the space expands exactly
     as typing text does today. No special-casing needed.

### Tests

- Extend `Tests/file-search-test.swift` (wired in `Scripts/run-tests.sh:121` via `$FS/Model/*.swift`):
  - `fileTerms("report") == (false, "report")`
  - `fileTerms(" report") == (true, "report")`
  - `fileTerms("  report") == (true, "report")` (second space swallowed by trim)
  - `fileTerms(" ") == (true, "")`, and `answersLauncher(" ") == false` (home screen unchanged)
  - `answersLauncher(" ab") == false` (still 2 chars — widen-in-place keeps the ≥ 3 rule)
  - `launcherResults` on a space-prefixed 3-char query still yields results against a
    2-char query → nothing (documents the threshold under the chosen option).
- Do **not** add a harness for the SwiftUI screen — coverage of the row wiring is the
  `run-tests.sh` pass + manual launch.

## Feature 2 — ⌘1–⌘9/⌘0 activates the Nth visible result

Today ⌘1–0 is intercepted at `PaletteWindowController.swift:444` for `.launcher`/`.clipboard`
and routed `noteFavoriteSlot` → `RootPaletteView.swift:499` →
`PaletteShortcut.favoriteSlot(Int)` → `LauncherScreen.launchFavorite(at:)` (line 415), which only
launches a *pinned favourite* and returns `false` otherwise.

Alfred seam (disjoint, so either rule can win cleanly): favorites are only pinned while the
trimmed query is whitespace-only (`pinsFavorites`). A typed query ⇒ no slots. So the rule:

- **Blank query** → ⌘N still launches favorite N. (Unchanged; not a redesign away from
  favourites.)
- **Typed query** → ⌘N activates the Nth row in the flat `rows` array. `rows` includes the
  lead card at index 0, and `row(at:)` already bounds-checks, so the handler is:

  ```swift
  private func launchSlot(at index: Int) -> Bool {
      if pinnedFavorites.indices.contains(index) {
          activate(at: index + (leadCard == nil ? 0 : 1))
          return true
      }
      let target = index + (leadCard == nil ? 0 : 1)
      return activate(at: target)   // activate() safely no-ops / guards nil
  }
  ```

  i.e. `launchFavorite` drops its favorites-only guard and activates the flat row. The same
  `leadCard` offset covers both branches; `.fallback` rows and the calc/color cards participate
  because they are `Row`s.
- **Renaming**: rename `PaletteShortcut.favoriteSlot` → keep the case name (it is consumed by
  `ClipboardScreen` too, where favorites semantics are untouched). Minimal diff; avoid a
  three-file rename for a label. *(If a rename is later wanted, the case is a mechanical
  3-file change: `PaletteShortcut`, `LauncherScreen` `perform`, `ClipboardScreen` `perform`.)*
- **Numbering affordance**: plain-result rows in `LauncherList` currently pass `slot: nil`
  (`AppRow`/`FileSearchRow`). Give `AppRow`/`FileSearchRow` non-favorite rows the digit chip:
  in `LauncherList`'s renderer, when a query is typed (favorites absent) pass
  `slot: FavoriteSlots.digit(at: flatIndex)` for the first 10 rows, where `flatIndex` is the
  row's position in `rows`. Favourites keep their existing `slot` path. Both row types already
  render through the same `KeyCapChip(text:)`-declaring chip view used by favorites, so the
  affordance reuses the shipped glyph stroke — no new view code.
- **Clipboard screen unchanged**: `ClipboardScreen.perform(.favoriteSlot)` keeps pinned-item
  activation. Not in scope.

### Tests

- `Tests/favorites-test.swift` — `FavoriteSlots` already covers keycode→index and digit
  round-trips; no new assertion needed for the mapping itself.
- `Tests/launcher-test.swift` (if present) — assert that slot→row arithmetic stays
  consistent with `launchSlot(at:)` (favorite N ↔ row `N + offset`). Otherwise rely on the
  full harness suite + manual check.

## Security audit (delivered, in `/tmp/audit.md`)

Full sweep already completed; audit-only, no remediation yet.

- **Secrets: clean.** No hardcoded keys/tokens anywhere (tree + `git log --all` added-files/
  `-p` format sweep). Hit-pattern table is in the audit (§1). No `.env`/`.pem`/`.p12`/`.p8`.
- **High: H-1** — the extension runtime (`ExtensionNodeShims`) gives extension JS unrestricted
  fs access (`readFile`/`writeFile`/`rename`/`copyFile`/`chmod`/`remove`, `path()` only
  expands `~`), arbitrary `/bin/sh -c` spawn with inherited environment, and network `fetch`
  with no host allowlist or per-extension consent. Only a global one-time "Enable extensions?"
  switch gates it; background/menu-bar commands run on a timer → unattended code execution
  after a single click. Contradicts `SECURITY.md`'s "offline by default, every networked
  feature consent-gated" threat model.
- **Medium: M-2** — `SzcastUpdatePublicKey` is an empty string in `Info.plist`, so update
  signature verification is inert; `UpdateInstaller` falls back to the running app's
  designated requirement.
- **Medium: M-3** — extension code can `kill()` any pid except Szcast's own (can SIGKILL
  AV/EDR agents from a background command).
- **Medium: M-4** — extension assets are auto-marked executable on every scan (shebang or
  Mach-O magic → `+x`).
- **Medium: M-5** — `CFBundleURLSchemes` claims `raycast`/`com.raycast` (any web page can drive
  via `raycast://`); `.note``/`.chat` deeplinks bypass consent entirely; and `ExtensionDeepLink`
  parses `launchType` straight out of the URL query (so `?launchType=background` on a
  `raycast://` link yields a background extension launch — verified live after the audit
  (`ExtensionDeepLink.swift:104-127`, `runDeepLink` in `ExtensionCoordinator.swift:95`).
- **Low: L-6** — Keychain items have no accessibility class / access-control attributes (correct
  store, weak ACL). **L-7** — extension `mkdir` is `0777` pre-umask.
- **Checked & clean:** ATS / TLS overrides, AI key storage (Keychain only), custom-command
  argv injection, temp-file races, custom-command gating, quicklink deeplink injection,
  updater privilege level (no helper/root), deeplink parser validation (rejects slashes/`..`,
  UUID for chat, refuses `extensions` host, consent defaults to Cancel), entitlements
  (no `get-task-allow`, hardened runtime on), `.github/workflows` (secret refs only,
  itemised per-file — no hardcoded credentials), `git log --all` history scan (no secret
  patterns in any revision).

## Verification (pending implementation)

- `Scripts/run-tests.sh` (113 harnesses) — full pass.
- Targeted: `Scripts/run-tests.sh file-search-test`, `Scripts/run-tests.sh launcher-file-test`,
  `Scripts/run-tests.sh favorites-test`.
- Build: `xcodebuild -project szcast.xcodeproj -scheme Szcast -configuration Debug -derivedDataPath build/DerivedData build`
- Manual smoke: launch the Debug build, in the launcher type ` demo` with file search enabled
  and confirm file rows appear with ⌘ digits; then type `dem` (no prefix) and confirm ⌘1
  lands on the first result; then clear and confirm ⌘1 still launches favorite 1.

## Not doing (explicitly out of scope)

- Files-first ordering in space mode (the user chose widen-in-place).
- Clipboard/Tinycast-Tab-ring ⌘N semantics (favourites only there; unchanged).
- Security remediation (H-1/M-2/M-3/M-4/M-5/L-6/L-7 are report-only until a separate go-ahead).
- `szcast.dev` purchase + DNS.
- Ed25519 release-key / Developer ID pipeline (self-update stays inert).
