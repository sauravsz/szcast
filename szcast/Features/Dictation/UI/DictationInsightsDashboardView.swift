import AppKit
import AVFoundation
import SwiftUI

// MARK: - Airbnb × szcast Adaptive Dashboard Design System

/// Pairs Airbnb's generous whitespace, soft geometry, single Rausch brand voltage, and editorial
/// rating showcase with szcast's adaptive light/dark chrome.
private enum DashboardPalette {
    /// Single brand voltage: Airbnb Rausch (#FF385C in light, luminous coral-rose in dark).
    static let rausch = Theme.Colors.adaptive(
        dark: NSColor(srgbRed: 1.0, green: 0.30, blue: 0.43, alpha: 1.0),
        light: NSColor(srgbRed: 1.0, green: 0.22, blue: 0.36, alpha: 1.0)
    )
    static let rauschPressed = Theme.Colors.adaptive(
        dark: NSColor(srgbRed: 0.90, green: 0.14, blue: 0.29, alpha: 1.0),
        light: NSColor(srgbRed: 0.878, green: 0.043, blue: 0.255, alpha: 1.0)
    )
    static let rauschSoft = Theme.Colors.adaptive(
        dark: NSColor(srgbRed: 1.0, green: 0.30, blue: 0.43, alpha: 0.15),
        light: NSColor(srgbRed: 1.0, green: 0.22, blue: 0.36, alpha: 0.10)
    )
    static let rauschGlowStroke = Theme.Colors.adaptive(
        dark: NSColor(srgbRed: 1.0, green: 0.30, blue: 0.43, alpha: 0.42),
        light: NSColor(srgbRed: 1.0, green: 0.22, blue: 0.36, alpha: 0.32)
    )
    static let ink = Theme.Colors.adaptive(
        dark: NSColor(srgbRed: 0.96, green: 0.96, blue: 0.97, alpha: 1.0),
        light: NSColor(srgbRed: 0.133, green: 0.133, blue: 0.133, alpha: 1.0) // #222222
    )
    static let body = Theme.Colors.adaptive(
        dark: NSColor(srgbRed: 0.82, green: 0.82, blue: 0.85, alpha: 1.0),
        light: NSColor(srgbRed: 0.247, green: 0.247, blue: 0.247, alpha: 1.0) // #3F3F3F
    )
    static let muted = Theme.Colors.adaptive(
        dark: NSColor(srgbRed: 0.58, green: 0.58, blue: 0.62, alpha: 1.0),
        light: NSColor(srgbRed: 0.416, green: 0.416, blue: 0.416, alpha: 1.0) // #6A6A6A
    )
    static let surfaceCard = Theme.Colors.adaptive(
        dark: NSColor(srgbRed: 0.145, green: 0.145, blue: 0.165, alpha: 1.0),
        light: NSColor(srgbRed: 1.0, green: 1.0, blue: 1.0, alpha: 1.0) // #FFFFFF
    )
    static let surfaceSoft = Theme.Colors.adaptive(
        dark: NSColor(srgbRed: 0.185, green: 0.185, blue: 0.210, alpha: 1.0),
        light: NSColor(srgbRed: 0.969, green: 0.969, blue: 0.969, alpha: 1.0) // #F7F7F7
    )
    static let surfaceStrong = Theme.Colors.adaptive(
        dark: NSColor(srgbRed: 0.23, green: 0.23, blue: 0.26, alpha: 1.0),
        light: NSColor(srgbRed: 0.949, green: 0.949, blue: 0.949, alpha: 1.0) // #F2F2F2
    )
    static let hairline = Theme.Colors.adaptive(
        dark: NSColor(srgbRed: 1.0, green: 1.0, blue: 1.0, alpha: 0.09),
        light: NSColor(srgbRed: 0.867, green: 0.867, blue: 0.867, alpha: 1.0) // #DDDDDD
    )
    static let hairlineHover = Theme.Colors.adaptive(
        dark: NSColor(srgbRed: 1.0, green: 1.0, blue: 1.0, alpha: 0.22),
        light: NSColor(srgbRed: 0.757, green: 0.757, blue: 0.757, alpha: 1.0) // #C1C1C1
    )
    static let hoverShadow = Theme.Colors.adaptive(
        dark: NSColor(srgbRed: 0, green: 0, blue: 0, alpha: 0.36),
        light: NSColor(srgbRed: 0, green: 0, blue: 0, alpha: 0.10)
    )
    static let selectedSegmentBg = Theme.Colors.adaptive(
        dark: NSColor(srgbRed: 0.95, green: 0.95, blue: 0.97, alpha: 1.0),
        light: NSColor(srgbRed: 0.133, green: 0.133, blue: 0.133, alpha: 1.0)
    )
    static let selectedSegmentInk = Theme.Colors.adaptive(
        dark: NSColor(srgbRed: 0.10, green: 0.10, blue: 0.12, alpha: 1.0),
        light: NSColor(srgbRed: 1.0, green: 1.0, blue: 1.0, alpha: 1.0)
    )
    static let activeFlame = Theme.Colors.adaptive(
        dark: NSColor(srgbRed: 1.0, green: 0.62, blue: 0.26, alpha: 1.0),
        light: NSColor(srgbRed: 0.88, green: 0.44, blue: 0.06, alpha: 1.0)
    )
    static let liveGreen = Theme.Colors.adaptive(
        dark: NSColor(srgbRed: 0.26, green: 0.84, blue: 0.50, alpha: 1.0),
        light: NSColor(srgbRed: 0.08, green: 0.64, blue: 0.32, alpha: 1.0)
    )
    static let rawAmber = Theme.Colors.adaptive(
        dark: NSColor(srgbRed: 1.0, green: 0.68, blue: 0.28, alpha: 1.0),
        light: NSColor(srgbRed: 0.78, green: 0.42, blue: 0.04, alpha: 1.0)
    )
}

private enum DashboardMetricsMotion {
    static let pop = Animation.spring(response: 0.24, dampingFraction: 0.78)
    static let gentle = Animation.easeOut(duration: 0.16)
}

@MainActor
private enum DashboardFormatters {
    static let decimal: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        return f
    }()

    static let relative: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .abbreviated
        return f
    }()

    static func number(_ value: Int) -> String {
        decimal.string(from: NSNumber(value: value)) ?? "\(value)"
    }

    static func duration(_ secs: TimeInterval) -> String {
        if secs < 60 { return String(format: "%.0fs", secs) }
        let mins = Int(secs / 60)
        let rem = Int(secs.truncatingRemainder(dividingBy: 60))
        return "\(mins)m \(rem)s"
    }

    static func relativeTime(from date: Date) -> String {
        relative.localizedString(for: date, relativeTo: Date())
    }
}

enum DashboardTimeWindow: String, CaseIterable, Identifiable {
    case all = "All"
    case fourteenDays = "14D"
    case sevenDays = "7D"

    var id: String { rawValue }

    var cadenceDays: Int {
        switch self {
        case .all: return 14
        case .fourteenDays: return 14
        case .sevenDays: return 7
        }
    }

    var filterDays: Int? {
        switch self {
        case .all: return nil
        case .fourteenDays: return 14
        case .sevenDays: return 7
        }
    }

    var cadenceSubtitle: String {
        switch self {
        case .all, .fourteenDays: return "Daily spoken words over the last 14 days"
        case .sevenDays: return "Daily spoken words over the last 7 days"
        }
    }
}

// MARK: - Main Dashboard View

/// Dictation Intelligence Dashboard uniting Airbnb's tactile editorial clarity with szcast's
/// adaptive desktop chrome, scoped leaf hover states, and precomputed metrics.
struct DictationInsightsDashboardView: View {
    @Environment(DictationCoordinator.self) private var coordinator
    @Environment(AppSettings.self) private var settings

