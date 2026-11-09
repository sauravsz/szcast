# Security Audit — szcast (working tree)

Read-only review. Scope actually covered: secret-pattern sweep, Keychain layer, extension JS runtime + Node shim host, CustomCommands shell runner, DeepLink parsing/consent, updater signature path, entitlements/Info.plist. **Not covered** (stated explicitly at the end): git-history scan, `.github/workflows`, `project.pbxproj` build settings (`get-task-allow`, hardened runtime), ExtensionStorage/OAuth token persistence internals, `ExtensionDeepLink` dispatch.

---

## 1. Committed / hardcoded secrets

**Result: none found.** Patterns searched across the whole tree (Swift, plist, yml, json, md, sh, js, pbxproj):

`AKIA[0-9A-Z]{16}`, `ghp_…36`, `github_pat_…`, `sk-ant-…`, `sk-…{32,}`, `sk-proj-…`, `AIza…35`, `xox[abprs]-…`, `sk_live_…`, `vck_`/`vcp_`, JWT `eyJ….eyJ…`, `-----BEGIN … PRIVATE KEY-----`, plus a generic `(api_key|secret|token|password|credential|bearer)\s*[:=]\s*"…{12,}"` and a long-base64 (`["'][A-Za-z0-9+/]{60,}={0,2}["']`) sweep.

All non-zero hits were adjudicated:

| Hit | Location | Verdict |
|---|---|---|
| `accessToken: "expired", refreshToken: "fixture-refresh"` | `Tests/mcp-oauth-test.swift:321,340,387,529` | **Test fixture** — literal strings `expired`/`fixture-*` |
| `access_token: 'fixture-access', refresh_token: 'rotated-refresh'` | `Tests/ai-fixtures/mcp-oauth-stub.js:10` | **Test fixture** — OAuth stub server |
| `const B64 = "ABCDEFGHIJKLMNOPQRSTUVWXYZ…+/"` | `Scripts/raycast-runtime/src/polyfills.js:736` | Base64 **alphabet constant**, not data |
| `Mn="ABCDEFGHIJKLMNOPQRSTUVWXYZ…+/"` | `szcast/Resources/RaycastRuntime.generated.js:20` | Same alphabet, minified build output |

No `.env`, `.pem`, `.p12`, `.p8`, `secrets.*` file appears in the tree.

⚠️ One real (non-secret) gap in shipped config:

`szcast/Info.plist:83`
```xml
<key>SzcastUpdatePublicKey</key>
<string></string>
```
The Ed25519 release-verification key is **empty in the working tree** — see finding M-2.

---

## 2. Findings

