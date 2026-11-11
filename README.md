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

szcast is a keyboard-first launcher for macOS: a command palette, file and menu search, clipboard history, snippets with tag/folder grouping, window management, notes with rich inline images, dictation, a calculator, a Pomodoro focus timer, and AI chat with live web search citations. Built with SwiftUI and AppKit — no dependencies, no Electron, no telemetry. It runs Raycast extensions, too.

[Explore all features →](docs/features/)

## Install

Download the DMG from [Releases](https://github.com/sauravsz/szcast/releases/latest), open it, and drag **szcast** into `/Applications`. Right-click → **Open** on first launch: the build is self-signed rather than notarized, so macOS asks once. macOS 26 or newer, Apple silicon.

## Differences from Tinycast

szcast builds on Tinycast with new features, visual customizations, and sensible defaults configured out of the box:

- **Dynamic Font Scaling**: Global typography slider in *Settings › General › Appearance* that dynamically scales launcher row titles, subtitles, accessory labels, details pane, and AI chat text from 12pt to 22pt.
- **`<alias><Space>` Command Trigger**: Typing an alias followed by Space in the root palette instantly expands and selects the command without pressing Return.
- **Focus Timer & Sensory Suite**: Native Pomodoro timer (`.work`, `.shortBreak`, `.longBreak`), menu bar countdown display, non-blocking audio cues, and full-screen celebration effects.
- **Native AI Web Search with Citations**: Live web search integration for OpenAI-compatible and custom endpoints using Tavily, Exa, or Jina (BYOK) with interactive inline Markdown citation badges.
- **Rich Notes with Inline Images**: TextKit 2 image attachments with clipboard image paste, drag-and-drop, and dynamic Markdown reveal when the cursor rests on the line.
- **Enhanced Snippets Management**: Folder and tag organization via YAML frontmatter, horizontal filter chips, snippet duplication (`⌘D`), and configurable default actions (Paste, Copy, or Copy & Paste).
- **Curated Defaults and Quicklinks**: Fallback search seeded with Brave Search, ChatGPT Web Search, and Brave Ask; Hyper key (⌃⌥⇧⌘) pre-armed out of the box; Space quick-jump to file search; and ⌘1…⌘0 row activation shortcuts.

## What to know before you rely on it

- **Self-update has a key but no feed.** The build carries the release verification key, so a signed update is checked against a key this project owns — but no feed is published, so nothing installs over itself. [docs/features/updates.md](docs/features/updates.md).
- **Exchange rates come from `tinycast.dev`**, the upstream project's server, not one this repo controls. If it goes away, conversions stop updating and the last cached snapshot is served until it ages out. [docs/features/calculator.md](docs/features/calculator.md).
- **Installed extensions are trusted with your whole account.** Extension JavaScript can read and write any file you can, fetch any URL, and spawn `/bin/sh`. The only prompt is one "Enable extensions?" switch. See [docs/SECURITY-AUDIT.md](docs/SECURITY-AUDIT.md) — finding H-1.

## Contributing

szcast is built natively with Swift 6, SwiftUI, AppKit, TextKit 2, JavaScriptCore (for native Raycast extension execution), CryptoKit, SQLite, NSSound, and CoreAnimation.

Feature requests, bug reports, and contributions are welcome in [this repo's issues](https://github.com/sauravsz/szcast/issues).

## License

szcast is a fork of [Tinycast](https://github.com/abue-ammar/tinycast) by Abue Ammar, and is licensed under the [GNU AGPL v3](LICENSE). Original copyright © 2026 Abue Ammar; third-party material is recorded in [NOTICE.md](NOTICE.md). No affiliation with or endorsement by the upstream author is implied.