    @State private var selectedWindow: DashboardTimeWindow = .all
    @State private var cachedMetrics: DictationIntelligenceMetrics = .empty
    @State private var copiedNotice = false
    @State private var showingClearConfirmation = false
    @State private var audioPlayer = DictationAudioPlayer()
    @State private var copyResetTask: Task<Void, Never>?

    private struct MetricsCacheKey: Equatable {
        let count: Int
        let firstID: UUID?
        let lastID: UUID?
        let firstTextLength: Int
        let window: DashboardTimeWindow
    }

    private var items: [DictationHistoryItem] {
        coordinator.historyStore.items
    }

    private var cacheKey: MetricsCacheKey {
        MetricsCacheKey(
            count: items.count,
            firstID: items.first?.id,
            lastID: items.last?.id,
            firstTextLength: items.first?.text.count ?? 0,
            window: selectedWindow
        )
    }

    private var engineSummary: String {
        let asrName: String
        switch settings.dictationTranscriptionProvider {
        case .local: asrName = settings.dictationModel.variantTitle
        case .cloud: asrName = settings.dictationCloudSpeechProvider.title
        }

        let polishName: String
        if settings.dictationS1Enabled {
            switch settings.dictationPolishProvider {
            case .localS1: polishName = "S1-mini"
            case .appleIntelligence: polishName = "Apple AI"
            case .groq: polishName = "Groq"
            }
        } else {
            polishName = "Raw STT"
        }

        return "\(asrName) · \(polishName)"
    }

    var body: some View {
        ScrollView(.vertical, showsIndicators: true) {
            VStack(alignment: .leading, spacing: 16) {
                headerBand

                // Row 1: Editorial Rating Hero + Craft + Volume Bento Row
                heroBentoRow

                // Row 2: Interactive Speech Cadence Bars
                SpeechCadenceSectionCard(
                    cadence: cachedMetrics.dailyCadence,
                    dailyAverage: cachedMetrics.dailyAverageWords,
                    currentStreak: cachedMetrics.currentStreak,
                    subtitle: selectedWindow.cadenceSubtitle
                )

                // Row 3: Workflow by App & Recent Captures
                bottomBentoRow
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 18)
            .frame(maxWidth: 1120, alignment: .topLeading)
            .frame(maxWidth: .infinity, alignment: .top)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onAppear { recomputeMetrics() }
        .onChange(of: cacheKey) { _, _ in recomputeMetrics() }
        .onDisappear {
            copyResetTask?.cancel()
            audioPlayer.stop()
        }
        .confirmationDialog(
            "Clear Dictation Analytics",
            isPresented: $showingClearConfirmation,
            titleVisibility: .visible
        ) {
            Button("Clear All History", role: .destructive) {
                coordinator.historyStore.clearAll()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will permanently clear all recorded dictation history and reset intelligence telemetry.")
        }
    }

    private func recomputeMetrics() {
        let computed = DictationIntelligenceMetrics.compute(from: items, window: selectedWindow)
        withAnimation(DashboardMetricsMotion.gentle) {
            cachedMetrics = computed
        }
    }

    // MARK: - Header & Pill Navigation Bar

    private var headerBand: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Dictation Intelligence")
                    .font(.system(size: 21, weight: .semibold))
                    .tracking(-0.4)
                    .foregroundStyle(DashboardPalette.ink)
                    .lineLimit(1)
                Text("Velocity, neural polish & desktop flow.")
                    .font(.system(size: 12))
                    .foregroundStyle(DashboardPalette.muted)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }

            Spacer(minLength: 8)

            // Airbnb Search-Bar-Pill inspired unified toolbar + Rausch orb CTA
            HStack(spacing: 5) {
                EngineStatusChip(
                    isEnabled: settings.dictationEnabled,
                    summary: engineSummary
                )

                hairlineDivider

                HStack(spacing: 2) {
                    ForEach(DashboardTimeWindow.allCases) { window in
                        TimeWindowPillButton(
                            title: window.rawValue,
                            isSelected: selectedWindow == window
                        ) {
                            selectedWindow = window
                        }
                    }
                }
                .padding(2)
                .background(DashboardPalette.surfaceSoft)
                .clipShape(Capsule())

                hairlineDivider

                RauschActionOrbButton(copiedNotice: copiedNotice) {
                    copyShareSummary()
                }
            }
            .padding(.horizontal, 7)
            .padding(.vertical, 5)
            .background(DashboardPalette.surfaceCard)
            .clipShape(Capsule())
            .overlay(Capsule().stroke(DashboardPalette.hairline, lineWidth: 1))
            .fixedSize(horizontal: true, vertical: false)

            CircleOverflowMenuButton {
                showingClearConfirmation = true
            }
        }
    }

    private var hairlineDivider: some View {
        Rectangle()
            .fill(DashboardPalette.hairline)
            .frame(width: 1, height: 18)
            .padding(.horizontal, 2)
    }

    private func copyShareSummary() {
        let m = cachedMetrics
        let summary = """
        # szcast Dictation Intelligence (\(selectedWindow.rawValue))
        - Pipeline: \(engineSummary)
        - Speed: \(m.wordsPerMinute > 0 ? "\(m.wordsPerMinute) WPM (\(m.speedMultiplier)x typing pace)" : "Awaiting data")
        - Time Saved: \(m.timeSavedFormatted) vs 45 WPM typing
        - Volume: \(DashboardFormatters.number(m.totalWords)) words across \(m.totalItems) sessions (\(DashboardFormatters.duration(m.totalDuration)) speech)
        - Neural Impact: \(m.fixesCount) normalizations (\(m.fillerWordsPurged) fillers purged, \(m.wordsCorrected) words polished)
        - Streak: \(m.currentStreak)d active (Best: \(m.longestStreak)d)
        """
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(summary, forType: .string)
        withAnimation(DashboardMetricsMotion.pop) { copiedNotice = true }
        copyResetTask?.cancel()
        copyResetTask = Task {
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            withAnimation(DashboardMetricsMotion.gentle) { copiedNotice = false }
        }
    }

    // MARK: - Row 1: Bento Hero Row

    private var heroBentoRow: some View {
        HStack(alignment: .top, spacing: 12) {
            VelocityHeroCard(metrics: cachedMetrics)
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            NeuralCraftCard(
                metrics: cachedMetrics,
                s1Enabled: settings.dictationS1Enabled,
                polishProvider: settings.dictationPolishProvider
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            VolumeMomentumCard(metrics: cachedMetrics)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    // MARK: - Row 3: Workflow & Recent Normalizations

    private var bottomBentoRow: some View {
        HStack(alignment: .top, spacing: 12) {
            DesktopWorkflowCard(entries: cachedMetrics.appUsage)
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            RecentTransformationsCard(
                items: cachedMetrics.recentTransformations,
                historyStore: coordinator.historyStore,
                audioPlayer: audioPlayer
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .fixedSize(horizontal: false, vertical: true)
    }
}

// MARK: - Interactive Leaf Chrome Components

/// Shared Airbnb card shell: flat baseline, 16pt radius, hairline border, and low-cost single-tier hover pop.
private struct DashboardInteractiveCard<Content: View>: View {
    var highlightBorderOnHover: Bool = false
    @ViewBuilder let content: () -> Content

    @State private var isHovered = false

    var body: some View {
        content()
            .padding(16)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(DashboardPalette.surfaceCard)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(
                        isHovered
                            ? (highlightBorderOnHover ? DashboardPalette.rauschGlowStroke : DashboardPalette.hairlineHover)
                            : DashboardPalette.hairline,
                        lineWidth: 1
                    )
            )
            .scaleEffect(isHovered ? 1.012 : 1.0)
            .offset(y: isHovered ? -2 : 0)
            .shadow(
                color: isHovered ? DashboardPalette.hoverShadow : .clear,
                radius: isHovered ? 10 : 0,
                x: 0,
                y: isHovered ? 5 : 0
            )
            .animation(DashboardMetricsMotion.pop, value: isHovered)
            .onHover { isHovered = $0 }
    }
}

private struct EngineStatusChip: View {
    let isEnabled: Bool
    let summary: String
    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(isEnabled ? DashboardPalette.liveGreen : DashboardPalette.muted)
                .frame(width: 7, height: 7)
            Text(summary)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(DashboardPalette.ink)
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 5)
        .background(isHovered ? DashboardPalette.surfaceSoft : .clear)
        .clipShape(Capsule())
        .animation(DashboardMetricsMotion.gentle, value: isHovered)
        .onHover { isHovered = $0 }
        .help(isEnabled ? "Active pipeline: \(summary)" : "Dictation is currently disabled")
    }
}

private struct TimeWindowPillButton: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .lineLimit(1)
                .fixedSize()
                .foregroundStyle(
                    isSelected
                        ? DashboardPalette.selectedSegmentInk
                        : (isHovered ? DashboardPalette.ink : DashboardPalette.muted)
                )
                .padding(.horizontal, 9)
                .padding(.vertical, 4)
                .background(
                    Capsule().fill(
                        isSelected
                            ? DashboardPalette.selectedSegmentBg
                            : (isHovered ? DashboardPalette.surfaceStrong : .clear)
                    )
                )
                .scaleEffect(isHovered && !isSelected ? 1.04 : 1.0)
        }
        .buttonStyle(.plain)
        .animation(DashboardMetricsMotion.pop, value: isHovered)
        .animation(DashboardMetricsMotion.gentle, value: isSelected)
        .onHover { isHovered = $0 }
    }
}

