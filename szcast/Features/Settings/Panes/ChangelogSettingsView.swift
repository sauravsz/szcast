import AppKit
import SwiftUI

// MARK: - Data Models

struct ChangelogCategory: Identifiable, Sendable {
    var id: String { name }
    let name: String
    let icon: String
    let items: [String]
}

struct ChangelogRelease: Identifiable, Sendable {
    let id: String
    let version: String
    let date: String
    let isLatest: Bool
    let summary: String
    let categories: [ChangelogCategory]

    var gitHubURL: URL? {
        URL(string: "https://github.com/sauravsz/szcast/releases/tag/v\(version)")
    }

    var formattedMarkdown: String {
        var text = "## szcast \(version) (\(date))\n\n\(summary)\n\n"
        for category in categories {
            text += "### \(category.name)\n"
            for item in category.items {
                text += "• \(item)\n"
            }
            text += "\n"
        }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

// MARK: - Changelog Catalog

enum ChangelogData {
    static let releases: [ChangelogRelease] = [
        ChangelogRelease(
            id: "1.1.2",
            version: "1.1.2",
            date: "November 16, 2026",
            isLatest: true,
            summary: "Responsive modifier key toggle detection (eliminated Fn key drop and Push-to-Talk speech onset clipping), universal Launcher shortcut dismissal across all active modes, full Ollama removal in favor of direct local llama-server, and DisplayTweaks sleep resilience.",
            categories: [
                ChangelogCategory(
                    name: "HotKey & Dictation Responsiveness",
                    icon: "keyboard",
                    items: [
                        "Expanded modifier single-tap threshold from 250ms to 650ms so deliberate human Fn/Globe taps are never dropped as abandoned holds.",
                        "Reduced Push-to-Talk activation delay from 250ms to 40ms for uncontended hold keys, preventing speech onset clipping and audio dropouts.",
                        "Resolved Launcher toggle shortcut (Option + Space) to dismiss szcast immediately when visible from any screen (Clipboard, AI, Calculator, etc.)."
                    ]
                ),
                ChangelogCategory(
                    name: "Dictation Offline Architecture",
                    icon: "mic.fill",
                    items: [
                        "Completely decoupled transcription polish from Ollama (localhost:11434), running directly through dedicated local llama-server on port 51143.",
                        "Pointed primary S1-mini GGUF download directly to GitHub Release assets with direct Hugging Face fallback.",
                        "Polishing returns raw transcripts in 0ms if the local inference daemon is stopped, eliminating network hang and timeout freezes."
                    ]
                ),
                ChangelogCategory(
                    name: "Hardware Display Tweaks & System Health",
                    icon: "sun.max",
                    items: [
                        "Added automatic wake and display reconfiguration observers to re-apply custom gamma curves on screen resume or monitor reconnect.",
                        "Eliminated hardcoded local path references in favor of clean internal Gamma Control profile defaults.",
                        "Resolved Swift concurrency data race warnings in KeePassXC CLI execution and cleaned Mach port invalidation in Clean Keyboard."
                    ]
                )
            ]
        ),
        ChangelogRelease(
            id: "1.1.1",
            version: "1.1.1",
            date: "November 16, 2026",
            isLatest: false,
            summary: "Native Gamma Control 3-point inspector with exact Black/Middle/White calibration, restored Settings window navigation title, unified 20pt form margin alignment, and official dark vector brand icons.",
            categories: [
                ChangelogCategory(
                    name: "Settings Navigation & Titlebar",
                    icon: "macwindow",
                    items: [
                        "Restored visible pane titles (AI, Display Tweaks, Clean Keyboard, Notes) beside the < | > navigation buttons across all settings tabs.",
                        "Eliminated manual platter offset overrides in favor of native AppKit and SwiftUI toolbar title layout with solid dark chrome.",
                        "Aligned content margins across Dictation Insights, Changelog, and settings pickers to 20pt native form insets."
                    ]
                ),
                ChangelogCategory(
                    name: "Hardware Display Tweaks & Gamma Control",
                    icon: "sun.max",
                    items: [
                        "Rebuilt Display Tweaks with a native 3-point inspector matching Gamma Control profiles: [ Black | Middle | White ].",
                        "Exact luminance and per-channel RGB controls: 0.05 Black Point, 1.00 Gray Balance, and 0.89 White Point Luminance.",
                        "Direct import and bidirectional hardware LUT synchronization with Gamma Control .gammaset files.",
                        "Added 5-box checkerboard calibration targets, 256-step grayscale ramp, and RGB spectrum gradient strips."
                    ]
                ),
                ChangelogCategory(
                    name: "Brand & Visual Polish",
                    icon: "sparkles",
                    items: [
                        "Integrated official dark vector squircle OpenAI and ChatGPT icon artwork.",
                        "Replaced white-background screenshots with transparent alpha assets across documentation and web surfaces."
                    ]
                )
            ]
        ),
        ChangelogRelease(
            id: "1.1.0",
            version: "1.1.0",
            date: "November 16, 2026",
            isLatest: false,
            summary: "Wispr Flow-style Dictation Insights Dashboard, 21.5pt toolbar navigation gap, Display Tweaks Gamma Control reference preset, zero-lag persistent local S1-mini & Parakeet models, and 840x600 window constraints.",
            categories: [
                ChangelogCategory(
                    name: "Dictation Insights Dashboard",
                    icon: "chart.bar.xaxis",
                    items: [
                        "Real-time speech analytics dashboard driven 100% by local dictation metrics (DictationHistoryStore).",
                        "Words Per Minute (WPM) circular arc gauge with percentile ranking (Top 0.1% tier).",
                        "AI normalization metrics: fixes made by S1-mini, words corrected, and domain dictionary overrides.",
                        "Cumulative words dictated counter with complete book equivalents (100k words per book) and desktop usage indicator.",
                        "Desktop application breakdown with untruncated app names (AI Prompts, Work Messages, Personal Messages, Documents, Emails, Other Tasks).",
                        "Interactive 16-week speech cadence streak calendar with historical month navigation and current streak counter."
                    ]
                ),
                ChangelogCategory(
                    name: "Settings Navigation & Layout",
                    icon: "macwindow",
                    items: [
                        "Enforced exact 21.5pt spacing between sidebar divider and < | > navigation buttons via AppKit NSToolbarPlatterView frame tracking.",
                        "Enforced 840x600 minimum window layout constraints preventing narrow sliver clipping on resize.",
                        "Opaque settings titlebar and navigation headers eliminating background transparency bleed-through."
                    ]
                ),
                ChangelogCategory(
                    name: "Hardware Display Tweaks",
                    icon: "sun.max",
                    items: [
                        "Integrated Gamma Control reference hardware profile (0.05 Black Point Luminance, 0.89 White Point Luminance).",
                        "Direct hardware LUT transfer curve scaling via CGSetDisplayTransferByTable, ensuring Blacks and Whites sliders directly control deep shadow floors and peak glare without banding."
                    ]
                ),
                ChangelogCategory(
                    name: "Zero-Latency Dictation Daemons",
                    icon: "bolt.fill",
                    items: [
                        "Local S1-mini normalization engine stays hot in Metal GPU memory (~460 MB RAM) across app launches.",
                        "Pre-warmed offline Parakeet v3 ASR engine eliminating first-dictation cold start delays entirely."
                    ]
                )
            ]
        ),
        ChangelogRelease(
            id: "1.0.9-hotfix",
            version: "1.0.9-hotfix",
            date: "November 15, 2026",
            isLatest: false,
            summary: "Dedicated hotfix eliminating titlebar transparency bleed-through, duplicate embossed ghost shadows, and process execution pipe deadlocks.",
            categories: [
                ChangelogCategory(
                    name: "Window UI & Chrome Polish",
                    icon: "macwindow",
                    items: [
                        "Solid native macOS window background opacity applied to titlebar and detail headers.",
                        "AppKit title visibility hidden to eliminate duplicate embossed ghost text behind SwiftUI navigation title.",
                        "Automatic split view persistence preventing accidental sidebar collapse."
                    ]
                ),
                ChangelogCategory(
                    name: "Productivity Suites & Icon Standardization",
                    icon: "square.grid.2x2",
                    items: [
                        "Standardized Ente Auth, KeePassXC, DuckDuckGo Email, Finder Actions, Display Tweaks, and Clean Keyboard into native grouped cards.",
                        "Vibrant Raycast-style squircle icons and custom snippet favicons.",
                        "Concurrent pipe draining for KeePassXC and Finder actions to prevent process deadlocks."
                    ]
                )
            ]
        ),
        ChangelogRelease(
            id: "1.0.8",
            version: "1.0.8",
            date: "November 15, 2026",
            isLatest: false,
            summary: "URL tracking stripper, screen OCR & QR code scanner, developer transformers, meeting countdown HUD, and live intelligence cards.",
            categories: [
                ChangelogCategory(
                    name: "URL Sanitizer & Privacy",
                    icon: "link.badge.plus",
                    items: [
                        "Pure offline tracking parameter stripper (utm_*, fbclid, gclid, si, twclid, msclkid, tag, ref).",
                        "Recursive redirect unwrap across Google (/url?q=), Slack, and Microsoft SafeLinks.",
                        "Root search evaluation (clean <url>, sanitize <url>) and ⇧⌘C context menu action."
                    ]
                ),
                ChangelogCategory(
                    name: "Screen OCR & Vision Scanner",
                    icon: "text.viewfinder",
                    items: [
                        "Direct-to-memory screen marquee capture (⌥⇧2 global shortcut) via Apple Vision framework.",
                        "Instant text extraction and QR code detection straight to clipboard with non-blocking HUD."
                    ]
                ),
                ChangelogCategory(
                    name: "Developer Tools & Live Intelligence",
                    icon: "wrench.and.screwdriver",
                    items: [
                        "Cryptographic hashing (sha256, sha512, md5), string encoders (base64, urlencode), and JWT inspector.",
                        "Menu bar meeting countdown HUD with 1-click join for Zoom, Google Meet, Teams, and Telemost.",
                        "Keyless Open-Meteo weather card, MapKit transit route estimator, and FlightRadar24 flight status."
                    ]
                )
            ]
        ),
        ChangelogRelease(
            id: "1.0.7",
            version: "1.0.7",
            date: "November 13, 2026",
            isLatest: false,
            summary: "Atomic single-shot paste pipeline after S1-mini cleanup, quiet floating glass pill, and streamlined document safety.",
            categories: [
                ChangelogCategory(
                    name: "Dictation Architecture",
                    icon: "waveform",
                    items: [
                        "Inhibited document chunk injection during recording; live speech preview is displayed strictly within the floating pill HUD.",
                        "Single-shot atomic paste via ⌘V after local S1-mini normalization and post-polish canonicalization finish.",
                        "Deprecated legacy typewriter and streaming modes to prevent document tampering."
                    ]
                )
            ]
        ),
        ChangelogRelease(
            id: "1.0.6",
            version: "1.0.6",
            date: "November 12, 2026",
            isLatest: false,
            summary: "Built-in security and everyday productivity tools: Ente Auth 2FA, KeePassXC, Finder Actions, DuckDuckGo Email, and Clean Keyboard.",
            categories: [
                ChangelogCategory(
                    name: "Built-In Productivity Suites",
                    icon: "lock.shield",
                    items: [
                        "Ente Auth 2FA (Hyper + T): instant TOTP codes with live countdown and auto-discovery from ente_auth.txt.",
                        "KeePassXC Password Vault: instant credential lookups with window resumption and dedicated shortcuts (⌘C, ⌘T, ⌘B, ⌘U).",
                        "Finder File Actions (Hyper + M): move or copy selected Finder files to pinned or recent destinations.",
                        "DuckDuckGo Email (Hyper + D): generate private @duck.com forwarding addresses on demand.",
                        "Clean Keyboard Mode: low-level keystroke blocking via CGEventTap with floating countdown HUD."
                    ]
                )
            ]
        ),
        ChangelogRelease(
            id: "1.0.5",
            version: "1.0.5",
            date: "November 12, 2026",
            isLatest: false,
            summary: "Dynamic font scaling, rich inline Markdown images in Notes, instant alias space triggers, and snippet tags/folders.",
            categories: [
                ChangelogCategory(
                    name: "Typography & Snippets",
                    icon: "textformat",
                    items: [
                        "Global dynamic font scaling (12pt-22pt) across launcher rows, details, and AI chat.",
                        "Instant alias execution: typing an alias followed by Space immediately expands and selects the command.",
                        "Inline rendering for Markdown images in Notes via TextKit 2 NSTextAttachment with caret reveal.",
                        "Snippet default action configuration (Paste, Copy, Copy & Paste), duplication (⌘D), and YAML folder grouping."
                    ]
                )
            ]
        ),
        ChangelogRelease(
            id: "1.0.4",
            version: "1.0.4",
            date: "November 11, 2026",
            isLatest: false,
            summary: "Audio and video file transcription directly from the menu bar, plus Bengali and Hindi phonetic romanization.",
            categories: [
                ChangelogCategory(
                    name: "Speech & Romanization",
                    icon: "mic.fill",
                    items: [
                        "Media file transcription via local Neural Engine or cloud Groq models with instant clipboard copy.",
                        "Phonetic Bengali & Hindi romanization (Banglish & Hinglish) via local S1-mini LLM and 0ms Avro rules."
                    ]
                )
            ]
        ),
        ChangelogRelease(
            id: "1.0.3",
            version: "1.0.3",
            date: "November 10, 2026",
            isLatest: false,
            summary: "Liquid Glass macOS UI with continuous transparency slider and one-key display mirroring.",
            categories: [
                ChangelogCategory(
                    name: "Liquid Glass Design",
                    icon: "sparkles",
                    items: [
                        "Translucent vibrancy and refraction across launcher and settings with 0-100% transparency slider.",
                        "One-key hardware display mirroring toggle."
                    ]
                )
            ]
        ),
        ChangelogRelease(
            id: "1.0.2",
            version: "1.0.2",
            date: "November 10, 2026",
            isLatest: false,
            summary: "EnviousWispr advanced dictation suite integration with embedded llama-server and domain vocabulary packs.",
            categories: [
                ChangelogCategory(
                    name: "Advanced Dictation",
                    icon: "waveform.badge.plus",
                    items: [
                        "Offline S1-mini speech normalization via embedded llama-server with 280ms inference.",
                        "5 domain vocabulary packs: Tech, Medical, Legal, Brands, Names (1,537 phonetic aliases).",
                        "Automatic audio ducking for Apple Music and Spotify while recording."
                    ]
                )
            ]
        ),
        ChangelogRelease(
            id: "1.0.1",
            version: "1.0.1",
            date: "November 9, 2026",
            isLatest: false,
            summary: "Live web search with inline citations in AI chat, Pomodoro focus timer with sensory audio cues, and quicklink favicons.",
            categories: [
                ChangelogCategory(
                    name: "AI Search & Focus",
                    icon: "globe",
                    items: [
                        "Multi-provider web search (Tavily, Exa, Jina) with numbered citations in AI chat.",
                        "Focus timer with menu bar countdown item, sound cues, and full-screen confetti celebration.",
                        "High-resolution quicklink favicon fetching and disk caching."
                    ]
                )
            ]
        ),
        ChangelogRelease(
            id: "1.0.0",
            version: "1.0.0",
            date: "November 8, 2026",
            isLatest: false,
            summary: "Initial standalone release of szcast: keyboard-first native macOS productivity launcher.",
            categories: [
                ChangelogCategory(
                    name: "Core Foundation",
                    icon: "terminal",
                    items: [
                        "Keyboard-driven search across applications, system settings, files, and custom shell commands.",
                        "Embedded JavaScriptCore runtime for native Raycast extension compatibility.",
                        "Local SQLite FTS5 clipboard history with text/image filtering and quick paste.",
                        "Quick Look previews (⌘Y) and multi-display window grid snapping."
                    ]
                )
            ]
        )
    ]
}

// MARK: - View

struct ChangelogSettingsView: View {
    @State private var searchQuery = ""
    @State private var selectedFilter = "All"
    @State private var copiedNotice: String?

    private let filterOptions = ["All", "v1.1", "v1.0"]

    private var filteredReleases: [ChangelogRelease] {
        ChangelogData.releases.filter { release in
            // Filter by prefix
            if selectedFilter == "v1.1" && !release.version.hasPrefix("1.1") {
                return false
            }
            if selectedFilter == "v1.0" && !release.version.hasPrefix("1.0") {
                return false
            }

            // Search query filter
            let q = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            guard !q.isEmpty else { return true }

            if release.version.lowercased().contains(q) { return true }
            if release.summary.lowercased().contains(q) { return true }
            for cat in release.categories {
                if cat.name.lowercased().contains(q) { return true }
                for item in cat.items {
                    if item.lowercased().contains(q) { return true }
                }
            }
            return false
        }
    }

    var body: some View {
        ScrollView(.vertical, showsIndicators: true) {
            VStack(alignment: .leading, spacing: Theme.Spacing.xl) {
                headerView
                searchAndFilterBar

                if filteredReleases.isEmpty {
                    emptyStateView
                } else {
                    LazyVStack(alignment: .leading, spacing: Theme.Spacing.xl) {
                        ForEach(filteredReleases) { release in
                            releaseCard(for: release)
                        }
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .settingsScrollTarget(.changelog)
    }

    // MARK: - Header

    private var headerView: some View {
        HStack(alignment: .center, spacing: Theme.Spacing.md) {
            ZStack {
                RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                    .fill(Theme.Colors.brand.opacity(0.16))
                    .frame(width: 44, height: 44)
                Image(systemName: "clock.arrow.circlepath")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(Theme.Colors.brand)
            }

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: Theme.Spacing.sm) {
                    Text("Changelog")
                        .font(.system(size: 22, weight: .bold))
                    Text("v1.1.1")
                        .font(.caption.monospacedDigit().weight(.semibold))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(Theme.Colors.cardFill))
                        .overlay(Capsule().strokeBorder(Theme.Colors.cardStroke, lineWidth: 1))
                }
                Text("Release notes, new features, and complete version history.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if let notice = copiedNotice {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(Color.green)
                    Text(notice)
                        .font(.caption.weight(.medium))
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Capsule().fill(Color(nsColor: .controlBackgroundColor)))
                .overlay(Capsule().strokeBorder(Color.green.opacity(0.3), lineWidth: 1))
                .transition(.opacity.combined(with: .scale(scale: 0.95)))
            }
        }
    }

    // MARK: - Search & Filter

    private var searchAndFilterBar: some View {
        HStack(spacing: Theme.Spacing.md) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.secondary)
                TextField("Search release notes and features…", text: $searchQuery)
                    .textFieldStyle(.plain)
                    .font(.body)
                if !searchQuery.isEmpty {
                    Button {
                        searchQuery = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 13))
                            .foregroundStyle(.tertiary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(Color(nsColor: .controlBackgroundColor).opacity(0.7))
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(Color.primary.opacity(0.08), lineWidth: 1)
            )

            Picker("", selection: $selectedFilter) {
                ForEach(filterOptions, id: \.self) { opt in
                    Text(opt).tag(opt)
                }
            }
            .pickerStyle(.segmented)
            .frame(width: 160)
            .labelsHidden()
        }
    }

    // MARK: - Release Card

    private func releaseCard(for release: ChangelogRelease) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            // Card Top Row
            HStack(alignment: .center, spacing: Theme.Spacing.md) {
                HStack(spacing: 8) {
                    Text("v\(release.version)")
                        .font(.system(size: 16, weight: .bold, design: .monospaced))
                    if release.isLatest {
                        Text("CURRENT")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(Color.green)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(Color.green.opacity(0.16)))
                            .overlay(Capsule().strokeBorder(Color.green.opacity(0.3), lineWidth: 1))
                    }
                    Text(release.date)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                HStack(spacing: 6) {
                    Button {
                        copyReleaseNotes(release)
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "doc.on.doc")
                                .font(.system(size: 11))
                            Text("Copy Notes")
                                .font(.caption.weight(.medium))
                        }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)

                    if let url = release.gitHubURL {
                        Button {
                            NSWorkspace.shared.open(url)
                        } label: {
                            HStack(spacing: 4) {
                                Text("GitHub")
                                    .font(.caption.weight(.medium))
                                Image(systemName: "arrow.up.right")
                                    .font(.system(size: 9, weight: .semibold))
                            }
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                }
            }

            // Summary Callout
            Text(release.summary)
                .font(.callout)
                .foregroundStyle(.primary)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(nsColor: .controlBackgroundColor).opacity(0.5))
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))

            // Categories
            VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                ForEach(release.categories) { category in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 6) {
                            Image(systemName: category.icon)
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(Theme.Colors.brand)
                            Text(category.name)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.primary)
                        }

                        VStack(alignment: .leading, spacing: 5) {
                            ForEach(category.items, id: \.self) { item in
                                HStack(alignment: .top, spacing: 8) {
                                    Text("•")
                                        .font(.subheadline.weight(.bold))
                                        .foregroundStyle(.secondary)
                                    Text(item)
                                        .font(.callout)
                                        .foregroundStyle(.secondary)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                            }
                        }
                        .padding(.leading, 6)
                    }
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.85))
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        )
    }

    // MARK: - Empty State

    private var emptyStateView: some View {
        VStack(spacing: Theme.Spacing.md) {
            Image(systemName: "text.magnifyingglass")
                .font(.system(size: 36))
                .foregroundStyle(.tertiary)
            Text("No release notes found")
                .font(.headline)
            Text("No releases matching \"\(searchQuery)\". Try searching for features like dictation, gamma, OCR, or URL.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 48)
    }

    // MARK: - Actions

    private func copyReleaseNotes(_ release: ChangelogRelease) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(release.formattedMarkdown, forType: .string)
        withAnimation {
            copiedNotice = "Copied v\(release.version) notes"
        }
        Task {
            try? await Task.sleep(for: .seconds(2))
            withAnimation {
                copiedNotice = nil
            }
        }
    }
}
