<h1 align="center">
  <a href="https://github.com/sauravsz/szcast"><img src="docs/images/icon.png" alt="Szcast app icon" width="128" height="128"></a><br>
  Szcast
</h1>

<p align="center">
  A native macOS launcher for everyday productivity. Lightweight and open source.
</p>

<p align="center">
  <a href="https://szcast.vercel.app"><strong>Website</strong></a> ·
  <a href="#install"><strong>Install</strong></a> ·
  <a href="docs/"><strong>Docs</strong></a> ·
  <a href="https://github.com/sauravsz/szcast/issues"><strong>Support</strong></a>
</p>

<p align="center">
  <a href="https://github.com/sauravsz/szcast/releases/latest"><picture><source media="(prefers-color-scheme: dark)" srcset="https://shieldcn.dev/github/release/sauravsz/szcast.svg?variant=ghost&amp;font=geist-mono&amp;mode=dark&amp;label=RELEASE&amp;logo=lu:Tag&amp;valueColor=60A5FA" /><img alt="Latest release" src="https://shieldcn.dev/github/release/sauravsz/szcast.svg?variant=ghost&amp;font=geist-mono&amp;mode=light&amp;label=RELEASE&amp;logo=lu:Tag&amp;valueColor=2563EB" /></picture></a>
  <a href="https://github.com/sauravsz/szcast/releases"><picture><source media="(prefers-color-scheme: dark)" srcset="https://shieldcn.dev/github/downloads/sauravsz/szcast.svg?variant=ghost&amp;font=geist-mono&amp;mode=dark&amp;label=DOWNLOADS&amp;logo=lu:CloudDownload&amp;valueColor=A78BFA" /><img alt="Total downloads" src="https://shieldcn.dev/github/downloads/sauravsz/szcast.svg?variant=ghost&amp;font=geist-mono&amp;mode=light&amp;label=DOWNLOADS&amp;logo=lu:CloudDownload&amp;valueColor=7C3AED" /></picture></a>
  <a href="https://github.com/sauravsz/szcast/actions/workflows/release.yml"><picture><source media="(prefers-color-scheme: dark)" srcset="https://shieldcn.dev/github/ci/sauravsz/szcast.svg?variant=ghost&amp;font=geist-mono&amp;mode=dark&amp;workflow=release.yml&amp;label=BUILD&amp;logo=lu:Hammer&amp;valueColor=4ADE80" /><img alt="Release build status" src="https://shieldcn.dev/github/ci/sauravsz/szcast.svg?variant=ghost&amp;font=geist-mono&amp;mode=light&amp;workflow=release.yml&amp;label=BUILD&amp;logo=lu:Hammer&amp;valueColor=16A34A" /></picture></a>
  <br>
  <picture><source media="(prefers-color-scheme: dark)" srcset="https://shieldcn.dev/badge/MACOS-26%2B.svg?variant=ghost&amp;font=geist-mono&amp;mode=dark&amp;logo=apple" /><img alt="macOS 26 or later" src="https://shieldcn.dev/badge/MACOS-26%2B.svg?variant=ghost&amp;font=geist-mono&amp;mode=light&amp;logo=apple" /></picture>
  <picture><source media="(prefers-color-scheme: dark)" srcset="https://shieldcn.dev/badge/SWIFT-6.svg?variant=ghost&amp;font=geist-mono&amp;mode=dark&amp;logo=swift&amp;valueColor=FB923C" /><img alt="Swift 6" src="https://shieldcn.dev/badge/SWIFT-6.svg?variant=ghost&amp;font=geist-mono&amp;mode=light&amp;logo=swift&amp;valueColor=EA580C" /></picture>
  <a href="LICENSE"><picture><source media="(prefers-color-scheme: dark)" srcset="https://shieldcn.dev/badge/LICENSE-AGPL--3.0.svg?variant=ghost&amp;font=geist-mono&amp;mode=dark&amp;logo=lu:Scale" /><img alt="License: AGPL-3.0" src="https://shieldcn.dev/badge/LICENSE-AGPL--3.0.svg?variant=ghost&amp;font=geist-mono&amp;mode=light&amp;logo=lu:Scale" /></picture></a>
</p>

<p align="center">
  <img src="docs/screenshot.jpg" alt="Szcast command palette">
</p>

Built with SwiftUI and AppKit. No dependencies, no Electron, no telemetry. It runs your Raycast
extensions, too.

[Explore all features →](docs/features/)

Szcast is a personal fork of [Tinycast](https://github.com/abue-ammar/tinycast) by Abue Ammar, under the same GNU AGPL v3 licence (see LICENSE). Original copyright © 2026 Abue Ammar; see NOTICE.md for third-party notices. No affiliation or endorsement implied.

## Install

On an Apple silicon Mac with macOS 26 or newer:

```sh
brew install --cask szcast
brew install --cask szcast@beta
```

- **DMG:** notarized, download from [Releases](https://github.com/sauravsz/szcast/releases). Drag `Szcast.app` to `/Applications`.
- **Intel Mac:** install from [Homebrew tap](https://github.com/sauravsz/homebrew-szcast).

## Support

Szcast is free and stays free. If it earns a place on your Mac, consider supporting its
development. Thank you!

<p align="center">
  <a href="https://github.com/sauravsz/szcast"><picture><source media="(prefers-color-scheme: dark)" srcset="https://shieldcn.dev/badge/SUPPORT-CARD.svg?variant=outline&amp;size=lg&amp;font=geist-mono&amp;mode=dark&amp;logo=lu:CircleDollarSign&amp;logoColor=A78BFA&amp;valueColor=A78BFA" /><img alt="Support by card payment" src="https://shieldcn.dev/badge/SUPPORT-CARD.svg?variant=outline&amp;size=lg&amp;font=geist-mono&amp;mode=light&amp;logo=lu:CircleDollarSign&amp;logoColor=7C3AED&amp;valueColor=7C3AED" /></picture></a>
  <a href="https://github.com/sauravsz/szcast"><picture><source media="(prefers-color-scheme: dark)" srcset="https://shieldcn.dev/badge/SUPPORT-CRYPTO.svg?variant=outline&amp;size=lg&amp;font=geist-mono&amp;mode=dark&amp;logo=lu:Bitcoin&amp;logoColor=FBBF24&amp;valueColor=FBBF24" /><img alt="Support with crypto" src="https://shieldcn.dev/badge/SUPPORT-CRYPTO.svg?variant=outline&amp;size=lg&amp;font=geist-mono&amp;mode=light&amp;logo=lu:Bitcoin&amp;logoColor=B45309&amp;valueColor=B45309" /></picture></a>
</p>

## License

Szcast is licensed under the [AGPL-3.0 license](LICENSE).