private struct RauschActionOrbButton: View {
    let copiedNotice: Bool
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: copiedNotice ? "checkmark" : "square.and.arrow.up")
                    .font(.system(size: 10.5, weight: .bold))
                Text(copiedNotice ? "Copied" : "Report")
                    .font(.system(size: 11, weight: .semibold))
                    .lineLimit(1)
                    .fixedSize()
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 11)
            .padding(.vertical, 6)
            .background(
                Capsule().fill(isHovered ? DashboardPalette.rauschPressed : DashboardPalette.rausch)
            )
            .scaleEffect(isHovered ? 1.04 : 1.0)
        }
        .buttonStyle(.plain)
        .animation(DashboardMetricsMotion.pop, value: isHovered)
        .onHover { isHovered = $0 }
        .help("Copy formatted Dictation Intelligence summary")
    }
}

private struct CircleOverflowMenuButton: View {
    let onReset: () -> Void
    @State private var isHovered = false

    var body: some View {
        Menu {
            Button(role: .destructive, action: onReset) {
                Label("Reset Dictation Analytics", systemImage: "trash")
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(isHovered ? DashboardPalette.ink : DashboardPalette.muted)
                .frame(width: 30, height: 30)
                .background(isHovered ? DashboardPalette.surfaceStrong : DashboardPalette.surfaceCard)
                .clipShape(Circle())
                .overlay(Circle().stroke(isHovered ? DashboardPalette.hairlineHover : DashboardPalette.hairline, lineWidth: 1))
                .scaleEffect(isHovered ? 1.05 : 1.0)
        }
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .animation(DashboardMetricsMotion.pop, value: isHovered)
        .onHover { isHovered = $0 }
        .help("Dashboard actions")
    }
}

/// Interactive Airbnb-style amenity row that lifts and highlights cleanly on pointer hover.
private struct HoverableStatRow<Trailing: View>: View {
    let icon: String
    let iconColor: Color
    let label: String
    var detail: String? = nil
    @ViewBuilder var trailing: () -> Trailing

    @State private var isHovered = false

    init(
        icon: String,
        iconColor: Color,
        label: String,
        detail: String? = nil,
        @ViewBuilder trailing: @escaping () -> Trailing = { EmptyView() }
    ) {
        self.icon = icon
        self.iconColor = iconColor
        self.label = label
        self.detail = detail
        self.trailing = trailing
    }

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(isHovered ? DashboardPalette.rausch : iconColor)
                .frame(width: 24, height: 24)
                .background(isHovered ? DashboardPalette.rauschSoft : DashboardPalette.surfaceSoft)
                .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))

            VStack(alignment: .leading, spacing: 1) {
                Text(label)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(DashboardPalette.ink)
                    .lineLimit(1)
                if let detail {
                    Text(detail)
                        .font(.system(size: 10.5))
                        .foregroundStyle(DashboardPalette.muted)
                }
            }

            Spacer(minLength: 6)

            trailing()
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(isHovered ? DashboardPalette.surfaceSoft : .clear)
        )
        .offset(x: isHovered ? 2 : 0)
        .animation(DashboardMetricsMotion.pop, value: isHovered)
        .onHover { isHovered = $0 }
    }
}

// MARK: - Hero Card 1: Velocity Rating Showcase

private struct VelocityHeroCard: View {
    let metrics: DictationIntelligenceMetrics
    @State private var isComparingHover = false

    private var wpmGain: Int {
        max(0, metrics.wordsPerMinute - 45)
    }

    var body: some View {
        DashboardInteractiveCard(highlightBorderOnHover: true) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .center, spacing: 6) {
                    Text("VOICE PACE")
                        .font(.system(size: 10, weight: .bold))
                        .tracking(0.5)
                        .foregroundStyle(DashboardPalette.muted)
                        .lineLimit(1)

                    Spacer(minLength: 4)

                    HStack(spacing: 4) {
                        Image(systemName: "bolt.fill")
                            .font(.system(size: 8.5, weight: .bold))
                            .foregroundStyle(DashboardPalette.rausch)
                        Text(metrics.wordsPerMinute > 0 ? "\(metrics.speedMultiplier)x" : "Ready")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(DashboardPalette.ink)
                            .lineLimit(1)
                            .fixedSize()
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(DashboardPalette.surfaceSoft)
                    .clipShape(Capsule())
                    .overlay(Capsule().stroke(DashboardPalette.hairline, lineWidth: 1))
                }

                // Airbnb Rating-Display centerpiece flanked by laurel ornaments
                HStack(alignment: .center, spacing: 5) {
                    Image(systemName: "laurel.leading")
                        .font(.system(size: 20, weight: .light))
                        .foregroundStyle(metrics.wordsPerMinute > 0 ? DashboardPalette.rausch.opacity(0.85) : DashboardPalette.muted.opacity(0.45))

                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text(metrics.wordsPerMinute > 0 ? "\(metrics.wordsPerMinute)" : "—")
                            .font(.system(size: 36, weight: .bold, design: .rounded))
                            .tracking(-1.0)
                            .monospacedDigit()
                            .contentTransition(.numericText())
                            .foregroundStyle(DashboardPalette.ink)

                        Text("WPM")
                            .font(.system(size: 10.5, weight: .semibold))
                            .foregroundStyle(DashboardPalette.muted)
                    }

                    Image(systemName: "laurel.trailing")
                        .font(.system(size: 20, weight: .light))
                        .foregroundStyle(metrics.wordsPerMinute > 0 ? DashboardPalette.rausch.opacity(0.85) : DashboardPalette.muted.opacity(0.45))
                }
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.vertical, 2)

                // Interactive speed comparison track
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("vs 45 WPM")
                            .font(.system(size: 10.5, weight: .medium))
                            .foregroundStyle(DashboardPalette.muted)
                            .lineLimit(1)
                        Spacer(minLength: 4)
                        Text(isComparingHover && wpmGain > 0 ? "+\(wpmGain) WPM" : "Saved ~\(metrics.timeSavedFormatted)")
                            .font(.system(size: 10.5, weight: .semibold, design: .rounded))
                            .foregroundStyle(isComparingHover ? DashboardPalette.rausch : DashboardPalette.ink)
                            .lineLimit(1)
                            .fixedSize()
                            .contentTransition(.numericText())
                    }

                    VStack(spacing: 4) {
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                Capsule().fill(DashboardPalette.surfaceSoft).frame(height: isComparingHover ? 6 : 5)
                                let ratio = CGFloat(min(metrics.wordsPerMinute, 240)) / 240.0
                                let width = metrics.wordsPerMinute > 0 ? max(8, geo.size.width * ratio) : 8
                                Capsule()
                                    .fill(DashboardPalette.rausch)
                                    .frame(width: width, height: isComparingHover ? 6 : 5)
                            }
                        }
                        .frame(height: 6)

                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                Capsule().fill(DashboardPalette.surfaceSoft).frame(height: 3.5)
                                Capsule()
                                    .fill(DashboardPalette.muted.opacity(0.45))
                                    .frame(width: max(8, geo.size.width * (45.0 / 240.0)), height: 3.5)
                            }
                        }
                        .frame(height: 4)
                    }
                }
                .padding(8)
                .background(isComparingHover ? DashboardPalette.surfaceSoft : .clear)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .animation(DashboardMetricsMotion.pop, value: isComparingHover)
                .onHover { isComparingHover = $0 }

                Spacer(minLength: 0)
            }
        }
    }
}

