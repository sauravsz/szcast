import AppKit
import AVFoundation
import SwiftUI

/// Dictation Intelligence Dashboard displaying acoustic speed velocity, S1-mini normalization telemetry,
/// native macOS desktop application breakdown, and a 14-day activity cadence histogram.
struct DictationInsightsDashboardView: View {
    @Environment(DictationCoordinator.self) private var coordinator
    @Environment(AppSettings.self) private var settings
    @State private var copiedNotice = false
    @State private var showingClearConfirmation = false
    @State private var audioPlayer = DictationAudioPlayer()
    @State private var showRawTextIDs: Set<UUID> = []

    private var items: [DictationHistoryItem] {
        coordinator.historyStore.items
    }

    private var metrics: DictationIntelligenceMetrics {
        DictationIntelligenceMetrics.compute(from: items)
    }

    private var engineSummary: String {
        let asrName: String
        switch settings.dictationTranscriptionProvider {
        case .local:
            asrName = settings.dictationModel.variantTitle
        case .cloud:
            asrName = settings.dictationCloudSpeechProvider.title
        }

        let polishName: String
        if settings.dictationS1Enabled {
            switch settings.dictationPolishProvider {
            case .localS1: polishName = "S1-mini (Local)"
            case .groq: polishName = "Groq Llama"
            }
        } else {
            polishName = "Raw STT"
        }

        return "\(asrName) • \(polishName)"
    }

