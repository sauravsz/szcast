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
history, snippets with tag/folder grouping, window management, notes with rich inline images, dictation,
a calculator, a Pomodoro focus timer, and AI chat with live web search citations. Built with SwiftUI and
AppKit — no dependencies, no Electron, no telemetry. It runs Raycast extensions, too.

[Explore all features →](docs/features/)

## Install

Download the DMG from [Releases](https://github.com/sauravsz/szcast/releases/latest), open it, and
drag **szcast** into `/Applications`. Right-click → **Open** on first launch: the build is
self-signed rather than notarized, so macOS asks once. macOS 26 or newer, Apple silicon.

## What this build changes

Everything is on out of the box, with sensory feedback, typography scaling, and palette shortcuts.

| | |
| --- | --- |
| **`<alias><Space>`** | In root search, typing a command alias followed by Space immediately expands or selects the command without requiring Return. |
| **Space** | In root search, a leading space opens the file search screen with the rest of the line already in its field. Escape returns to the launcher with a clean field. Needs File Search enabled; it ignores *Show in launcher*, because the space is the explicit intent. |
| **⌘1…⌘0** | Activates the Nth visible row. Hold ⌘ and the first ten rows swap their kind label for their digit; on a blank query the digits launch pinned favourites by position instead. |
| **File rows** | Carry a document or folder glyph rather than the word. |

### Capabilities in szcast

- **Focus Timer**: Pomodoro focus intervals, menu bar timer item, non-blocking audio cues, and celebration effects.
- **Live AI Web Search**: Native client-side search orchestration with Tavily, Exa, and Jina (BYOK) providing live web context and Markdown citation badges.
- **Customizable Font Scaling**: Adjustable typography slider in *Settings › General › Appearance* dynamically scaling launcher rows, detail panes, and AI chat text from 12pt to 22pt.
- **Rich Inline Images in Notes**: TextKit 2 image attachments in note editing with clipboard paste, drag-and-drop, and automatic raw Markdown reveal when the cursor rests on the line.
- **Snippets Suite**: Tag and folder organization with frontmatter, horizontal filter chips, snippet duplication (`⌘D`), and default actions (Paste, Copy, or Copy & Paste).
- **Curated Fallback Search**: Out-of-the-box fallback search integration with Brave Search, ChatGPT Web Search, and Brave Ask.

**Every feature switch defaults on**, and a fresh install arrives with Hyper armed — Caps Lock, with
*Include Shift* and *Secure input compatibility* on, so Hyper is ⌃⌥⇧⌘:

| Chord | Action |
| --- | --- |
| Hyper + **S** | Search Snippets |
| Hyper + **J** | Window: left half |
| Hyper + **L** | Window: right half |
| Hyper + **I** | Window: maximise |
| Hyper + **K** | Window: reasonable size |

Chords are seeded once as ordinary bindings, so clearing one in Settings keeps it cleared.

## Build from source

Requirements: macOS 26 or newer and Xcode 27 (Swift 6, macOS 26 SDK).

```sh
git clone https://github.com/sauravsz/szcast.git
cd szcast
open szcast.xcodeproj    # scheme: Szcast, then ⌘R
```

Or from the terminal:

```sh
xcodebuild -project szcast.xcodeproj -scheme Szcast -configuration Release \
  -derivedDataPath build/DerivedData build
```

Debug builds install as **szcast Dev** (`com.sauravsz.szcast.dev`), side by side with a release;
release builds are `com.sauravsz.szcast`. The Xcode scheme and the `Szcast Self-Signed` signing
identity keep their capitalisation — renaming either drops your Accessibility grant on every rebuild.

### Local DMG

```sh
./Scripts/build-dmg.sh          # → build/szcast-<version>.dmg
```

It signs with **Szcast Self-Signed** so macOS keeps your Accessibility grant across rebuilds. Create
that identity once — [docs/signing.md](docs/signing.md) §1. Without it every rebuild resets your
privacy permissions.

### Tests

```sh
./Scripts/run-tests.sh          # 117 self-contained harnesses
```

Each harness compiles the shipped sources it guards, so it needs Xcode, not just Command Line Tools.
See [docs/testing.md](docs/testing.md).

## What to know before you rely on it

- **Self-update has a key but no feed.** The build carries the release verification key, so a signed
  update is checked against a key this project owns — but no feed is published, so nothing installs
  over itself. [docs/features/updates.md](docs/features/updates.md).
- **Exchange rates come from `tinycast.dev`**, the upstream project's server, not one this repo
  controls. If it goes away, conversions stop updating and the last cached snapshot is served until
  it ages out. [docs/features/calculator.md](docs/features/calculator.md).
- **Installed extensions are trusted with your whole account.** Extension JavaScript can read and
  write any file you can, fetch any URL, and spawn `/bin/sh`. The only prompt is one "Enable
  extensions?" switch. See [docs/SECURITY-AUDIT.md](docs/SECURITY-AUDIT.md) — finding H-1.

## Contributing

Feature requests and fixes are welcome in [this repo's issues](https://github.com/sauravsz/szcast/issues).

## License

szcast is a fork of [Tinycast](https://github.com/abue-ammar/tinycast) by Abue Ammar, and is
licensed under the [GNU AGPL v3](LICENSE). Original copyright © 2026 Abue Ammar; third-party
material is recorded in [NOTICE.md](NOTICE.md). No affiliation with or endorsement by the upstream
author is implied.
