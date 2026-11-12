<h1 align="center">
  <a href="https://szcast.vercel.app"><img src="docs/images/icon.png" alt="szcast app icon" width="128" height="128"></a><br>
  szcast
</h1>

<p align="center">
  A native, keyboard-first macOS launcher for everyday productivity.
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

szcast is a native, keyboard-driven productivity launcher for macOS built in pure Swift. It features a command palette, file and menu search, clipboard history, snippets with folder tags, window tiling, rich-media notes, Pomodoro focus cycles, and full Raycast extension execution. Built natively with SwiftUI and AppKit: zero dependencies, zero Electron, zero tracking.

## Installation

Download the DMG from [Releases](https://github.com/sauravsz/szcast/releases/latest), open it, and move **szcast** to `/Applications`.

```bash
# macOS Sequoia / Apple Silicon
xattr -cr /Applications/szcast.app
open /Applications/szcast.app
```

## Features

### Advanced Offline Dictation
- **Local Speech Recognition**: Multi-root model discovery supporting Nvidia Parakeet Ultra with real-time Apple Neural Engine and Metal GPU execution.
- **Embedded S1-mini Normalization**: Bundled `llama-server` running `s1-mini-1.0.gguf` on loopback with Metal offload (`-ngl 99`, `-t 4`), sub-300ms inference, idle memory unloading, and Jinja thinking bypass.
- **Vocabulary Packs & Custom Dictionary**: Preloaded domain dictionaries (Tech, Medical, Legal, Brands, Names) with phonetic alias matching and post-polish canonicalization.
- **Dictation Hotkey Presets**: Instant triggers for `Fn key`, `⌥Space`, `⌃Space`, or custom keybinds.
- **Audio Intelligence**: Automatic background audio ducking (Spotify and Apple Music), spoken emoji/punctuation expansion, filler word scrubbing, and compact live audio level meters.

### Launcher & Navigation
- **Dynamic Typography Scaling**: Real-time font slider (12pt to 22pt) across row labels, accessory details, and AI chat.
- **Instant Alias Triggers**: Type any alias followed by Space to expand and run commands immediately.
- **Quicklink Favicons**: Auto-fetches and caches web favicons via Google, DuckDuckGo, and origin `/favicon.ico`.
- **Raycast Store Compatibility**: Direct install and updates for community Raycast extensions with full package CDN trust.

### Productivity Tools
- **Live AI Search**: Native chat with Tavily, Exa, and Jina search providers featuring interactive inline Markdown citation badges.
- **Focus Timer**: Full Pomodoro cycles (Work, Short Break, Long Break) with menu bar countdown and non-blocking audio cues.
- **Rich Media Notes**: TextKit 2 image attachments with inline paste, drag-and-drop, and cursor-revealed Markdown.
- **Window Management**: Grid snapping, multi-monitor movement, and persistent layout presets.

## Architecture

szcast is engineered natively on macOS technologies:
- **Frameworks**: SwiftUI, AppKit, TextKit 2, Accelerate (vDSP), Metal, CoreML, CryptoKit, JavaScriptCore.
- **Storage**: SQLite FTS5 for local search indexing, Keychain for API credentials.
- **Audio & ML**: AVFoundation capture pipelines, embedded ARM64 llama-server runtime, Parakeet CoreML recognition.

## Acknowledgements

- **[Tinycast](https://github.com/abue-ammar/tinycast)** by Abue Ammar: The native macOS launcher foundation upon which szcast is built.
- **[EnviousWispr](https://github.com/saurabhav88/EnviousWispr)** by saurabhav88: Dictation architecture inspiration, domain vocabulary packs, audio ducking, and speech normalization workflows rebuilt natively in szcast.
- **[Raycast](https://raycast.com)**: The extension API and community extension ecosystem supported by szcast.

Third-party licenses and notices are documented in [NOTICE.md](NOTICE.md).

## License

szcast is licensed under the [GNU AGPL v3](LICENSE). Forked from Tinycast by Abue Ammar. Copyright © 2026 Saurav. Third-party notices are documented in [NOTICE.md](NOTICE.md).