    var body: some View {
        ScrollView(.vertical, showsIndicators: true) {
            VStack(alignment: .leading, spacing: Theme.Spacing.xl) {
                headerView

                // Row 1: 3 Hero Velocity & Telemetry Cards
                heroCardsRow

                // Row 2: 14-Day Activity & Velocity Histogram
                cadenceHistogramCard

                // Row 3: Desktop App Workflow & Live Normalization Inspector
                workflowAndTransformationsRow
            }
            .padding(.horizontal, Theme.Spacing.xxl)
            .padding(.vertical, Theme.Spacing.xl)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
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

    // MARK: - Header

    private var headerView: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Dictation Intelligence")
                    .font(.system(size: 22, weight: .bold))
                Text("Acoustic velocity, S1-mini normalization telemetry, and desktop workflow analytics.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 12)
            HStack(spacing: 8) {
                // Active Engine Badge
                HStack(spacing: 6) {
                    Circle()
                        .fill(settings.dictationEnabled ? Color.green : Color.secondary)
                        .frame(width: 6, height: 6)
                    Text(engineSummary)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 9)
                .padding(.vertical, 5)
                .background(Color.primary.opacity(0.04))
                .clipShape(Capsule())
                .overlay(Capsule().stroke(Color.primary.opacity(0.08), lineWidth: 1))

                // Copy report button
                Button {
                    copyShareSummary()
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: copiedNotice ? "checkmark" : "square.and.arrow.up")
                            .font(.system(size: 11, weight: .semibold))
                        Text(copiedNotice ? "Copied" : "Copy Report")
                            .font(.system(size: 11, weight: .semibold))
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Color.primary.opacity(0.06))
                    .foregroundStyle(.primary)
                    .clipShape(Capsule())
                    .overlay(Capsule().stroke(Color.primary.opacity(0.12), lineWidth: 1))
                }
                .buttonStyle(.plain)

                // Menu for reset
                Menu {
                    Button(role: .destructive) {
                        showingClearConfirmation = true
                    } label: {
                        Label("Reset Dictation Analytics", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .font(.system(size: 14))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func copyShareSummary() {
        let m = metrics
        let engine = engineSummary
        let summary = """
        # szcast Dictation Intelligence Report
        • Pipeline: \(engine)
        • Speed: \(m.wordsPerMinute > 0 ? "\(m.wordsPerMinute) WPM (\(m.speedMultiplier)x keyboard pace)" : "Awaiting data")
        • Time Saved: \(m.timeSavedFormatted) vs 45 WPM typing
        • Volume: \(formatNumber(m.totalWords)) words across \(m.totalItems) sessions (\(formatDuration(m.totalDuration)) speech)
        • Neural Impact: \(m.fixesCount) normalizations (\(m.fillerWordsPurged) fillers purged, \(m.wordsCorrected) words polished)
        • Daily Streak: \(m.currentStreak) days active (Longest: \(m.longestStreak) days)
        """
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(summary, forType: .string)
        withAnimation { copiedNotice = true }
        Task {
            try? await Task.sleep(for: .seconds(2))
            withAnimation { copiedNotice = false }
        }
    }

    // MARK: - Row 1: Hero Cards

    private var heroCardsRow: some View {
        HStack(alignment: .top, spacing: Theme.Spacing.md) {
            speedVelocityCard
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            neuralNormalizationCard
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            volumeAndCadenceCard
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    // MARK: - Card 1: Speed Velocity

    private var speedVelocityCard: some View {
        cardContainer {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 2) {
                        if metrics.wordsPerMinute > 0 {
                            Text("\(metrics.wordsPerMinute)")
                                .font(.system(size: 28, weight: .bold, design: .rounded))
                                .monospacedDigit()
                        } else {
                            Text("—")
                                .font(.system(size: 28, weight: .bold, design: .rounded))
                                .foregroundStyle(.secondary)
                        }
                        Text("WORDS PER MINUTE")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    if metrics.wordsPerMinute > 0 {
                        Text("\(metrics.speedMultiplier)x typing pace")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(Theme.Colors.brand)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(Theme.Colors.brand.opacity(0.12))
                            .clipShape(Capsule())
                    }
                }

                Divider()

                VStack(spacing: 8) {
                    VStack(alignment: .leading, spacing: 3) {
                        HStack {
                            Text("Voice Velocity")
                                .font(.system(size: 10, weight: .medium))
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text(metrics.wordsPerMinute > 0 ? "\(metrics.wordsPerMinute) WPM" : "0 WPM")
                                .font(.system(size: 10, weight: .bold, design: .rounded))
                                .foregroundStyle(Theme.Colors.brand)
                        }
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                Capsule().fill(Color.primary.opacity(0.06)).frame(height: 5)
                                let width = max(6, min(geo.size.width, geo.size.width * CGFloat(min(metrics.wordsPerMinute, 240)) / 240.0))
                                Capsule()
                                    .fill(LinearGradient(colors: [Theme.Colors.brand, Color.accentColor], startPoint: .leading, endPoint: .trailing))
                                    .frame(width: width, height: 5)
                            }
                        }
                        .frame(height: 5)
                    }

                    VStack(alignment: .leading, spacing: 3) {
                        HStack {
                            Text("Typing Baseline")
                                .font(.system(size: 10, weight: .medium))
                                .foregroundStyle(.tertiary)
                            Spacer()
                            Text("45 WPM")
                                .font(.system(size: 10, weight: .medium, design: .rounded))
                                .foregroundStyle(.tertiary)
                        }
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                Capsule().fill(Color.primary.opacity(0.06)).frame(height: 4)
                                let width = max(6, min(geo.size.width, geo.size.width * 45.0 / 240.0))
                                Capsule()
                                    .fill(Color.secondary.opacity(0.35))
                                    .frame(width: width, height: 4)
                            }
                        }
                        .frame(height: 4)
                    }
                }

                Spacer(minLength: 0)

                HStack(spacing: 4) {
                    Image(systemName: "clock.arrow.circlepath")
                        .font(.system(size: 10))
                        .foregroundStyle(Color.accentColor)
                    Text("Saved ~\(metrics.timeSavedFormatted)")
                        .font(.system(size: 11, weight: .semibold))
                    Text("vs keyboard input")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
                .padding(.top, 2)
            }
        }
    }

    // MARK: - Card 2: Neural Normalization

    private var neuralNormalizationCard: some View {
        cardContainer {
            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(formatNumber(metrics.fixesCount))")
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                        .monospacedDigit()
                    Text("NEURAL NORMALIZATIONS")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.secondary)
                }

                Divider()

                VStack(spacing: 7) {
                    HStack(spacing: 8) {
                        Image(systemName: "waveform.badge.minus")
                            .font(.system(size: 11))
                            .foregroundStyle(Color.accentColor)
                            .frame(width: 14)
                        Text("\(formatNumber(metrics.fillerWordsPurged)) fillers purged")
                            .font(.system(size: 11, weight: .medium))
                        Spacer()
                    }

                    HStack(spacing: 8) {
                        Image(systemName: "character.cursor.ibeam")
                            .font(.system(size: 11))
                            .foregroundStyle(Color.accentColor)
                            .frame(width: 14)
                        Text("\(formatNumber(metrics.punctuationInserted)) punctuation inserted")
                            .font(.system(size: 11, weight: .medium))
                        Spacer()
                    }

                    HStack(spacing: 8) {
                        Image(systemName: "wand.and.stars")
                            .font(.system(size: 11))
                            .foregroundStyle(Color.accentColor)
                            .frame(width: 14)
                        Text("\(formatNumber(metrics.wordsCorrected)) words polished")
                            .font(.system(size: 11, weight: .medium))
                        Spacer()
                    }
                }

                Spacer(minLength: 0)

                HStack(spacing: 6) {
                    Circle()
                        .fill(settings.dictationS1Enabled ? Color.green : Color.orange)
                        .frame(width: 6, height: 6)
                    Text(settings.dictationS1Enabled ? "S1-mini Local Daemon Active" : "Neural Polish Disabled")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.secondary)
                }
                .padding(.top, 2)
            }
        }
    }

    // MARK: - Card 3: Volume & Cadence

    private var volumeAndCadenceCard: some View {
        cardContainer {
            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(formatNumber(metrics.totalWords))
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                        .monospacedDigit()
                    Text("TOTAL WORDS DICTATED")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.secondary)
                }

                Divider()

                VStack(spacing: 7) {
                    HStack(spacing: 8) {
                        Image(systemName: "mic.fill")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .frame(width: 14)
                        Text("\(formatDuration(metrics.totalDuration)) speech")
                            .font(.system(size: 11, weight: .medium))
                        Spacer()
                        Text("\(metrics.totalItems) sessions")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(.secondary)
                    }

                    HStack(spacing: 8) {
                        Image(systemName: "timer")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .frame(width: 14)
                        Text("Average burst: \(metrics.averageSessionDuration)s")
                            .font(.system(size: 11, weight: .medium))
                        Spacer()
                    }

                    HStack(spacing: 8) {
                        Image(systemName: "flame.fill")
                            .font(.system(size: 11))
                            .foregroundStyle(metrics.currentStreak > 0 ? Color.orange : Color.secondary)
                            .frame(width: 14)
                        Text("\(metrics.currentStreak) day active streak")
                            .font(.system(size: 11, weight: .medium))
                        Spacer()
                        Text("Best: \(metrics.longestStreak)d")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer(minLength: 0)

                if metrics.totalWords > 0 {
                    let pages = max(1, Int(round(Double(metrics.totalWords) / 250.0)))
                    Text("Equivalent to ~\(pages) page\(pages == 1 ? "" : "s") of written prose")
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                        .padding(.top, 2)
                }
            }
        }
    }

    // MARK: - Row 2: Cadence Histogram Card

    private var cadenceHistogramCard: some View {
        cardContainer {
            VStack(alignment: .leading, spacing: Theme.Spacing.xl) {
                HStack(alignment: .center) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Speech Cadence & Momentum")
                            .font(.system(size: 14, weight: .bold))
                        Text("Daily word volume across the last 14 days")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    HStack(spacing: Theme.Spacing.xl) {
                        VStack(alignment: .trailing, spacing: 2) {
                            Text("\(formatNumber(metrics.dailyAverageWords)) w/day")
                                .font(.system(size: 12, weight: .bold, design: .rounded))
                                .monospacedDigit()
                            Text("14-DAY AVERAGE")
                                .font(.system(size: 8, weight: .semibold))
                                .foregroundStyle(.secondary)
                        }
                        VStack(alignment: .trailing, spacing: 2) {
                            Text("\(metrics.currentStreak) days")
                                .font(.system(size: 12, weight: .bold, design: .rounded))
                                .foregroundStyle(Color.accentColor)
                            Text("ACTIVE STREAK")
                                .font(.system(size: 8, weight: .semibold))
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                // 14 daily bars
                let maxWords = max(50, metrics.dailyCadence.map(\.wordCount).max() ?? 50)
                HStack(alignment: .bottom, spacing: 8) {
                    ForEach(metrics.dailyCadence) { day in
                        VStack(spacing: 6) {
                            ZStack(alignment: .bottom) {
                                RoundedRectangle(cornerRadius: 3, style: .continuous)
                                    .fill(Color.primary.opacity(0.04))
                                    .frame(height: 64)

                                let height = max(4, CGFloat(day.wordCount) / CGFloat(maxWords) * 64.0)
                                RoundedRectangle(cornerRadius: 3, style: .continuous)
                                    .fill(
                                        day.isToday
                                            ? LinearGradient(colors: [Theme.Colors.brand, Color.accentColor], startPoint: .top, endPoint: .bottom)
                                            : (day.wordCount > 0
                                                ? LinearGradient(colors: [Theme.Colors.brand.opacity(0.85), Theme.Colors.brand.opacity(0.45)], startPoint: .top, endPoint: .bottom)
                                                : LinearGradient(colors: [Color.primary.opacity(0.08), Color.primary.opacity(0.08)], startPoint: .top, endPoint: .bottom))
                                    )
                                    .frame(height: height)
                            }
                            .help("\(day.dateLabel): \(day.wordCount) words (\(day.sessionCount) sessions)")

                            Text(day.dayLabel)
                                .font(.system(size: 9, weight: day.isToday ? .bold : .medium))
                                .foregroundStyle(day.isToday ? Color.accentColor : .secondary)
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
                .frame(height: 84)
            }
        }
    }

    // MARK: - Row 3: Desktop App Workflow & Live Normalization Inspector

    private var workflowAndTransformationsRow: some View {
        HStack(alignment: .top, spacing: Theme.Spacing.md) {
            desktopWorkflowCard
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            recentTransformationsCard
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    // MARK: - Desktop Workflow Card

    private var desktopWorkflowCard: some View {
        cardContainer {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Desktop Application Workflow")
                        .font(.system(size: 14, weight: .bold))
                    Spacer()
                    Text("\(max(1, metrics.appUsage.count)) APPS")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.secondary)
                }

                if metrics.appUsage.isEmpty {
                    VStack(alignment: .center, spacing: 6) {
                        Image(systemName: "macwindow")
                            .font(.system(size: 20))
                            .foregroundStyle(.tertiary)
                        Text("No application telemetry yet.")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                        Text("Dictate into apps like Xcode, Slack, or Safari to map workflow usage.")
                            .font(.system(size: 10))
                            .foregroundStyle(.tertiary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, Theme.Spacing.xl)
                } else {
                    VStack(spacing: 10) {
                        ForEach(metrics.appUsage) { app in
                            HStack(spacing: 10) {
                                DictationAppIconView(bundleID: app.bundleID, fallbackName: app.name)
                                    .frame(width: 22, height: 22)

                                VStack(alignment: .leading, spacing: 3) {
                                    HStack {
                                        Text(app.name)
                                            .font(.system(size: 11, weight: .medium))
                                            .lineLimit(1)
                                        Spacer()
                                        Text("\(formatNumber(app.wordCount)) w")
                                            .font(.system(size: 10, weight: .semibold, design: .rounded))
                                            .monospacedDigit()
                                        Text("(\(app.percent)%)")
                                            .font(.system(size: 9))
                                            .foregroundStyle(.secondary)
                                    }

                                    GeometryReader { geo in
                                        ZStack(alignment: .leading) {
                                            Capsule()
                                                .fill(Color.primary.opacity(0.04))
                                                .frame(height: 4)
                                            let barWidth = max(6, geo.size.width * CGFloat(app.percent) / 100.0)
                                            Capsule()
                                                .fill(LinearGradient(colors: [Theme.Colors.brand, Color.accentColor], startPoint: .leading, endPoint: .trailing))
                                                .frame(width: barWidth, height: 4)
                                        }
                                    }
                                    .frame(height: 4)
                                }
                            }
                        }
                    }
                }
                Spacer(minLength: 0)
            }
        }
    }

    // MARK: - Recent Neural Transformations Card

    private var recentTransformationsCard: some View {
        cardContainer {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Recent Neural Transformations")
                        .font(.system(size: 14, weight: .bold))
                    Spacer()
                    Text("S1-MINI DIFF")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.secondary)
                }

                if metrics.recentTransformations.isEmpty {
                    VStack(alignment: .center, spacing: 6) {
                        Image(systemName: "waveform.badge.magnifyingglass")
                            .font(.system(size: 20))
                            .foregroundStyle(.tertiary)
                        Text("No recent speech records.")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                        Text("Transcripts will show raw acoustic input vs S1-mini polished output.")
                            .font(.system(size: 10))
                            .foregroundStyle(.tertiary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, Theme.Spacing.xl)
                } else {
                    VStack(spacing: 8) {
                        ForEach(metrics.recentTransformations) { item in
                            let isShowingRaw = showRawTextIDs.contains(item.id)
                            let displayText = (isShowingRaw && !item.rawText.isEmpty) ? item.rawText : item.text
                            let hasAudio = coordinator.historyStore.audioURL(for: item) != nil
                            let hasDiff = item.rawText != item.text && !item.rawText.isEmpty

                            VStack(alignment: .leading, spacing: 4) {
                                HStack(spacing: 6) {
                                    DictationAppIconView(bundleID: item.appBundleID, fallbackName: item.appName ?? "System")
                                        .frame(width: 14, height: 14)
                                    Text(item.appName ?? "System")
                                        .font(.system(size: 10, weight: .semibold))

                                    if isShowingRaw {
                                        Text("RAW ASR")
                                            .font(.system(size: 8, weight: .bold))
                                            .padding(.horizontal, 4)
                                            .padding(.vertical, 1)
                                            .background(Color.orange.opacity(0.15))
                                            .foregroundStyle(Color.orange)
                                            .clipShape(RoundedRectangle(cornerRadius: 3))
                                    }

                                    Spacer()

                                    if hasAudio, let audioURL = coordinator.historyStore.audioURL(for: item) {
                                        Button {
                                            audioPlayer.toggle(id: item.id, url: audioURL)
                                        } label: {
                                            Image(systemName: audioPlayer.playingID == item.id ? "stop.fill" : "play.fill")
                                                .font(.system(size: 9))
                                                .foregroundStyle(audioPlayer.playingID == item.id ? Color.red : Color.accentColor)
                                        }
                                        .buttonStyle(.plain)
                                        .help(audioPlayer.playingID == item.id ? "Stop playback" : "Play original dictation audio")
                                    }

                                    if hasDiff {
                                        Button {
                                            if isShowingRaw {
                                                showRawTextIDs.remove(item.id)
                                            } else {
                                                showRawTextIDs.insert(item.id)
                                            }
                                        } label: {
                                            Image(systemName: "arrow.triangle.2.circlepath")
                                                .font(.system(size: 9))
                                                .foregroundStyle(isShowingRaw ? Color.orange : Color.secondary)
                                        }
                                        .buttonStyle(.plain)
                                        .help(isShowingRaw ? "Show polished text" : "Show original raw ASR")
                                    }

                                    Button {
                                        Paster.copyPlainText(displayText)
                                    } label: {
                                        Image(systemName: "doc.on.doc")
                                            .font(.system(size: 9))
                                            .foregroundStyle(.secondary)
                                    }
                                    .buttonStyle(.plain)
                                    .help("Copy to clipboard")

                                    Text(relativeTimeString(from: item.timestamp))
                                        .font(.system(size: 9))
                                        .foregroundStyle(.tertiary)
                                }

                                Text(displayText)
                                    .font(.system(size: 11, weight: isShowingRaw ? .regular : .medium))
                                    .foregroundStyle(isShowingRaw ? .secondary : .primary)
                                    .lineLimit(2)
                            }
                            .padding(Theme.Spacing.md)
                            .background(Color.primary.opacity(0.03))
                            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.menu, style: .continuous))
                        }
                    }
                }
                Spacer(minLength: 0)
            }
        }
    }

    // MARK: - Helpers

    private func cardContainer<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .padding(Theme.Spacing.xl)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(Color(nsColor: .controlBackgroundColor).opacity(0.70))
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                    .stroke(Theme.Colors.cardStroke, lineWidth: Theme.Size.hairline)
            )
    }

    private func formatNumber(_ num: Int) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        return formatter.string(from: NSNumber(value: num)) ?? "\(num)"
    }

    private func formatDuration(_ secs: TimeInterval) -> String {
        if secs < 60 {
            return String(format: "%.0fs", secs)
        }
        let mins = Int(secs / 60)
        let remainSecs = Int(secs.truncatingRemainder(dividingBy: 60))
        return "\(mins)m \(remainSecs)s"
    }

    private func relativeTimeString(from date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}

