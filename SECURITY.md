# Security Policy

## Reporting a Vulnerability

Report privately through GitHub: **Security** tab → **Report a vulnerability**.

Include your macOS version, the szcast version and channel, reproduction steps, and the impact.
Please don't disclose publicly until it's fixed.

We'll respond as quickly as we can and keep you posted.

## Supported Versions

Current stable and beta only. Update from
[Releases](https://github.com/sauravsz/szcast/releases/latest) before reporting — this build has no
Homebrew cask, and releases are self-signed rather than notarized.

## Scope

Of particular interest:

- **Accessibility (TCC)** — anything that widens what the paste grant enables.
- **Clipboard history** — text and images cached on disk; unintended exposure or capture.
- **Network** — szcast itself is offline by default and its own networked features are consent-gated.
  A path that reaches the network without consent, or survives consent being withdrawn, is high
  severity. **Installed extensions are the known exception:** their `fetch` has no host allowlist and
  no per-extension consent beyond the one-time "Enable extensions?" switch. That gap is documented in
  [`docs/SECURITY-AUDIT.md`](docs/SECURITY-AUDIT.md) as H-1, so reports about it are already known
  rather than new.
- **Hotkeys** — the in-house hotkey stack and the Input Monitoring grant.
- **Signing and distribution** — the DMG chain. Releases are self-signed, so macOS asks once on
  first launch; a signed update is verified against `SzcastUpdatePublicKey`.

Out of scope: anything needing existing code execution or admin rights on the machine.
