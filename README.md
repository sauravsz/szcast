<h1 align="center">
  <a href="https://szcast.vercel.app"><img src="docs/images/icon.png" alt="szcast app icon" width="128" height="128"></a><br>
  szcast
</h1>

<p align="center">
  A native, keyboard-first macOS productivity launcher and offline dictation engine built in pure Swift.
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
  <img src="docs/screenshot.png" alt="szcast command palette">
</p>

## Overview

szcast is a lightweight, keyboard-driven launcher and local AI dictation system for macOS. It combines instant search, local speech-to-text, system telemetry, and Raycast extension compatibility into a single native binary. Built in pure Swift with zero Electron overhead and zero telemetry.

## Quick Install

Download the latest `.dmg` from [Releases](https://github.com/sauravsz/szcast/releases/latest), mount it, and move **szcast** to `/Applications`.

```bash
xattr -cr /Applications/szcast.app
open /Applications/szcast.app
```

## Features

### Fast Native Launcher
- **Instant Search**: Search applications, preference panes, files, and custom shell commands with fuzzy ranking.
- **Scope Filters**: Switch contexts instantly with category chips (`All`, `Apps`, `Commands`, `Quicklinks`, `Snippets`, `Files`, `Actions`).
- **File Previews**: Arrow through file search results with instant native Quick Look previews (`⌘Y`).
- **Clipboard History**: SQLite FTS5-indexed history with code syntax highlighting, line numbers, and interactive color swatches.
- **Quicklinks & Snippets**: Parameterized URLs with cached favicons, deep snippet content body search with live row excerpt previews, and instant dynamic text expansions.
- **Window Management**: Half, quarter, and multi-display layout management without external window daemons.

### Raycast Extension Runtime
- **Native Extension Compatibility**: Run Raycast store extensions directly inside an embedded JavaScriptCore runtime.
- **Zero-Config Import**: Import `.rayconfig` exports to migrate quicklinks, snippets, and preferences in one step.
- **In-App Hotkeys & Aliases**: Assign dedicated shortcuts and custom keyword aliases to any extension command.

### Offline Speech Dictation
- **Local Speech Recognition**: Transcribe speech locally using Core ML-accelerated Parakeet v3 or Qwen3-ASR models.
- **GPU Grammar Polish**: Pre-warmed local S1-mini model cleans up filler words, punctuation, and grammar before pasting.
- **Floating Waveform Pill**: Minimal glass capsule showing real-time transcription status, haptic cues, and single-shot insertion.
- **Dictation Telemetry**: Track WPM, speech cadence tiers, streak calendar, and application usage locally.

### System Telemetry & Hardware Monitors
- **Resource Dashboard**: Real-time tracking of CPU load, RAM memory pressure, Disk space, Battery health, and Network throughput.
- **Rolling Sparklines**: Live 30-sample quadratic Bezier sparklines for immediate telemetry visualization.
- **Modular Menu Bar Items**: Togglable menu bar indicators with customizable polling intervals (1s to 10s).

### Emoji & Symbols Picker
- **Natural Language Search**: Find emojis and Unicode symbols by name, category, or semantic intent.
- **Custom Keywords (`⌘E`)**: Attach custom search keywords to any symbol for immediate recall.
- **Inline Autocomplete (`:`)**: Trigger instant inline emoji suggestions directly inside Notes, AI Chat, and Snippet editors.
- **Tone & Grid Modifiers**: Configurable 6–10 column grid with zoom shortcuts (`⌘-`/`⌘+`/`⌘0`) and quick skin tone selectors (`⌥⌘V`/`⌥⌘C`).

### Interactive Text Transformer
- **Instant Text Conversions**: Convert selected text across 15+ formats (camelCase, snake_case, kebab-case, PascalCase, Slugify, Base64, URL encode/decode, SHA-256, MD5, UUID).
- **Side-by-Side Diff Inspector (`⌘D`)**: Dual-column diff view with real-time word, line, and character count comparisons.

### Modular Power Tools
- **Ente Auth 2FA (`Hyper + T`)**: Instant TOTP generation with auto-discovery from `ente_auth.txt`.
- **KeePassXC Integration**: Rapid password vault lookup via `keepassxc-cli` (`⌘C` password, `⌘T` TOTP, `⌘B` username).
- **DuckDuckGo Email (`Hyper + D`)**: Generate and copy private `@duck.com` forwarding addresses on demand.
- **Display Tweaks & Gamma Control**: Hardware LUT calibration (`CGSetDisplayTransferByTable`) with 3-point luminance sliders and one-click contrast presets.
- **Clean Keyboard Mode**: Suppress keystrokes via `CGEventTap` for safe physical keyboard cleaning.
- **In-App Changelog & Version Sync**: Native release notes, feature highlights, and version history dynamically tracking the running app build.

## Architecture

- **Language**: Swift 6 (Strict Concurrency enabled)
- **UI Framework**: Native AppKit + SwiftUI
- **Local Storage**: SQLite FTS5 for clipboard and file indexing; local JSON configuration
- **Privacy**: No telemetry, no external analytics, no user tracking

## Building from Source

Requires macOS 26+ and Xcode 27+.

```bash
git clone https://github.com/sauravsz/szcast.git
cd szcast
xcodebuild -project Szcast.xcodeproj -scheme Szcast -configuration Debug build
./Scripts/run-tests.sh
```

## Acknowledgements

- **[Tinycast](https://github.com/abue-ammar/tinycast)** by Abue Ammar: The native macOS launcher foundation upon which szcast is built.
- **[EnviousWispr](https://github.com/saurabhav88/EnviousWispr)** by saurabhav88: Dictation pipeline architecture, domain vocabulary packs, and audio ducking.
- **[Raycast](https://raycast.com)**: Extension runtime model and API specifications.
- **[Stats](https://github.com/exelban/stats)** by Serhiy Mytrovtsiy (exelban): macOS system monitor telemetry architecture.
- **[FreeDisplay](https://github.com/huberdf/FreeDisplay)** & **[gamma-control](https://github.com/Qiueyed/gamma-control)**: Display management and gamma transfer LUT mathematics.

Third-party licenses are documented in [NOTICE.md](NOTICE.md).

## License

szcast is licensed under the [GNU AGPL v3](LICENSE).