// MARK: - Dictation App Icon View (Native macOS App Icon with Symbol Fallback)

struct DictationAppIconView: View {
    let bundleID: String?
    let fallbackName: String

    var body: some View {
        if let icon = resolveIcon() {
            Image(nsImage: icon)
                .resizable()
                .interpolation(.high)
                .aspectRatio(contentMode: .fit)
        } else {
            Image(systemName: Self.fallbackSymbol(for: fallbackName))
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
        }
    }

    private func resolveIcon() -> NSImage? {
        guard let bundleID, !bundleID.isEmpty,
              let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else {
            return nil
        }
        return NSWorkspace.shared.icon(forFile: appURL.path)
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

    struct AppWorkflowEntry: Identifiable {
        let id = UUID()
        let name: String
        let bundleID: String?
        let wordCount: Int
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

    static func compute(from items: [DictationHistoryItem]) -> DictationIntelligenceMetrics {
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

        // Multiplier vs standard 45 WPM typing
        let speedMultiplier: String
        if wpm > 0 {
            let mult = Double(wpm) / 45.0
            speedMultiplier = String(format: "%.1f", mult)
        } else {
            speedMultiplier = "1.0"
        }

        // Time Saved
        let timeSavedMinutes = max(0, (Double(totalWords) / 45.0) - (totalDuration / 60.0))
        let timeSavedFormatted: String
        if timeSavedMinutes >= 60 {
            let hours = timeSavedMinutes / 60.0
            timeSavedFormatted = String(format: "%.1fh", hours)
        } else if timeSavedMinutes >= 1 {
            timeSavedFormatted = String(format: "%.0fm", timeSavedMinutes)
        } else {
            timeSavedFormatted = "<1m"
        }

        // Average burst duration
        let avgSecs = totalItems > 0 ? totalDuration / Double(totalItems) : 0
        let averageSessionDuration = String(format: "%.1f", avgSecs)

        // Neural S1-mini Normalizations & Transformations
        var fixesCount = 0
        var fillerWordsPurged = 0
        var punctuationInserted = 0
        var wordsCorrected = 0

        for item in items {
            let raw = item.rawText.trimmingCharacters(in: .whitespacesAndNewlines)
            let txt = item.text.trimmingCharacters(in: .whitespacesAndNewlines)

            if !raw.isEmpty && !txt.isEmpty && raw != txt {
                fixesCount += 1

                // Count filler tokens in raw vs clean
                let rawWords = raw.lowercased().components(separatedBy: CharacterSet.alphanumerics.inverted).filter { !$0.isEmpty }
                let cleanWords = txt.lowercased().components(separatedBy: CharacterSet.alphanumerics.inverted).filter { !$0.isEmpty }

                let rawFillers = rawWords.filter { fillerTokens.contains($0) }.count
                let cleanFillers = cleanWords.filter { fillerTokens.contains($0) }.count
                fillerWordsPurged += max(0, rawFillers - cleanFillers)

                // Count punctuation
                let rawPunct = raw.unicodeScalars.filter { punctuationCharacters.contains($0) }.count
                let cleanPunct = txt.unicodeScalars.filter { punctuationCharacters.contains($0) }.count
                punctuationInserted += max(0, cleanPunct - rawPunct)

                // Word count edits
                wordsCorrected += max(1, abs(rawWords.count - cleanWords.count) + zip(rawWords, cleanWords).filter { $0 != $1 }.count)
            }
        }

        // App Workflow Breakdown
        var appWordMap: [String: (bundleID: String?, words: Int)] = [:]
        for item in items {
            let name: String
            if let appName = item.appName, !appName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                name = appName
            } else {
                name = "System Input"
            }
            let cur = appWordMap[name] ?? (bundleID: item.appBundleID, words: 0)
            appWordMap[name] = (bundleID: cur.bundleID ?? item.appBundleID, words: cur.words + item.wordCount)
        }

        let sortedApps = appWordMap.sorted { $0.value.words > $1.value.words }
        var appUsage: [AppWorkflowEntry] = []
        for entry in sortedApps.prefix(5) {
            let percent = totalWords > 0 ? Int(round(Double(entry.value.words) / Double(totalWords) * 100.0)) : 0
            appUsage.append(AppWorkflowEntry(
                name: entry.key,
                bundleID: entry.value.bundleID,
                wordCount: entry.value.words,
                percent: max(1, percent)
            ))
        }

        // Calendar streaks & 14-day cadence
        let calendar = Calendar.current
        var dayCounts: [Date: (words: Int, sessions: Int)] = [:]
        for item in items {
            let day = calendar.startOfDay(for: item.timestamp)
            let cur = dayCounts[day] ?? (words: 0, sessions: 0)
            dayCounts[day] = (words: cur.words + item.wordCount, sessions: cur.sessions + 1)
        }

        let today = calendar.startOfDay(for: Date())
        var currentStreak = 0
        var testDay = today
        if (dayCounts[testDay]?.words ?? 0) == 0 {
            if let yesterday = calendar.date(byAdding: .day, value: -1, to: today), (dayCounts[yesterday]?.words ?? 0) > 0 {
                testDay = yesterday
            }
        }
        while (dayCounts[testDay]?.words ?? 0) > 0 {
            currentStreak += 1
            guard let prev = calendar.date(byAdding: .day, value: -1, to: testDay) else { break }
            testDay = prev
        }

        let sortedDays = dayCounts.keys.sorted()
        var longestStreak = 0
        var runStreak = 0
        var prevDate: Date? = nil
        for d in sortedDays {
            if let prev = prevDate, let nextDay = calendar.date(byAdding: .day, value: 1, to: prev), calendar.isDate(d, inSameDayAs: nextDay) {
                runStreak += 1
            } else {
                runStreak = 1
            }
            prevDate = d
            if runStreak > longestStreak { longestStreak = runStreak }
        }
        if currentStreak > longestStreak { longestStreak = currentStreak }

        // 14-Day Cadence
        let dayAbbrFormatter = DateFormatter()
        dayAbbrFormatter.dateFormat = "EEEEE"

        let shortDateFormatter = DateFormatter()
        shortDateFormatter.dateFormat = "MMM d"

        var dailyCadence: [DailyVelocityEntry] = []
        var total14DayWords = 0

        for offset in (0..<14).reversed() {
            if let date = calendar.date(byAdding: .day, value: -offset, to: today) {
                let stats = dayCounts[date] ?? (words: 0, sessions: 0)
                let isToday = offset == 0
                total14DayWords += stats.words
                dailyCadence.append(DailyVelocityEntry(
                    date: date,
                    dayLabel: isToday ? "Today" : dayAbbrFormatter.string(from: date),
                    dateLabel: shortDateFormatter.string(from: date),
                    wordCount: stats.words,
                    sessionCount: stats.sessions,
                    isToday: isToday
                ))
            }
        }

        let dailyAverageWords = total14DayWords / 14
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
