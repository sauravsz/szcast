<h1 align="center">
  <a href="https://szcast.vercel.app"><img src="docs/images/icon.png" alt="szcast app icon" width="128" height="128"></a><br>
  szcast
</h1>

<p align="center">
  A native macOS launcher for everyday productivity.
</p>

<p align="center">
  <a href="https://szcast.vercel.app"><strong>Website</strong></a> ·
  <a href="https://github.com/sauravsz/szcast/releases/latest"><strong>Download</strong></a> ·
  <a href="docs/"><strong>Docs</strong></a> ·
  <a href="https://github.com/sauravsz/szcast/issues"><strong>Issues</strong></a>
</p>

<p align="center">
  <a href="https://github.com/sauravsz/szcast/releases/latest"><picture><source media="(prefers-color-scheme: dark)" srcset="https://shieldcn.dev/github/release/sauravsz/szcast.svg?variant=ghost&amp;font=geist-mono&amp;mode=dark&amp;label=RELEASE&amp;logo=lu:Tag&amp;valueColor=60A5FA" /><img alt="Latest release" src="https://shieldcn.dev/github/release/sauravsz/szcast.svg?variant=ghost&amp;font=geist-mono&amp;mode=light&amp;label=RELEASE&amp;logo=lu:Tag&amp;valueColor=2563EB" /></picture></a>
  <picture><source media="(prefers-color-scheme: dark)" srcset="https://shieldcn.dev/badge/MACOS-26%2B.svg?variant=ghost&amp;font=geist-mono&amp;mode=dark&amp;logo=apple" /><img alt="macOS 26 or later" src="https://shieldcn.dev/badge/MACOS-26%2B.svg?variant=ghost&amp;font=geist-mono&amp;mode=light&amp;logo=apple" /></picture>
  <picture><source media="(prefers-color-scheme: dark)" srcset="https://shieldcn.dev/badge/SWIFT-6.svg?variant=ghost&amp;font=geist-mono&amp;mode=dark&amp;logo=swift&amp;valueColor=FB923C" /><img alt="Swift 6" src="https://shieldcn.dev/badge/SWIFT-6.svg?variant=ghost&amp;font=geist-mono&amp;mode=light&amp;logo=swift&amp;valueColor=EA580C" /></picture>
  <a href="LICENSE"><picture><source media="(prefers-color-scheme: dark)" srcset="https://shieldcn.dev/badge/LICENSE-AGPL--3.0.svg?variant=ghost&amp;font=geist-mono&amp;mode=dark&amp;logo=lu:Scale" /><img alt="License: AGPL-3.0" src="https://shieldcn.dev/badge/LICENSE-AGPL--3.0.svg?variant=ghost&amp;font=geist-mono&amp;mode=light&amp;logo=lu:Scale" /></picture></a>
</p>

<p align="center">
  <img src="docs/screenshot.jpg" alt="szcast command palette">
</p>

szcast is a keyboard-first launcher for macOS: a command palette, file and menu search, clipboard
history, snippets, window management, notes, dictation, and a calculator. Built with SwiftUI and
AppKit — no dependencies, no Electron, no telemetry. It runs Raycast extensions, too.

[Explore all features →](docs/features/)

## Launcher touches in this build

Three changes to the palette, on top of upstream:

- **Space opens file search.** Type a space at the start of root search and the file search screen
  opens, Alfred-style, with the rest of the line already in its field. Escape walks back to the
  launcher with a clean field. Needs File Search enabled; it ignores the *Show in launcher* toggle,
  because the space is the explicit intent.
- **⌘1…⌘0 activates the Nth visible row.** Hold ⌘ and the first ten rows swap their kind label for
  the digit that activates them. On a blank query the digits launch pinned favourites by position
  instead. Rows past the tenth carry no chord.
- **File rows carry an icon.** A document or folder glyph in place of the word.

## Defaults in this build

Every feature switch starts **on**. A fresh install also arrives with:

- **Hyper key = Caps Lock**, with **Include Shift** and **Secure Input compatibility** enabled, so
  Hyper is ⌃⌥⇧⌘.

| Chord | Action |
| --- | --- |
| Hyper + **S** | Search Snippets |
| Hyper + **J** | Window: left half |
| Hyper + **L** | Window: right half |
| Hyper + **I** | Window: maximise |
| Hyper + **K** | Window: reasonable size |

Bindings are seeded once, as ordinary bindings — clear one and it stays cleared.

## Install

Download the DMG from [Releases](https://github.com/sauravsz/szcast/releases/latest), open it, and
drag **szcast** into `/Applications`.

The build is **self-signed, not notarized**: right-click → **Open** on first launch and macOS will
not ask again. macOS 26 or newer, Apple silicon. There is no Homebrew cask.

## Build from source

Requirements: macOS 26 or newer and Xcode 27 (Swift 6, macOS 26 SDK).

```sh
git clone https://github.com/sauravsz/szcast.git
cd szcast
open szcast.xcodeproj    # scheme: szcast, then ⌘R
```

Or from the terminal:

```sh
xcodebuild -project szcast.xcodeproj -scheme szcast -configuration Release \
  -derivedDataPath build/DerivedData build
```

The Debug configuration builds **szcast Dev** (`com.sauravsz.szcast.dev`), so it runs side by side
with a release install. Release builds are `com.sauravsz.szcast`.

### Local DMG

```sh
./Scripts/build-dmg.sh          # → build/szcast-<version>.dmg
```

The script signs with the **szcast Self-Signed** identity, so macOS keeps your Accessibility grant
across rebuilds. Create that identity once — [docs/signing.md](docs/signing.md) §1. Without it, every
rebuild resets your privacy permissions.

### Tests

```sh
./Scripts/run-tests.sh          # 114 self-contained harnesses
```

Each harness compiles the shipped sources it guards, so it needs Xcode, not just Command Line Tools.
See [docs/testing.md](docs/testing.md).

## What to know before you rely on it

- **The site is static.** `site/` is plain HTML, deployed to
  [szcast.vercel.app](https://szcast.vercel.app) on every push to `main`. No build step.
- **Self-update has a key but no feed.** The build carries the release verification key, so a signed
  update is checked against a key this project owns — but no update feed is published, so nothing
  installs over itself. [docs/features/updates.md](docs/features/updates.md).
- **Exchange rates come from `tinycast.dev`**, the upstream project's server, not one this repo
  controls. If it goes away, conversions stop updating and the last cached snapshot is served until
  it ages out. [docs/features/calculator.md](docs/features/calculator.md).
- **CI cannot cut a release yet.** The Release workflow needs a Developer ID certificate and
  notarization secrets that are not configured; `v1.0.0` was built and signed locally instead.
  [docs/signing.md](docs/signing.md) §2.

## Contributing

Feature requests and fixes are welcome in [this repo's issues](https://github.com/sauravsz/szcast/issues).

## License

szcast is a fork of [Tinycast](https://github.com/abue-ammar/tinycast) by Abue Ammar, and is
licensed under the [GNU AGPL v3](LICENSE). Original copyright © 2026 Abue Ammar; third-party
material is recorded in [NOTICE.md](NOTICE.md). No affiliation with or endorsement by the
upstream author is implied.
