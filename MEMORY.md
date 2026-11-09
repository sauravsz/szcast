# szcast — MEMORY

Fork of [Tinycast](https://github.com/abue-ammar/tinycast) by Abue Ammar, renamed **Szcast**. GitHub: `sauravsz/szcast` (fork of `abue-ammar/tinycast`). Clone: `Github Repos/szcast`.

Identity map:
- Bundle IDs: `com.sauravsz.szcast` (stable), `com.sauravsz.szcast.beta`, dev config `com.sauravsz.szcast.dev`. Helpers `com.sauravsz.szcast.*`.
- URL schemes: `szcast` / `szcast-dev` (plist key `SzcastURLScheme`, build vars `SZCAST_BUNDLE_IDENTIFIER` / `SZCAST_URL_SCHEME`).
- Product display names: Szcast, Szcast Dev, Szcast Dictation.
- Self-update is disabled by design: empty `SzcastUpdatePublicKey` and every bundle ID resolves to the development channel (ReleaseChannel). To ship updates later, add a signed release stream to `sauravsz/szcast` and a real key.
- Currency rates still call `https://tinycast.dev/api/v1/currencies` (upstream-hosted; kept working by choice).
- Support/about/changelog links point at the fork repo itself.

Attribution: AGPL-3.0. Copyright © 2026 Abue Ammar in LICENSE; NOTICE.md retains third-party material. Szcast is a fork of Tinycast; no affiliation implied.