// MARK: - Hero Card 2: Neural Craft

private struct NeuralCraftCard: View {
    let metrics: DictationIntelligenceMetrics
    let s1Enabled: Bool
    let polishProvider: DictationPolishProvider

    private var daemonLabel: String {
        guard s1Enabled else { return "Raw" }
        switch polishProvider {
        case .localS1: return "S1-mini"
        case .appleIntelligence: return "Apple AI"
        case .groq: return "Groq"
        }
    }

    var body: some View {
        DashboardInteractiveCard {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top, spacing: 6) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(DashboardFormatters.number(metrics.fixesCount))
                            .font(.system(size: 28, weight: .semibold, design: .rounded))
                            .tracking(-0.5)
                            .monospacedDigit()
                            .contentTransition(.numericText())
                            .foregroundStyle(DashboardPalette.ink)
                        Text("NEURAL EDITS")
                            .font(.system(size: 10, weight: .bold))
                            .tracking(0.5)
                            .foregroundStyle(DashboardPalette.muted)
                            .lineLimit(1)
                    }

                    Spacer(minLength: 4)

                    HStack(spacing: 4) {
                        Circle()
                            .fill(s1Enabled ? DashboardPalette.liveGreen : DashboardPalette.rawAmber)
                            .frame(width: 6, height: 6)
                        Text(daemonLabel)
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(DashboardPalette.body)
                            .lineLimit(1)
                            .fixedSize()
                    }
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(DashboardPalette.surfaceSoft)
                    .clipShape(Capsule())
                }

                VStack(spacing: 3) {
                    HoverableStatRow(
                        icon: "waveform.badge.minus",
                        iconColor: DashboardPalette.body,
                        label: "Fillers purged"
                    ) {
                        Text(DashboardFormatters.number(metrics.fillerWordsPurged))
                            .font(.system(size: 11.5, weight: .semibold, design: .rounded))
                            .monospacedDigit()
                            .fixedSize()
                            .foregroundStyle(DashboardPalette.ink)
                    }

                    HoverableStatRow(
                        icon: "character.cursor.ibeam",
                        iconColor: DashboardPalette.body,
                        label: "Punctuation"
                    ) {
                        Text(DashboardFormatters.number(metrics.punctuationInserted))
                            .font(.system(size: 11.5, weight: .semibold, design: .rounded))
                            .monospacedDigit()
                            .fixedSize()
                            .foregroundStyle(DashboardPalette.ink)
                    }

                    HoverableStatRow(
                        icon: "sparkles",
                        iconColor: Theme.Colors.brand,
                        label: "Polished"
                    ) {
                        Text(DashboardFormatters.number(metrics.wordsCorrected))
                            .font(.system(size: 11.5, weight: .semibold, design: .rounded))
                            .monospacedDigit()
                            .fixedSize()
                            .foregroundStyle(DashboardPalette.ink)
                    }
                }
                .padding(.horizontal, -6)

                Spacer(minLength: 0)

                Text(s1Enabled ? "Local daemon ready" : "Deterministic fast-path")
                    .font(.system(size: 10))
                    .foregroundStyle(DashboardPalette.muted)
                    .lineLimit(1)
            }
        }
    }
}

// MARK: - Hero Card 3: Volume & Momentum

private struct VolumeMomentumCard: View {
    let metrics: DictationIntelligenceMetrics

    private var equivalentPagesText: String {
        guard metrics.totalWords > 0 else { return "Awaiting first capture" }
        let pages = max(1, Int(round(Double(metrics.totalWords) / 250.0)))
        return "~\(pages) page\(pages == 1 ? "" : "s") of prose"
    }

    var body: some View {
        DashboardInteractiveCard {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top, spacing: 6) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(DashboardFormatters.number(metrics.totalWords))
                            .font(.system(size: 28, weight: .semibold, design: .rounded))
                            .tracking(-0.5)
                            .monospacedDigit()
                            .contentTransition(.numericText())
                            .foregroundStyle(DashboardPalette.ink)
                        Text("TOTAL WORDS")
                            .font(.system(size: 10, weight: .bold))
                            .tracking(0.5)
                            .foregroundStyle(DashboardPalette.muted)
                            .lineLimit(1)
                    }

                    Spacer(minLength: 4)

                    HStack(spacing: 4) {
                        Image(systemName: "flame.fill")
                            .font(.system(size: 9))
                            .foregroundStyle(metrics.currentStreak > 0 ? DashboardPalette.activeFlame : DashboardPalette.muted)
                        Text("\(metrics.currentStreak)d")
                            .font(.system(size: 10, weight: .semibold, design: .rounded))
                            .foregroundStyle(metrics.currentStreak > 0 ? DashboardPalette.activeFlame : DashboardPalette.muted)
                            .lineLimit(1)
                            .fixedSize()
                    }
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(DashboardPalette.surfaceSoft)
                    .clipShape(Capsule())
                }

                VStack(spacing: 3) {
                    HoverableStatRow(
                        icon: "mic.fill",
                        iconColor: DashboardPalette.body,
                        label: "\(DashboardFormatters.duration(metrics.totalDuration))"
                    ) {
                        Text("\(metrics.totalItems) bursts")
                            .font(.system(size: 11, weight: .semibold))
                            .fixedSize()
                            .foregroundStyle(DashboardPalette.muted)
                    }

                    HoverableStatRow(
                        icon: "timer",
                        iconColor: DashboardPalette.body,
                        label: "Avg burst"
                    ) {
                        Text("\(metrics.averageSessionDuration)s")
                            .font(.system(size: 11.5, weight: .semibold, design: .rounded))
                            .fixedSize()
                            .foregroundStyle(DashboardPalette.ink)
                    }

                    HoverableStatRow(
                        icon: "flame.fill",
                        iconColor: metrics.currentStreak > 0 ? DashboardPalette.activeFlame : DashboardPalette.muted,
                        label: "Best streak"
                    ) {
                        Text("\(metrics.longestStreak)d")
                            .font(.system(size: 11.5, weight: .semibold, design: .rounded))
                            .fixedSize()
                            .foregroundStyle(metrics.currentStreak > 0 ? DashboardPalette.activeFlame : DashboardPalette.muted)
                    }
                }
                .padding(.horizontal, -6)

                Spacer(minLength: 0)

                Text(equivalentPagesText)
                    .font(.system(size: 10))
                    .foregroundStyle(DashboardPalette.muted)
                    .lineLimit(1)
            }
        }
    }
}

