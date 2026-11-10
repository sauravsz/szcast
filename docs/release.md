# Release

How a build reaches a user. The local development loop is in [development.md](development.md);
the signing identity itself is in [signing.md](signing.md).

> **This fork releases by hand.** Releases are self-signed with `Szcast Self-Signed` and are **not
> notarized**, so there is no Developer ID chain: users right-click → Open once. The sections below
> describing the CI workflow, notarization and the `universal` job document the upstream pipeline —
> `release.yml` is kept intact but **cannot run** without a Developer ID certificate and an App Store
> Connect key, and it fails loudly at its first signing step. Everything up to and including
> "Packaging a DMG locally" is what actually applies here. `v1.0.0` was produced that way.

## Packaging a DMG locally

```sh
./Scripts/build-dmg.sh            # -> build/Szcast-<version>.dmg (version from project.yml)
./Scripts/build-dmg.sh 0.5.7      # -> build/Szcast-0.5.7.dmg
```

It builds a Release `Szcast.app` signed with `Szcast Self-Signed` and packs it with an
`/Applications` symlink. Official per-channel releases are built by CI, below.

## Signing & Gatekeeper

CI releases are signed with the team's Developer ID, notarized and stapled, so a downloaded DMG
opens without a Gatekeeper warning. Local builds, `build-dmg.sh` included, keep signing with
`Szcast Self-Signed` and are never notarized. Full details in [signing.md](signing.md).

## How the in-app updater consumes a release

Every release publishes three assets from one build: `Szcast-<version>.dmg`, which people download
by hand, `Szcast-<version>.zip`, which the in-app updater installs, and `Szcast-<version>.zip.sig`,
the zip's signature by the release key. The zip is produced with
`ditto -c -k --keepParent --sequesterRsrc` — the only zip that leaves the code signature verifiable,
which matters because the updater refuses any bundle it cannot prove is ours.

This build ships **arm64 only**. There is no `universal` job: macOS 26 is the last release that boots
on Intel, and the fork does not publish an Intel slice. `ReleaseFeed` still understands the
`-Universal-` marker, so publishing one later needs no client change.

Three things a release must keep true, or the updater skips it:

- **It carries a `.zip` asset this Mac can run.** A DMG-only release is not installable and is not
  offered, and an Intel build is offered nothing rather than a thin arm64 zip.
- **The tag parses as `vMAJOR.MINOR.PATCH` or `vMAJOR.MINOR.PATCH-beta.N`,** and agrees with the
  `prerelease` flag. A tag of any other shape is treated as mis-published and skipped.
- **It is not a draft.**

**There is no Homebrew cask.** Releases are self-signed and not notarized, so they are installed by
dragging the app out of the DMG. A cask would need a notarized build to be worth having; see
[signing.md](signing.md). The `Update Homebrew cask` step in `release.yml` is a no-op unless
`HOMEBREW_TAP_TOKEN` is set, and that tap does not exist.

## Pull request review

There is no CI workflow and no automated reviewer, so the whole bar in
[testing.md](testing.md#definition-of-done) is run locally before a PR is opened.

## Releasing

`.github/workflows/release.yml` builds and publishes a DMG from GitHub Actions, no local machine
needed. Run it from the **Actions** tab (`Release` → **Run workflow**) and pick:

- **channel** — `beta` or `stable`. Each builds a distinct app (`Szcast Beta.app` / `Szcast.app`)
  with its own bundle id, alongside the local `Szcast Dev.app`. Beta gets an auto-incrementing
  `-beta.N` suffix (`N` = the Actions run number) so re-running never collides; stable ships the
  version as-is.
- **version** — base semver, e.g. `0.2.0`.

Its first step is `Scripts/check-migrations.sh`: a migration that a stable release already shipped
stops the run until it is deleted ([migrations.md](migrations.md)). The check reads tags and history,
so the checkout fetches every commit without blobs.

It builds on an `xcode-27` runner with the newest released Xcode 27 and publishes a GitHub Release
tagged `v<full-version>` with a versioned DMG and zip asset, marked prerelease for beta. On success
it also announces the release on Discord. A stable run also dispatches the Website workflow, because
the site reads the latest version and the [changelog](https://szcast.dev/changelog/) from GitHub at
build time.

A stable run then fans out to a second job, `universal` (present in the workflow, not used here), which rebuilds the same commit with
`ARCHS="arm64 x86_64"` and attaches `Szcast-Universal-<version>.dmg` / `.zip` to the release the
first job created, then bumps `szcast-universal`. macOS 26 is the last release that boots on Intel,
and those Macs need both slices. Both jobs pin `ARCHS` explicitly and assert the slices on _every_
shipping binary — the app, `ClipboardTextHelper`, `FileIndexHelper` and `Szcast Dictation`:
trusting `ARCHS_STANDARD` is what shipped a thin arm64 build to Intel users once already, and it
also keeps the Apple silicon download from silently gaining a slice it never needs. A thin helper
inside a universal app is the quiet form of the same bug: the app boots on Intel and only clipboard
OCR or dictation stops working.

Both jobs run in the `release` environment, which holds the signing and notary secrets and deploys
from `main` only ([signing.md](signing.md#2-the-release-secrets)). After `verify-signature.sh`,
`Scripts/package-release.sh` packs and signs the DMG, submits it once with `notarytool --wait`, and
staples the ticket to the DMG and to the app before zipping it, so the updater's zip is stapled too.
Any status but `Accepted` prints Apple's log and stops the run before anything is published.
`Scripts/sign-update.swift` then signs the zip, and fails the run if the built app trusts a different
update key. `Scripts/check-update-path.sh` runs just before notarizing, and fails the run unless the
last release on the channel would install this build ([signing.md](signing.md#update-trust)).

Channel builds override `SZCAST_BUNDLE_IDENTIFIER`, not the target-wide `PRODUCT_BUNDLE_IDENTIFIER`.
The Dictation helper derives its own identifier with a `.dictation` suffix; signature verification
checks that its bundle and signing identifiers agree and remain distinct from the main app.

### Release notes

`Scripts/release-notes.sh` composes the release body, and CI runs it just before `gh release create`.
It is safe to run by hand against any tag — it only reads:

```sh
CHANNEL=beta TAG=v0.9.13-beta.61 ./Scripts/release-notes.sh /tmp/body.md /tmp/discord.md
```

The changelog itself comes from GitHub's own release-notes API, which lists every merged PR with its
author and number — so contributors are credited without anyone maintaining a `CHANGELOG.md`, and
without Conventional Commits. **Nothing is ever committed to this repo**: the tag is created
server-side by `gh release create`, and no release, bot or version-bump commit exists.

Two details the script exists for:

- **The previous tag is picked per channel.** Beta and stable tags interleave on `main` — the same
  commit can carry both — so "the previous release" is only ever right within one channel. A stable
  release therefore spans every beta since the last stable.
- **The body is split by `<!-- szcast:install -->`.** Everything above it is the changelog;
  everything below is the install text, which only a download page needs. The website's changelog
  would cut at that marker. The site here is static (see `site/`), so nothing reads it yet. Full PR
  URLs are shortened to `#304`, which still autolinks on the web.

The Discord announcement carries the same changelog, truncated to fit Discord's component limit, and
pings `@everyone`.

### Homebrew

None. This fork publishes no cask and maintains no tap: releases are self-signed, so installing means
dragging `Szcast.app` out of the DMG. `release.yml` still carries an `Update Homebrew cask` step from
upstream; it exits early unless `HOMEBREW_TAP_TOKEN` is set, and that tap does not exist.
