# szcast — MEMORY

Fork of [Tinycast](https://github.com/abue-ammar/tinycast) by Abue Ammar, renamed **szcast**. GitHub: `sauravsz/szcast` (fork of `abue-ammar/tinycast`). Clone: `Github Repos/szcast` (`upstream` remote → abue-ammar/tinycast).

## Layout
- Source root `szcast/`, Xcode package `szcast.xcodeproj`, scheme `szcast`, entry `szcast/App/szcastApp.swift`, icon `szcast/szcast.icon`.
- Display strings stay capitalised: `szcast`, `szcast Dev`, `szcast Dictation`; signing identity `szcast Self-Signed`.

## Identity map
- Bundle IDs: `com.sauravsz.szcast` (stable), `.beta`, dev config `.dev`. Helpers `com.sauravsz.szcast.*`.
- URL schemes: `szcast` / `szcast-dev` (plist key `SzcastURLScheme`, build vars `SZCAST_BUNDLE_IDENTIFIER` / `SZCAST_URL_SCHEME`).
- Updater: `ReleaseFeed.repository = sauravsz/szcast`; stable/beta channels are wired, but `SzcastUpdatePublicKey` now carries a real Ed25519 key (`IwtZDpOb…vac=`, private half out of the repo); no update feed is published, so nothing installs over itself yet. Releases are built and signed locally — CI needs a Developer ID, which this fork does not buy.
- Currency rates still call `https://tinycast.dev/api/v1/currencies` (upstream-hosted; kept on purpose). Needs a `GET /api/v1/currencies` and `/currencies/crypto?symbols=` JSON shape if self-hosting.
- Support/About/changelog links point at the fork repo; upstream Discord, funding URL and release team secrets removed.

## Web / deploy
- Static landing page in `site/` (`index.html`, `docs-images/`, `docs-screenshot.jpg`); `vercel.json` sets `outputDirectory: site`. Never add `"framework": "static"` — not a valid slug, it fails schema validation; omit the key for static.
- Vercel project `szcast` (`prj_dxHc1UekHSnarwZdUH9xYsmeQJL0`, team `team_6BdgmeJhD8C2QlwQhVFkWTmk` / "Abhigha's projects"), linked to `sauravsz/szcast` via the GitHub integration: every push to `main` deploys. Live at https://szcast.vercel.app.
- `szcast.dev` is attached to the project but unregistered/unpurchased (Vercel registrar: available, $9.99 first year / $13 renewal). No DNS yet — README/About hand-written URLs must stay on `szcast.vercel.app` until it's bought.
- Local Vercel CLI is logged out and cannot log in here (network `EBADF` on login/`whoami`); use the REST API with a token instead of the CLI.

## Build / verify (macOS 27, Xcode 27.2)
- `xcodebuild -project szcast.xcodeproj -scheme szcast -configuration Debug build`
- `Scripts/run-tests.sh` — all 113 harnesses pass. `Scripts/build-dmg.sh` → `build/szcast-0.1.0.dmg`; needs the `szcast Self-Signed` keychain identity (already created; without it Accessibility/TCC grants reset each build).

Attribution: AGPL-3.0. Copyright © 2026 Abue Ammar in LICENSE; NOTICE.md keeps third-party material. Fork of Tinycast; no affiliation implied.