// MARK: - Row 2: Interactive Cadence Histogram

private struct SpeechCadenceSectionCard: View {
    let cadence: [DictationIntelligenceMetrics.DailyVelocityEntry]
    let dailyAverage: Int
    let currentStreak: Int
    let subtitle: String

    @State private var hoveredDayID: UUID?

    private var hoveredDay: DictationIntelligenceMetrics.DailyVelocityEntry? {
        guard let hoveredDayID else { return nil }
        return cadence.first { $0.id == hoveredDayID }
    }

    private var maxWords: Int {
        max(50, cadence.map(\.wordCount).max() ?? 50)
    }

    var body: some View {
        DashboardInteractiveCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .center, spacing: 12) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Speech Cadence & Momentum")
                            .font(.system(size: 15.5, weight: .semibold))
                            .foregroundStyle(DashboardPalette.ink)
                            .lineLimit(1)

                        if let day = hoveredDay {
                            HStack(spacing: 6) {
                                Circle()
                                    .fill(DashboardPalette.rausch)
                                    .frame(width: 6, height: 6)
                                Text("\(day.dateLabel) · \(DashboardFormatters.number(day.wordCount)) words across \(day.sessionCount) session\(day.sessionCount == 1 ? "" : "s")")
                                    .font(.system(size: 11.5, weight: .semibold))
                                    .foregroundStyle(DashboardPalette.ink)
                                    .lineLimit(1)
                            }
                            .transition(.opacity)
                        } else {
                            Text(subtitle)
                                .font(.system(size: 11.5))
                                .foregroundStyle(DashboardPalette.muted)
                                .lineLimit(1)
                                .transition(.opacity)
                        }
                    }
                    .animation(DashboardMetricsMotion.gentle, value: hoveredDayID)

                    Spacer(minLength: 12)

                    HStack(spacing: 8) {
                        CadenceBadgePill(
                            value: "\(DashboardFormatters.number(dailyAverage)) w/d",
                            label: "AVERAGE",
                            accent: DashboardPalette.ink
                        )
                        CadenceBadgePill(
                            value: "\(currentStreak) days",
                            label: "STREAK",
                            accent: currentStreak > 0 ? DashboardPalette.rausch : DashboardPalette.muted
                        )
                    }
                    .fixedSize(horizontal: true, vertical: false)
                }

                // Airy Airbnb bar stage with headroom above tallest bar for hover pill
                ZStack(alignment: .bottomLeading) {
                    let barMaxHeight: CGFloat = 62
                    let barSlotHeight: CGFloat = 84
                    let stageHeight: CGFloat = 102
                    let avgOffset = min(barMaxHeight - 4, max(4, CGFloat(dailyAverage) / CGFloat(maxWords) * barMaxHeight))

                    VStack(spacing: 0) {
                        Spacer()
                        HStack(spacing: 6) {
                            Text("AVG")
                                .font(.system(size: 8.5, weight: .bold))
                                .foregroundStyle(DashboardPalette.muted.opacity(0.8))
                            DashedHorizontalRule()
                                .stroke(DashboardPalette.hairline, style: StrokeStyle(lineWidth: 1, dash: [3, 4]))
                                .frame(height: 1)
                        }
                        .padding(.bottom, avgOffset + 18)
                    }
                    .frame(height: stageHeight)
                    .allowsHitTesting(false)

                    HStack(alignment: .bottom, spacing: cadence.count > 16 ? 5 : 8) {
                        ForEach(cadence) { day in
                            CadenceBarColumn(
                                day: day,
                                maxWords: maxWords,
                                maxBarHeight: barMaxHeight,
                                barSlotHeight: barSlotHeight,
                                cornerRadius: cadence.count > 16 ? 4 : 6,
                                isHovered: hoveredDayID == day.id,
                                anyBarHovered: hoveredDayID != nil,
                                onHoverChanged: { inside in
                                    hoveredDayID = inside ? day.id : (hoveredDayID == day.id ? nil : hoveredDayID)
                                }
                            )
                        }
                    }
                    .frame(height: stageHeight)
                }
            }
        }
    }
}

private struct CadenceBadgePill: View {
    let value: String
    let label: String
    let accent: Color

    var body: some View {
        VStack(alignment: .trailing, spacing: 1) {
            Text(value)
                .font(.system(size: 12.5, weight: .bold, design: .rounded))
                .monospacedDigit()
                .lineLimit(1)
                .fixedSize()
                .foregroundStyle(accent)
            Text(label)
                .font(.system(size: 8, weight: .bold))
                .tracking(0.5)
                .foregroundStyle(DashboardPalette.muted)
                .lineLimit(1)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 5)
        .background(DashboardPalette.surfaceSoft)
        .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
    }
}

private struct CadenceBarColumn: View {
    let day: DictationIntelligenceMetrics.DailyVelocityEntry
    let maxWords: Int
    let maxBarHeight: CGFloat
    let barSlotHeight: CGFloat
    let cornerRadius: CGFloat
    let isHovered: Bool
    let anyBarHovered: Bool
    let onHoverChanged: (Bool) -> Void

    private var barHeight: CGFloat {
        guard day.wordCount > 0 else { return 5 }
        return max(10, CGFloat(day.wordCount) / CGFloat(maxWords) * maxBarHeight)
    }

    private var barFill: Color {
        if isHovered { return DashboardPalette.rausch }
        if day.isToday { return DashboardPalette.rausch.opacity(0.92) }
        if day.wordCount > 0 { return DashboardPalette.rausch.opacity(0.46) }
        return DashboardPalette.hairline
    }

    var body: some View {
        VStack(spacing: 5) {
            ZStack(alignment: .bottom) {
                Color.clear.frame(height: barSlotHeight)

                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(barFill)
                    .frame(height: barHeight)
                    .scaleEffect(x: isHovered ? 1.12 : 1.0, y: isHovered ? 1.07 : 1.0, anchor: .bottom)
                    .opacity(anyBarHovered && !isHovered ? 0.55 : 1.0)
                    .overlay(alignment: .top) {
                        if isHovered {
                            Text(DashboardFormatters.number(day.wordCount))
                                .font(.system(size: 10, weight: .bold, design: .rounded))
                                .monospacedDigit()
                                .foregroundStyle(DashboardPalette.ink)
                                .padding(.horizontal, 7)
                                .padding(.vertical, 2.5)
                                .background(DashboardPalette.surfaceCard)
                                .clipShape(Capsule())
                                .overlay(Capsule().stroke(DashboardPalette.hairlineHover, lineWidth: 1))
                                .shadow(color: DashboardPalette.hoverShadow, radius: 4, y: 2)
                                .fixedSize()
                                .offset(y: -22)
                                .allowsHitTesting(false)
                        }
                    }
            }

            Text(day.dayLabel)
                .font(.system(size: 9.5, weight: (isHovered || day.isToday) ? .bold : .medium))
                .foregroundStyle(isHovered ? DashboardPalette.rausch : (day.isToday ? DashboardPalette.ink : DashboardPalette.muted))
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
        .animation(DashboardMetricsMotion.pop, value: isHovered)
        .onHover(perform: onHoverChanged)
    }
}

private struct DashedHorizontalRule: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.midY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
        return path
    }
}

// MARK: - Row 3 Left: Desktop Workflow

private struct DesktopWorkflowCard: View {
    let entries: [DictationIntelligenceMetrics.AppWorkflowEntry]