### H-1 — Extension runtime gives arbitrary third-party JS unrestricted filesystem, process and network access with no per-extension capability gate
**Severity: High** (violates the project's own stated threat model)

The `fs` shim does no path confinement whatsoever — any absolute or `~` path is passed straight to Darwin:

`szcast/Features/Extensions/Service/ExtensionNodeShims.swift:217-221`
```swift
func path(_ index: Int) throws -> String {
    guard let value = arguments[safe: index] as? String, !value.isEmpty else { … }
    return (value as NSString).expandingTildeInPath
}
```
and then, unrestricted: `readFile` (`:241`), `writeFile` (`:248`), `rename` (`:339`), `copyFile` (`:346`), `chmod` (`:360`, any mode), `remove` (`:329`).

Process execution, including a shell:

`ExtensionNodeShims.swift:531-536`
```swift
let useShell = spec["shell"] as? Bool ?? false
let task = Process()
if useShell {
    task.executableURL = URL(fileURLWithPath: "/bin/sh")
    task.arguments = ["-c", command]
```
Environment is inherited in full when no override is supplied (`:547-551`), so extension code reads the app's whole environment.

Network egress is unconditional and unrestricted by host:

`szcast/Features/Extensions/Service/ExtensionHostBridge.swift:159`
```swift
case "fetch": return try await fetch(arguments.first)
```
`ExtensionFetcher.request(spec)` is called with no domain allowlist (verified by dispatch; the fetcher itself was not read line-by-line, so the *absence of an allowlist* there is `[INFERENCE]`, but no consent/allowlist symbol exists anywhere under `Features/Extensions` — the only matching symbols are the `confirmAlert`/`confirmUninstall` UI confirmations).

The only gate is a one-time global switch:

`szcast/Features/Extensions/UI/ExtensionCoordinator.swift:38-59`
```swift
/// Also consent to run third-party JavaScript, so it asks before it starts.
func setExtensionsEnabled(_ enabled: Bool) {
```
Nothing prompts per extension, per command, or per capability. Critically, background/menu-bar commands run on a timer (`ExtensionRefreshPolicy.minimumInterval`, 10 s floor for menu-bar) with no user present, so an installed extension can exfiltrate files and the clipboard on a schedule after a single "Enable extensions?" click months earlier.

This contradicts `SECURITY.md`:
> "Szcast is offline by default and every networked feature is consent-gated. A path that reaches the network without consent, or survives consent being withdrawn, is high severity."

**Why it matters:** installing or refreshing any store/GitHub extension is equivalent to granting that extension full user-account code execution and unattended network access. "Extension installed" and "extension trusted with ~/.ssh, Keychain-adjacent files, and the clipboard" are conflated into one click.
**Fix:** add a per-extension capability manifest (fs roots, spawn, network hosts) enforced in `dispatch(api:…)`/`ExtensionFetcher`, prompting on first use of each capability, and deny `fetch`/`spawn` for `.background` launches unless explicitly granted.

---

### M-2 — Update signature verification is inert in this tree: the Ed25519 public key is an empty string
**Severity: Medium**

`szcast/Info.plist:83-84` ships `<string></string>` for `SzcastUpdatePublicKey`, and verification fails closed to `false`:

`szcast/Features/Updates/Service/UpdateSignature.swift:23-29`
```swift
private static var bundledKey: Curve25519.Signing.PublicKey? {
    guard let encoded = Bundle.main.object(forInfoDictionaryKey: publicKeyInfoKey) as? String,
        let raw = Data(base64Encoded: encoded)
    else { return nil }
    return try? Curve25519.Signing.PublicKey(rawRepresentation: raw)
}
```
`isSigned` therefore always returns `false`, and `UpdateInstaller` falls back to the *running* app's designated requirement:

`szcast/Features/Updates/Service/UpdateInstaller.swift:99-110` + `BundleSignature.swift:13-21`
```swift
let requirement = releaseSigned ? compiled(developerID) : runningRequirement
```
The any-team requirement (`BundleSignature.swift:5-11`, `"Any team, so a new one still updates through the release key"`) is consequently unreachable — but so is the release key's intended cross-team continuity. Trust in this configuration reduces entirely to "the staged bundle satisfies the installed app's own DR". That is still a real barrier, but the second, independent trust root the design documents does not exist in this tree.

**Why it matters:** the release pipeline must inject the key; if it ever ships without it (local build, ad-hoc DMG, forgotten `--dmg` flag), updates silently downgrade to single-root trust and the `.sig` asset is fetched and discarded. Also note `UpdateInstaller.isReleaseSigned` logs at `.public` on failure (`:104`), leaking fetch failures into unified log.
**Fix:** fail the update (do not proceed) when `bundledKey == nil` and the release channel is stable/beta, rather than proceeding unverified.

---

### M-3 — Extension code can signal any other process on the machine
**Severity: Medium**

`szcast/Features/Extensions/Service/ExtensionNodeShims.swift:595-603`
```swift
guard pid > 0 || pid < -1, pid != getpid(), pid != -getpgrp() else {
    throw ShimError.failed("kill EPERM", "EPERM")
}
guard Darwin.kill(pid, signal) == 0 else {
```
The guard excludes only Szcast's own pid and process group. Any other pid — the user's editor, a security agent, another app — is signalable with `SIGKILL`, from an unattended background command.

**Why it matters:** a malicious extension can terminate AV/EDR agents, backup daemons, or `WindowServer`-adjacent helpers as a precursor to F-1 abuse, without any prompt.
**Fix:** allow signalling only pid values this runtime itself launched (track them in `ExtensionAsyncProcess`), reject everything else with `EPERM`.

---

### M-4 — Extension assets are auto-marked executable on every scan
**Severity: Medium** (multiplier for H-1)

`szcast/Features/Extensions/Service/ExtensionCatalog.swift:151-170`
```swift
guard values.isRegularFile == true, values.isSymbolicLink != true,
    !fileManager.isExecutableFile(atPath: file.path), isExecutablePayload(file)
else { continue }
…
try fileManager.setAttributes([.posixPermissions: permissions | executeBits], ofItemAtPath: file.path)
```
and `isExecutablePayload` (`:172-185`) treats a `#!` shebang **or any Mach-O magic** as grounds to add `+x`. This runs inside `scan()`, i.e. on every launch, over content that came from a downloaded zip.

**Why it matters:** combined with H-1's `/bin/sh -c`, any file dropped into `assets/` becomes directly runnable without a user action, and a Mach-O payload gets the execute bit without a notarization check.
**Fix:** do not restore execute bits automatically; require an explicit, signed allowlist or refuse to execute anything from `assets/` that is not a script the user selected.

---

### M-5 — Deep-link surface is claimed under Raycast's own URL schemes
**Severity: Medium** (exposure — input validation itself is good)

`szcast/Info.plist:20-28`
```xml
<key>CFBundleURLSchemes</key>
<array>
    <string>raycast</string>
    <string>$(SZCAST_URL_SCHEME)</string>
    <string>com.raycast</string>
</array>
```
Any app, web page, or malicious document can therefore drive Szcast by opening `raycast://…`, not just `szcast://`.

The built-in parser and gate are sound: `DeepLink.link` rejects `/` and `.`/`..` in note names, requires a UUID for chat, and refuses the `extensions` host (`DeepLink.swift:68-77`); unknown rows are rejected before consent (`DeepLinkCoordinator.swift:150`); input-bearing keys include the query so an "Always Allow" never covers different arguments (`DeepLinkConsentPolicy.swift:11-16`); the consent dialog defaults to Cancel (`DeepLinkCoordinator.swift:245-249`).

Two residual gaps:
- `.note` and `.chat` bypass consent entirely (`DeepLinkCoordinator.swift:52-57`) — a page can enumerate/peek which note names exist by observing behaviour, and can force a chat window open.
- `CFBundleURLSchemes` claims `raycast://extensions/...`, whose handler is `ExtensionDeepLink`, which parses `arguments` **and `launchType`** straight out of the URL query (`szcast/Features/Extensions/Model/ExtensionDeepLink.swift:104-127`: `var launchType = ExtensionLaunchType.userInitiated` then overwritten from the query). Whether that path is consent-gated was **not verified** — `ExtensionDeepLink` dispatch/coordinator was outside what I read. `[SUSPECTED]` If the query-supplied `launchType` is trusted, a web page could force `.background` semantics (bypassing `ExtensionHostBridge.swift:423-425`'s "Signing in during a background refresh" guard).

**Why it matters:** claiming another product's scheme enlarges the attack surface to any `raycast://` link ever clicked; the `note`/`chat` consent exemption is an unauthenticated read/inspect primitive.
**Fix:** drop `raycast`/`com.raycast` from `CFBundleURLSchemes` if interop does not require it; put `.note`/`.chat` behind the same gate; verify `ExtensionDeepLink` rejects a URL-supplied `launchType` (force `.userInitiated` for non-Szcast sources).

---

### L-6 — Keychain items carry no accessibility class and no per-item ACL
**Severity: Low** (no plaintext-on-disk credentials; storage choice is correct)

`szcast/Platform/KeychainSecretStore.swift:79-89`
```swift
var query: [String: Any] = [
    kSecClass as String: kSecClassGenericPassword,
    kSecAttrService as String: service,
    kSecAttrAccount as String: account.uuidString
]
```
No `kSecAttrAccessible`, no `kSecAttrAccessControl`, no `kSecUseDataProtectionKeychain`, no `SecAccessControlCreateWithFlags`. Provider keys, request headers, MCP header values/environments/OAuth credentials and installed-AI env vars are all Keychain-stored JSON blobs under `"<bundleID>.ai-api-keys"` etc. (`:12-16`) — **this is correct; nothing sensitive lands in `UserDefaults`**, and `AISettingsStore` persists only connection metadata (`AISettingsStore.swift`, `persistConnections`).

Residual weakness: on macOS the item defaults to the legacy file-based login keychain, where access is granted per-application by a user dialog and remembered. Any other program the user is once tricked into approving can read the same items; `KeychainSecretStore` also has no `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly` semantics, so items ride keychain/iCloud backup paths according to the user's keychain settings. Also `values(for:)` swallows a decode failure and reports "no values" (`:66-69`), which converts corruption into silent credential loss rather than an error.

**Fix:** add `kSecAttrAccessible: kSecAttrAccessibleWhenUnlockedThisDeviceOnly` and `kSecUseDataProtectionKeychain: true`, and an `SecAccessControl` requiring biometry/presence for the AI-key scope.

---

### L-7 — `mkdir` in the extension `fs` shim is created world-writable pre-umask
**Severity: Low**

`ExtensionNodeShims.swift:309`
```swift
guard Darwin.mkdir(target, 0o777) == 0 else { throw fileError("mkdir", target) }
```
The process umask trims this in practice (typically `0755`), but the shim also exposes `chmod` with arbitrary modes (`:360-368`), so an extension can explicitly `chmod` any file it can reach to `0777`. Only matters for shared/multi-user Macs.
**Fix:** mask to `0o700`, and bound `chmod` to modes without group/other write.

---

## 3. Checked and clean

- **Hardcoded secrets** — full-format + heuristic sweep across the tree; only labelled fixtures and base64 alphabets matched (§1).
- **ATS / TLS overrides** — no `NSAllowsArbitraryLoads`, `NSAllowsArbitraryLoadsInWebContent`, `NSExceptionDomains`, `NSExceptionAllowsInsecureHTTPLoads`, `SecTrustSetExceptions`, or custom `URLSessionDelegate` trust handling anywhere in the repo.
- **Keychain usage** — the entire keychain surface is one file (`KeychainSecretStore.swift`, 4 scopes, documented as such); `hasSecret` deliberately avoids materialising secret bytes (`:34-41`).
- **AI keys on disk** — `HTTPAIProvider` receives the key in memory (`HTTPAIProvider.swift:5-9`); no `defaults.set` of a key string; `AIConnection` (`Model/AIConnection.swift`) holds only metadata. `AIConnectionKeyPolicy` prevents a key following a retargeted endpoint.
- **Custom-command argument injection** — arguments are passed as positional argv after the `-c` script (`ShellCommandRunner.swift:353-356`: `[flag, command, "szcast"] + arguments`), so user-typed values land in `$1…$n` and are never re-parsed by zsh. The `#!` path writes a `0o700` script and execs via `exec "$0" "$@"` (`:359-368`) — same property, no splice.
- **Custom-command temp files** — output capture is `mkstemp` (`:399-411`), scripts use a UUID name with `0o700` (`:359-364`) and are removed on every exit path (`:98`, `:158`, `:166`). No temp-file race found.
- **Custom-command gating** — one run funnel (`CustomCommandCoordinator.swift:251-259`) enforcing the feature switch, `isEnabled`, required-argument completeness, and the per-command `requiresConfirmation`; Raycast script import is behind a confirmation that states scripts run with the user's account (`:228-238`).
- **Quicklink deeplink injection** — `createQuicklinks` only accepts an `openWith` bundle ID that is actually installed (`DeepLinkCoordinator.swift:356-360`); quicklink→quicklink recursion is blocked at the source level (`DeepLinkSource.mayRun`).
- **Updater privilege level** — no helper, no `SMJobBless`, no root: `UpdateInstaller.install` performs `FileManager.replaceItemAt` in the user's own bundle directory after a writability precheck (`UpdateInstaller.swift:44-48, 77-95`), and re-verifies the exact code hash immediately before the swap (`:84-86`). Extraction uses `/usr/bin/ditto -x -k` into a private staging dir (`:113-125`), and the staged app must match bundle ID and version (`:128-148`). Zip-slip content outside the staging directory is not independently checked, but is constrained by `ditto`'s archive handling — `[INFERENCE]`.
- **Deep-link parser validation** — `settings` rejects slashes, `note` rejects `/`, `.`, `..`, `chat` requires a UUID, `window-size` requires named fields; unknown entries and non-existent rows are refused before any prompt (`DeepLink.swift:68-77`, `DeepLinkCoordinator.swift:150, 164-169`); consent defaults to Cancel and drops concurrent links.
- **Extension `open()` file flags** — masked to an allowlist, `O_CLOEXEC` always added, `O_EXLOCK` excluded deliberately (`ExtensionNodeShims.swift:11-13, 232-234`); a 256-handle cap (`:227`) bounds descriptor exhaustion.
- **Entitlements** — `szcast/Szcast.entitlements` is minimal and each key is justified in-file: no `app-sandbox` (needed for a launcher), `allow-jit` (JavaScriptCore), `automation.apple-events`, camera, audio-input, calendars. No `com.apple.security.cs.disable-library-validation`, no `get-task-allow`.

---

## 4. Coverage gaps (not reviewed — do not read as "clean")

1. **Git history** — the `git log --all` / added-file scan for `*.pem`, `*.p12`, `*.p8`, `.env` was **not performed**. Current tree is clean, but a previously committed-then-deleted secret would not appear in my sweep.
2. **`.github/workflows/`** — not read; hardcoded credentials or over-broad token scopes in CI are unchecked.
3. **`szcast.xcodeproj/project.pbxproj` / `project.yml`** — `get-task-allow`, debug entitlements in Release, `ENABLE_HARDENED_RUNTIME` and `OTHER_CODE_SIGN_FLAGS` were not inspected.
4. **`ExtensionStorage` / OAuth token persistence** — `ExtensionHostBridge.swift:441-448` routes `getTokens`/`setTokens` into `context.storage`; the on-disk format, location and file mode of those third-party OAuth tokens were not verified. `[SUSPECTED]` they live under Application Support rather than the Keychain.
5. **`fetch`/WebSocket internals** — `ExtensionFetcher` was not read line-by-line; the "no host allowlist" conclusion is inferred from the absence of any allowlist/consent symbol in the feature directory.
6. **`ExtensionDeepLink` dispatch** — whether a URL-supplied `launchType` is honoured (M-5, second bullet) needs one file read to settle.
---

## 5. Addendum — 2026-11-09, gap closure

Coverage gaps §4 closed by direct inspection:

1. **Git history — clean.** `git log --all --diff-filter=A --name-only` added-files scan for
   `.env/.pem/.p12/.p8/.p7b/.pfx/keystore/jks/mobileprovision` + any `secret|credential|^\.env`
   file, plus a full `git log --all -p` regex sweep for `AKIA…`, `ghp_…`, `github_pat_…`,
   `sk-ant-…`, `sk-…{32,}`, `AIza…`, `xox[abprs]-`, `sk_live_`, and
   `-----BEGIN … PRIVATE KEY-----`. Zero history hits. Only files ever added matching the
   secret-ish names are `MCPSecretStore.swift` and `KeychainSecretStore.swift` (code, not secrets).

2. **`.github/workflows` — clean.** Only three files: `issue-link.yml`, `release.yml`,
   `triage.yml`. All credentials are `secrets.*` references sourced from GitHub Actions
   secrets (`DEVELOPER_ID_P12_BASE64`, `P12_PASSWORD`, `NOTARY_KEY_P8_BASE64`,
   `NOTARY_KEY_ID`, `NOTARY_ISSUER_ID`, `UPDATE_SIGNING_KEY`, `DISCORD_WEBHOOK_URL`,
   `HOMEBREW_TAP_TOKEN`) plus `github.token`. No plaintext secrets in the workflows; the
   permissions blocks are minimal per-workflow (`issue-link.yml` and `triage.yml` carry their
   own scoped permissions headers).

3. **Signing settings — `get-task-allow` absent, hardened runtime ON.**
   `szcast.xcodeproj/project.pbxproj:5291` → `ENABLE_HARDENED_RUNTIME = YES`; `CODE_SIGN_IDENTITY`
   is `"Szcast Self-Signed"` (self-signed, expected for a personal fork) in both Debug and
   Release configurations. `get-task-allow` appears nowhere in the project. No debug
   entitlement is wired into Release.

4. **`ExtensionStorage` / OAuth tokens — on disk, plaintext JSON, under Application Support.**
   Confirmed `[SUSPECTED]` from §4: third-party OAuth tokens ride `context.storage` and are
   persisted as an ordinary file under Application Support, not the Keychain — the only
   plaintext credential store in the app. AI provider keys, by contrast, live in Keychain via
   `KeychainSecretStore` (see §3). Treat every installed extension's OAuth refresh token as
   readable by any process running as the user.

5. **`fetch`/WebSocket — no host allowlist confirmed.**
   `ExtensionFetcher` performs the request with no domain filtering; there is no consent or
   allowlist symbol anywhere under `Features/Extensions`. The only prompts in that feature are
   `confirmAlert` / `confirmUninstall` UI confirmations. H-1's network half stands as verified.

6. **`ExtensionDeepLink` `launchType` — a web page can force `.background`. Verified live.**
   `ExtensionDeepLink.swift:107-116` parses `launchType`/`launch_type` straight from the URL
   query and sets `.background` when the value is `"background"`, and
   `ExtensionCoordinator.runDeepLink` (`ExtensionCoordinator.swift:95-109`) passes
   `link.launchType` into `run(...)` after only the global `settings.extensionsEnabled` check
   and an installed-command resolution. `AppCore.handleOpenURL` (`AppCore.swift:503-523`)
   routes *any* URL matched by `ExtensionDeepLink.claims(url)` to `runDeepLink` with no
   per-source gate. M-5's `[SUSPECTED]` is now a **confirmed** issue, and it upgrades one
   notch: combined with H-1 (background commands run on a timer), a `raycast://` link of the
   form `…?launchType=background` starts an installed extension command in background mode
   unprompted. Fix alongside the existing M-5 fix: reject or force-normalise the
   `launchType` parameter at the `ExtensionDeepLink` parse site (ignore the URL's value and
   always use `.userInitiated` for non-Szcast-source links) and stop claiming the
   `raycast` / `com.raycast` URL schemes if interop doesn't need them.

**Revised severity:** with §4.6 confirmed, the top items are H-1 (unattended exec) and
M-5 (URL-driven `launchType=background`) as a pair on the same extension-runtime attack
surface; M-2 (inert update signature) is medium but cheap to fail-closed.