    var body: some View {
        DashboardInteractiveCard {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Text("Desktop Application Workflow")
                        .font(.system(size: 15.5, weight: .semibold))
                        .foregroundStyle(DashboardPalette.ink)
                    Spacer()
                    Text("\(entries.count) APPS")
                        .font(.system(size: 9.5, weight: .bold))
                        .tracking(0.5)
                        .foregroundStyle(DashboardPalette.muted)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(DashboardPalette.surfaceSoft)
                        .clipShape(Capsule())
                }

                if entries.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "macwindow")
                            .font(.system(size: 22))
                            .foregroundStyle(DashboardPalette.muted)
                        Text("No application telemetry yet.")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(DashboardPalette.body)
                        Text("Dictate inside Obsidian, iTerm2, Xcode, or Slack to build your desktop map.")
                            .font(.system(size: 11))
                            .foregroundStyle(DashboardPalette.muted)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 24)
                } else {
                    VStack(spacing: 6) {
                        ForEach(Array(entries.enumerated()), id: \.element.id) { index, entry in
                            WorkflowAppRow(entry: entry, isTopApp: index == 0)
                        }
                    }
                }

                Spacer(minLength: 0)
            }
        }
    }
}

private struct WorkflowAppRow: View {
    let entry: DictationIntelligenceMetrics.AppWorkflowEntry
    let isTopApp: Bool
    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 11) {
            DictationAppIconView(bundleID: entry.bundleID, fallbackName: entry.name)
                .frame(width: 24, height: 24)
                .scaleEffect(isHovered ? 1.08 : 1.0)

            VStack(alignment: .leading, spacing: 5) {
                HStack(alignment: .firstTextBaseline) {
                    Text(entry.name)
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundStyle(DashboardPalette.ink)
                        .lineLimit(1)

                    Spacer(minLength: 8)

                    HStack(spacing: 6) {
                        if isHovered {
                            Text("\(entry.sessionCount) session\(entry.sessionCount == 1 ? "" : "s")")
                                .font(.system(size: 10.5, weight: .medium))
                                .foregroundStyle(DashboardPalette.muted)
                                .transition(.opacity)
                        }
                        Text("\(DashboardFormatters.number(entry.wordCount)) w")
                            .font(.system(size: 11.5, weight: .bold, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(DashboardPalette.ink)
                        Text("\(entry.percent)%")
                            .font(.system(size: 10.5, weight: .semibold))
                            .foregroundStyle(isHovered || isTopApp ? DashboardPalette.rausch : DashboardPalette.muted)
                    }
                }

                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(DashboardPalette.hairline.opacity(0.6))
                            .frame(height: isHovered ? 6 : 4.5)
                        let barWidth = max(10, geo.size.width * CGFloat(entry.percent) / 100.0)
                        Capsule()
                            .fill(
                                (isTopApp || isHovered)
                                    ? DashboardPalette.rausch
                                    : DashboardPalette.muted.opacity(0.65)
                            )
                            .frame(width: barWidth, height: isHovered ? 6 : 4.5)
                    }
                }
                .frame(height: 6)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(isHovered ? DashboardPalette.surfaceSoft : .clear)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(isHovered ? DashboardPalette.hairline : .clear, lineWidth: 1)
        )
        .scaleEffect(isHovered ? 1.015 : 1.0)
        .animation(DashboardMetricsMotion.pop, value: isHovered)
        .onHover { isHovered = $0 }
    }
}

// MARK: - Row 3 Right: Recent Transformations Feed

private struct RecentTransformationsCard: View {
    let items: [DictationHistoryItem]
    let historyStore: DictationHistoryStore
    let audioPlayer: DictationAudioPlayer

    var body: some View {
        DashboardInteractiveCard {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Text("Recent Normalizations")
                        .font(.system(size: 15.5, weight: .semibold))
                        .foregroundStyle(DashboardPalette.ink)
                    Spacer()
                    Text("CLICK TO INSPECT")
                        .font(.system(size: 9.5, weight: .bold))
                        .tracking(0.5)
                        .foregroundStyle(DashboardPalette.muted)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(DashboardPalette.surfaceSoft)
                        .clipShape(Capsule())
                }

                if items.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "waveform.badge.magnifyingglass")
                            .font(.system(size: 22))
                            .foregroundStyle(DashboardPalette.muted)
                        Text("No recent captures yet.")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(DashboardPalette.body)
                        Text("Your raw voice transcripts and S1-mini polished prose will appear here.")
                            .font(.system(size: 11))
                            .foregroundStyle(DashboardPalette.muted)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 24)
                } else {
                    VStack(spacing: 8) {
                        ForEach(items) { item in
                            TransformationFeedRow(
                                item: item,
                                audioURL: historyStore.audioURL(for: item),
                                isPlayingAudio: audioPlayer.playingID == item.id,
                                onToggleAudio: { url in audioPlayer.toggle(id: item.id, url: url) }
                            )
                        }
                    }
                }

                Spacer(minLength: 0)
            }
        }
    }
}

private struct TransformationFeedRow: View {
    let item: DictationHistoryItem
    let audioURL: URL?
    let isPlayingAudio: Bool
    let onToggleAudio: (URL) -> Void

    @State private var isHovered = false
    @State private var isExpanded = false
    @State private var showingRaw = false
    @State private var copiedRow = false
    @State private var copyFeedbackTask: Task<Void, Never>?

    private var hasDiff: Bool {
        !item.rawText.isEmpty && item.rawText != item.text
    }

    private var displayText: String {
        (showingRaw && !item.rawText.isEmpty) ? item.rawText : item.text
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 7) {
                DictationAppIconView(bundleID: item.appBundleID, fallbackName: item.appName ?? "System")
                    .frame(width: 16, height: 16)

                Text(item.appName ?? "System")
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundStyle(DashboardPalette.ink)
                    .lineLimit(1)

                if showingRaw {
                    Text("RAW")
                        .font(.system(size: 8.5, weight: .bold))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(DashboardPalette.rawAmber.opacity(0.18))
                        .foregroundStyle(DashboardPalette.rawAmber)
                        .clipShape(Capsule())
                } else if hasDiff {
                    Text("POLISHED")
                        .font(.system(size: 8.5, weight: .bold))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(DashboardPalette.rauschSoft)
                        .foregroundStyle(DashboardPalette.rausch)
                        .clipShape(Capsule())
                }

                Spacer(minLength: 4)

                HStack(spacing: 5) {
                    if let audioURL {
                        CircleMiniActionButton(
                            systemImage: isPlayingAudio ? "stop.fill" : "play.fill",
                            tint: isPlayingAudio ? DashboardPalette.rausch : DashboardPalette.ink,
                            help: isPlayingAudio ? "Stop playback" : "Play original dictation audio"
                        ) {
                            onToggleAudio(audioURL)
                        }
                    }

                    if hasDiff {
                        CircleMiniActionButton(
                            systemImage: "arrow.triangle.2.circlepath",
                            tint: showingRaw ? DashboardPalette.rawAmber : DashboardPalette.ink,
                            help: showingRaw ? "Show polished text" : "Show original raw ASR"
                        ) {
                            withAnimation(DashboardMetricsMotion.gentle) {
                                showingRaw.toggle()
                            }
                        }
                    }

                    CircleMiniActionButton(
                        systemImage: copiedRow ? "checkmark" : "doc.on.doc",
                        tint: copiedRow ? DashboardPalette.liveGreen : DashboardPalette.ink,
                        help: "Copy text"
                    ) {
                        Paster.copyPlainText(displayText)
                        withAnimation(DashboardMetricsMotion.pop) { copiedRow = true }
                        copyFeedbackTask?.cancel()
                        copyFeedbackTask = Task {
                            try? await Task.sleep(for: .seconds(1.4))
                            guard !Task.isCancelled else { return }
                            withAnimation(DashboardMetricsMotion.gentle) { copiedRow = false }
                        }
                    }
                }
                .opacity(isHovered || isPlayingAudio || isExpanded ? 1.0 : 0.65)

                Text(DashboardFormatters.relativeTime(from: item.timestamp))
                    .font(.system(size: 10))
                    .foregroundStyle(DashboardPalette.muted)
            }

            Text(displayText)
                .font(.system(size: 12, weight: showingRaw ? .regular : .medium))
                .foregroundStyle(showingRaw ? DashboardPalette.muted : DashboardPalette.body)
                .lineLimit(isExpanded ? 6 : 2)
                .fixedSize(horizontal: false, vertical: true)

            if isExpanded && hasDiff {
                VStack(alignment: .leading, spacing: 4) {
                    Text(showingRaw ? "POLISHED OUTPUT" : "RAW SPOKEN INPUT")
                        .font(.system(size: 8.5, weight: .bold))
                        .tracking(0.5)
                        .foregroundStyle(DashboardPalette.muted)
                    Text(showingRaw ? item.text : item.rawText)
                        .font(.system(size: 11))
                        .foregroundStyle(DashboardPalette.muted)
                        .lineLimit(4)
                }
                .padding(.top, 4)
                .transition(.opacity)
            }
        }
        .padding(11)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(isHovered || isExpanded ? DashboardPalette.surfaceCard : DashboardPalette.surfaceSoft)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(
                    isHovered || isExpanded ? DashboardPalette.hairlineHover : DashboardPalette.hairline.opacity(0.7),
                    lineWidth: 1
                )
        )
        .scaleEffect(isHovered ? 1.015 : 1.0)
        .offset(y: isHovered ? -1.5 : 0)
        .shadow(
            color: isHovered ? DashboardPalette.hoverShadow : .clear,
            radius: isHovered ? 6 : 0,
            y: isHovered ? 3 : 0
        )
        .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .onTapGesture {
            withAnimation(DashboardMetricsMotion.pop) {
                isExpanded.toggle()
            }
        }
        .animation(DashboardMetricsMotion.pop, value: isHovered)
        .onHover { isHovered = $0 }
        .onDisappear { copyFeedbackTask?.cancel() }
    }
}

private struct CircleMiniActionButton: View {
    let systemImage: String
    let tint: Color
    let help: String
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 9.5, weight: .semibold))
                .foregroundStyle(isHovered ? DashboardPalette.rausch : tint)
                .frame(width: 22, height: 22)
                .background(
                    Circle().fill(isHovered ? DashboardPalette.surfaceStrong : DashboardPalette.surfaceCard)
                )
                .overlay(Circle().stroke(DashboardPalette.hairline, lineWidth: 1))
                .scaleEffect(isHovered ? 1.12 : 1.0)
        }
        .buttonStyle(.plain)
        .animation(DashboardMetricsMotion.pop, value: isHovered)
        .onHover { isHovered = $0 }
        .help(help)
    }
}

// MARK: - Cached Native App Icon View

@MainActor
private enum AppIconCache {
    static let cache: NSCache<NSString, NSImage> = {
        let c = NSCache<NSString, NSImage>()
        c.countLimit = 64
        return c
    }()

    static func icon(for bundleID: String?) -> NSImage? {
        guard let bundleID, !bundleID.isEmpty else { return nil }
        let key = bundleID as NSString
        if let cached = cache.object(forKey: key) {
            return cached
        }
        guard let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else {
            return nil
        }
        let img = NSWorkspace.shared.icon(forFile: appURL.path)
        cache.setObject(img, forKey: key)
        return img
    }
}

struct DictationAppIconView: View {
    let bundleID: String?
    let fallbackName: String

    var body: some View {
        if let icon = AppIconCache.icon(for: bundleID) {
            Image(nsImage: icon)
                .resizable()
                .interpolation(.high)
                .aspectRatio(contentMode: .fit)
        } else {
            Image(systemName: Self.fallbackSymbol(for: fallbackName))
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(DashboardPalette.muted)
        }
    }

    static func fallbackSymbol(for name: String) -> String {
        let lower = name.lowercased()
        if lower.contains("iterm") || lower.contains("terminal") || lower.contains("warp") { return "terminal.fill" }
        if lower.contains("xcode") || lower.contains("code") || lower.contains("cursor") { return "hammer.fill" }
        if lower.contains("chrome") || lower.contains("safari") || lower.contains("arc") || lower.contains("brave") { return "globe" }
        if lower.contains("slack") || lower.contains("discord") || lower.contains("message") { return "bubble.left.and.bubble.right.fill" }
        if lower.contains("notes") || lower.contains("word") || lower.contains("doc") || lower.contains("obsidian") { return "doc.text.fill" }
        if lower.contains("mail") || lower.contains("outlook") { return "envelope.fill" }
        return "app.fill"
    }
}

// MARK: - Dictation Intelligence Metrics Computation

struct DictationIntelligenceMetrics {
    let totalItems: Int
    let totalWords: Int
    let totalDuration: TimeInterval
    let wordsPerMinute: Int
    let speedMultiplier: String
    let timeSavedFormatted: String
    let fixesCount: Int
    let fillerWordsPurged: Int
    let punctuationInserted: Int
    let wordsCorrected: Int
    let appUsage: [AppWorkflowEntry]
    let currentStreak: Int
    let longestStreak: Int
    let dailyCadence: [DailyVelocityEntry]
    let dailyAverageWords: Int
    let averageSessionDuration: String
    let recentTransformations: [DictationHistoryItem]

    static let empty = DictationIntelligenceMetrics(
        totalItems: 0,
        totalWords: 0,
        totalDuration: 0,
        wordsPerMinute: 0,
        speedMultiplier: "1.0",
        timeSavedFormatted: "<1m",
        fixesCount: 0,
        fillerWordsPurged: 0,
        punctuationInserted: 0,
        wordsCorrected: 0,
        appUsage: [],
        currentStreak: 0,
        longestStreak: 0,
        dailyCadence: [],
        dailyAverageWords: 0,
        averageSessionDuration: "0.0",
        recentTransformations: []
    )

    struct AppWorkflowEntry: Identifiable {
        let id = UUID()
        let name: String
        let bundleID: String?
        let wordCount: Int
        let sessionCount: Int
        let percent: Int
    }

    struct DailyVelocityEntry: Identifiable {
        let id = UUID()
        let date: Date
        let dayLabel: String
        let dateLabel: String
        let wordCount: Int
        let sessionCount: Int
        let isToday: Bool
    }

    private static let fillerTokens: Set<String> = [
        "um", "uh", "er", "ah", "like", "literally", "basically", "actually"
    ]

    private static let punctuationCharacters = CharacterSet(charactersIn: ".,?!;:-—\"'()[]")

    private static func dayAbbreviationFormatter() -> DateFormatter {
        let f = DateFormatter()
        f.dateFormat = "EEEEE"
        return f
    }

    private static func shortDateFormatter() -> DateFormatter {
        let f = DateFormatter()
        f.dateFormat = "MMM d"
        return f
    }

    static func compute(
        from allItems: [DictationHistoryItem],
        window: DashboardTimeWindow = .all
    ) -> DictationIntelligenceMetrics {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())

        let items: [DictationHistoryItem]
        if let filterDays = window.filterDays,
           let cutoff = calendar.date(byAdding: .day, value: -(filterDays - 1), to: today) {
            items = allItems.filter { $0.timestamp >= cutoff }
        } else {
            items = allItems
        }

        let totalItems = items.count
        let totalWords = items.reduce(0) { $0 + $1.wordCount }
        let totalDuration = items.reduce(0.0) { $0 + $1.duration }

        // Speech Velocity (Words per minute)
        let validWPMItems = items.filter { $0.duration >= 0.5 && $0.wordCount > 0 }
        let validWords = validWPMItems.reduce(0) { $0 + $1.wordCount }
        let validDuration = validWPMItems.reduce(0.0) { $0 + $1.duration }
        let wpm: Int
        if validDuration > 1.0 && validWords > 0 {
            let rawWpm = Int(round((Double(validWords) / validDuration) * 60.0))
            wpm = max(10, min(300, rawWpm))
        } else {
            wpm = 0
        }

        let speedMultiplier = wpm > 0 ? String(format: "%.1f", Double(wpm) / 45.0) : "1.0"

        // Time Saved vs 45 WPM baseline
        let timeSavedMinutes = max(0, (Double(totalWords) / 45.0) - (totalDuration / 60.0))
        let timeSavedFormatted: String
        if timeSavedMinutes >= 60 {
            timeSavedFormatted = String(format: "%.1fh", timeSavedMinutes / 60.0)
        } else if timeSavedMinutes >= 1 {
            timeSavedFormatted = String(format: "%.0fm", timeSavedMinutes)
        } else {
            timeSavedFormatted = "<1m"
        }

        let avgSecs = totalItems > 0 ? totalDuration / Double(totalItems) : 0
        let averageSessionDuration = String(format: "%.1f", avgSecs)

        // Neural S1-mini / deterministic normalizations
        var fixesCount = 0
        var fillerWordsPurged = 0
        var punctuationInserted = 0
        var wordsCorrected = 0

        for item in items {
            let raw = item.rawText.trimmingCharacters(in: .whitespacesAndNewlines)
            let txt = item.text.trimmingCharacters(in: .whitespacesAndNewlines)
            if !raw.isEmpty && !txt.isEmpty && raw != txt {
                fixesCount += 1
                let rawWords = raw.lowercased().components(separatedBy: CharacterSet.alphanumerics.inverted).filter { !$0.isEmpty }
                let cleanWords = txt.lowercased().components(separatedBy: CharacterSet.alphanumerics.inverted).filter { !$0.isEmpty }

                let rawFillers = rawWords.filter { fillerTokens.contains($0) }.count
                let cleanFillers = cleanWords.filter { fillerTokens.contains($0) }.count
                fillerWordsPurged += max(0, rawFillers - cleanFillers)

                let rawPunct = raw.unicodeScalars.filter { punctuationCharacters.contains($0) }.count
                let cleanPunct = txt.unicodeScalars.filter { punctuationCharacters.contains($0) }.count
                punctuationInserted += max(0, cleanPunct - rawPunct)

                wordsCorrected += max(1, abs(rawWords.count - cleanWords.count) + zip(rawWords, cleanWords).filter { $0 != $1 }.count)
            }
        }

        // App workflow breakdown (including per-app session count)
        var appWordMap: [String: (bundleID: String?, words: Int, sessions: Int)] = [:]
        for item in items {
            let name: String
            if let appName = item.appName, !appName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                name = appName
            } else {
                name = "System Input"
            }
            let cur = appWordMap[name] ?? (bundleID: item.appBundleID, words: 0, sessions: 0)
            appWordMap[name] = (
                bundleID: cur.bundleID ?? item.appBundleID,
                words: cur.words + item.wordCount,
                sessions: cur.sessions + 1
            )
        }

        let sortedApps = appWordMap.sorted { $0.value.words > $1.value.words }
        var appUsage: [AppWorkflowEntry] = []
        for entry in sortedApps.prefix(5) {
            let percent = totalWords > 0 ? Int(round(Double(entry.value.words) / Double(totalWords) * 100.0)) : 0
            appUsage.append(AppWorkflowEntry(
                name: entry.key,
                bundleID: entry.value.bundleID,
                wordCount: entry.value.words,
                sessionCount: entry.value.sessions,
                percent: max(1, percent)
            ))
        }

        // Streaks always reflect full lifetime cadence for continuity
        var allDayCounts: [Date: (words: Int, sessions: Int)] = [:]
        for item in allItems {
            let day = calendar.startOfDay(for: item.timestamp)
            let cur = allDayCounts[day] ?? (words: 0, sessions: 0)
            allDayCounts[day] = (words: cur.words + item.wordCount, sessions: cur.sessions + 1)
        }

        var currentStreak = 0
        var testDay = today
        if (allDayCounts[testDay]?.words ?? 0) == 0,
           let yesterday = calendar.date(byAdding: .day, value: -1, to: today),
           (allDayCounts[yesterday]?.words ?? 0) > 0 {
            testDay = yesterday
        }
        while (allDayCounts[testDay]?.words ?? 0) > 0 {
            currentStreak += 1
            guard let prev = calendar.date(byAdding: .day, value: -1, to: testDay) else { break }
            testDay = prev
        }

        let sortedDays = allDayCounts.keys.sorted()
        var longestStreak = 0
        var runStreak = 0
        var prevDate: Date? = nil
        for d in sortedDays {
            if let prev = prevDate,
               let nextDay = calendar.date(byAdding: .day, value: 1, to: prev),
               calendar.isDate(d, inSameDayAs: nextDay) {
                runStreak += 1
            } else {
                runStreak = 1
            }
            prevDate = d
            if runStreak > longestStreak { longestStreak = runStreak }
        }
        if currentStreak > longestStreak { longestStreak = currentStreak }

        // Cadence bars over selected window (14 days default, 7 days for 7D)
        let cadenceDays = window.cadenceDays
        let dayAbbrFormatter = dayAbbreviationFormatter()
        let shortFormatter = shortDateFormatter()
        var dailyCadence: [DailyVelocityEntry] = []
        var totalWindowWords = 0

        for offset in (0..<cadenceDays).reversed() {
            if let date = calendar.date(byAdding: .day, value: -offset, to: today) {
                let stats = allDayCounts[date] ?? (words: 0, sessions: 0)
                let isToday = offset == 0
                totalWindowWords += stats.words
                dailyCadence.append(DailyVelocityEntry(
                    date: date,
                    dayLabel: isToday ? "Today" : dayAbbrFormatter.string(from: date),
                    dateLabel: shortFormatter.string(from: date),
                    wordCount: stats.words,
                    sessionCount: stats.sessions,
                    isToday: isToday
                ))
            }
        }

        let dailyAverageWords = cadenceDays > 0 ? (totalWindowWords / cadenceDays) : 0
        let recentTransformations = Array(items.prefix(3))

        return DictationIntelligenceMetrics(
            totalItems: totalItems,
            totalWords: totalWords,
            totalDuration: totalDuration,
            wordsPerMinute: wpm,
            speedMultiplier: speedMultiplier,
            timeSavedFormatted: timeSavedFormatted,
            fixesCount: fixesCount,
            fillerWordsPurged: fillerWordsPurged,
            punctuationInserted: punctuationInserted,
            wordsCorrected: wordsCorrected,
            appUsage: appUsage,
            currentStreak: currentStreak,
            longestStreak: longestStreak,
            dailyCadence: dailyCadence,
            dailyAverageWords: dailyAverageWords,
            averageSessionDuration: averageSessionDuration,
            recentTransformations: recentTransformations
        )
    }
}

// MARK: - Dictation Audio Player

@MainActor
@Observable
final class DictationAudioPlayer: NSObject, AVAudioPlayerDelegate {
    private var player: AVAudioPlayer?
    private(set) var playingID: UUID?

    func toggle(id: UUID, url: URL) {
        if playingID == id {
            stop()
            return
        }
        stop()
        do {
            let p = try AVAudioPlayer(contentsOf: url)
            p.delegate = self
            p.prepareToPlay()
            p.play()
            player = p
            playingID = id
        } catch {
            playingID = nil
        }
    }

    func stop() {
        player?.stop()
        player = nil
        playingID = nil
    }

    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in
            self.stop()
        }
    }
}
