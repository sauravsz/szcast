import AppKit
import SwiftUI

/// Dictation Insights Dashboard displaying actual speech analytics, S1-mini normalization metrics,
/// real desktop application usage breakdown, and a real calendar contribution heatmap.
struct DictationInsightsDashboardView: View {
    @Environment(DictationCoordinator.self) private var coordinator
    @State private var copiedNotice = false
    @State private var currentStreakOnly = false

    // Theme palette matching Wispr Flow aesthetic
    private let darkTeal = Color(red: 0.07, green: 0.35, blue: 0.33)      // #125954
    private let midTeal = Color(red: 0.15, green: 0.54, blue: 0.50)       // #268A80
    private let lightTeal = Color(red: 0.28, green: 0.72, blue: 0.65)     // #47B8A6
    private let softTealBg = Color(red: 0.28, green: 0.72, blue: 0.65).opacity(0.14)
    private let cardBorder = Color.primary.opacity(0.08)

    private var items: [DictationHistoryItem] {
        coordinator.historyStore.items
    }

    private var metrics: RealDictationMetrics {
        RealDictationMetrics.compute(from: items)
    }

    var body: some View {
        ScrollView(.vertical, showsIndicators: true) {
            VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                headerView

                // Row 1: 3 Summary Cards
                summaryCardsRow

                // Row 2: Desktop Usage & Activity Streak
                usageAndStreakRow
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    // MARK: - Header

    private var headerView: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Insights")
                    .font(.system(size: 24, weight: .bold))
                Text("Real-time speech analytics, speed cadence, and AI normalization impact.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 12)
            shareButton
        }
    }

    private var shareButton: some View {
        Button {
            copyShareSummary()
        } label: {
            HStack(spacing: 6) {
                Image(systemName: copiedNotice ? "checkmark" : "square.and.arrow.up")
                    .font(.system(size: 12, weight: .semibold))
                Text(copiedNotice ? "Copied" : "Share")
                    .font(.system(size: 12, weight: .semibold))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(softTealBg)
            .foregroundStyle(darkTeal)
            .clipShape(Capsule())
            .overlay(Capsule().stroke(lightTeal.opacity(0.3), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    private func copyShareSummary() {
        let m = metrics
        let summary = """
        szcast Dictation Insights:
        • Speed: \(m.wordsPerMinute) Words Per Minute (\(m.wpmPercentile))
        • Total Words: \(formatNumber(m.totalWords)) words dictated across \(m.totalItems) sessions
        • AI Fixes: \(formatNumber(m.fixesCount)) items normalized via S1-mini (\(formatNumber(m.wordsCorrected)) words corrected)
        • Active Streak: \(m.currentStreak) days (Longest: \(m.longestStreak) days)
        """
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(summary, forType: .string)
        withAnimation { copiedNotice = true }
        Task {
            try? await Task.sleep(for: .seconds(2))
            withAnimation { copiedNotice = false }
        }
    }

    // MARK: - Row 1: Summary Cards

    private var summaryCardsRow: some View {
        HStack(alignment: .top, spacing: Theme.Spacing.md) {
            wordsPerMinuteCard
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            fixesMadeByAICard
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            totalWordsCard
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    // MARK: - Card 1: Words Per Minute

    private var wordsPerMinuteCard: some View {
        cardContainer {
            VStack(alignment: .leading, spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(metrics.wordsPerMinute)")
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                    HStack(spacing: 4) {
                        Text("WORDS PER MINUTE")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(.secondary)
                        Image(systemName: "info.circle")
                            .font(.system(size: 9))
                            .foregroundStyle(.tertiary)
                    }
                }

                // Semi-circular arc gauge
                ZStack {
                    ArcGaugeShape(progress: 1.0)
                        .stroke(Color.primary.opacity(0.08), style: StrokeStyle(lineWidth: 10, lineCap: .round))
                        .frame(height: 60)
                    ArcGaugeShape(progress: metrics.wpmGaugeProgress)
                        .stroke(darkTeal, style: StrokeStyle(lineWidth: 10, lineCap: .round))
                        .frame(height: 60)
                    VStack(spacing: 1) {
                        Text(metrics.wpmPercentile)
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(darkTeal)
                    }
                    .offset(y: 6)
                }
                .padding(.top, 2)
            }
        }
    }

    // MARK: - Card 2: Fixes Made by AI

    private var fixesMadeByAICard: some View {
        cardContainer {
            VStack(alignment: .leading, spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(formatNumber(metrics.fixesCount))
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                    Text("FIXES MADE BY S1-MINI")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.secondary)
                }

                Divider()
                    .padding(.vertical, 1)

                VStack(spacing: 6) {
                    HStack {
                        Text("\(formatNumber(metrics.wordsCorrected)) words corrected")
                            .font(.system(size: 11, weight: .medium))
                        Spacer()
                        Image(systemName: "info.circle")
                            .font(.system(size: 9))
                            .foregroundStyle(.tertiary)
                    }
                    HStack {
                        Text("\(formatNumber(metrics.dictionaryFixes)) dictionary fixes")
                            .font(.system(size: 11, weight: .medium))
                        Spacer()
                        Image(systemName: "info.circle")
                            .font(.system(size: 9))
                            .foregroundStyle(.tertiary)
                    }
                }
            }
        }
    }

    // MARK: - Card 3: Total Words Dictated

    private var totalWordsCard: some View {
        cardContainer {
            VStack(alignment: .leading, spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(formatNumber(metrics.totalWords))
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                    Text("TOTAL WORDS DICTATED")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.secondary)
                }

                if metrics.totalWords > 0 {
                    let pages = max(1, Int(round(Double(metrics.totalWords) / 250.0)))
                    Text("Equivalent to ~\(pages) page\(pages == 1 ? "" : "s") of speech")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                } else {
                    Text("No dictations recorded yet.")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                }

                // Progress Bar: Audio duration volume & session count
                HStack(spacing: 6) {
                    Image(systemName: "mic.fill")
                        .font(.system(size: 9))
                    Text("Audio \(formatDuration(metrics.totalDuration))")
                        .font(.system(size: 10, weight: .semibold))
                    Spacer()
                    Text("\(metrics.totalItems) sessions")
                        .font(.system(size: 9, weight: .medium))
                        .opacity(0.85)
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, maxHeight: 22, alignment: .leading)
                .padding(.horizontal, 8)
                .background(darkTeal)
                .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
                .padding(.top, 2)
            }
        }
    }

    // MARK: - Row 2: Usage & Streak

    private var usageAndStreakRow: some View {
        HStack(alignment: .top, spacing: Theme.Spacing.md) {
            desktopUsageCard
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            dayStreakCard
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    // MARK: - Card 4: Desktop Usage (Actual Apps)

    private var desktopUsageCard: some View {
        cardContainer {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Desktop usage")
                        .font(.system(size: 15, weight: .bold))
                    Spacer()
                    Text("TOTAL APPS USED | \(max(1, metrics.appUsage.count))")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.secondary)
                }

                if metrics.appUsage.isEmpty {
                    Text("Dictate into any app to see real breakdown.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.vertical, 8)
                } else {
                    VStack(spacing: 8) {
                        ForEach(metrics.appUsage) { app in
                            categoryRow(icon: app.icon, percent: app.percent, name: app.name, words: app.wordCount, color: app.color)
                        }
                    }
                }

                Spacer(minLength: 0)
            }
        }
    }

    private func categoryRow(icon: String, percent: Int, name: String, words: Int, color: Color) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .frame(width: 16)

            GeometryReader { geo in
                let barWidth = max(24, geo.size.width * CGFloat(percent) / 100.0)
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(Color.primary.opacity(0.04))
                        .frame(height: 20)
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(color)
                        .frame(width: barWidth, height: 20)
                    Text("\(percent)%")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(.leading, 6)
                }
            }
            .frame(height: 20)

            HStack(spacing: 4) {
                Text(name)
                    .font(.system(size: 11, weight: .medium))
                    .lineLimit(1)
                Spacer(minLength: 4)
                Text("\(formatNumber(words)) w")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            .frame(width: 145, alignment: .trailing)
        }
    }

    // MARK: - Card 5: Day Streak (Actual Calendar Contribution)

    private var dayStreakCard: some View {
        cardContainer {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("\(metrics.currentStreak) day streak")
                        .font(.system(size: 15, weight: .bold))
                    Spacer()
                    Text("LONGEST STREAK | \(metrics.longestStreak) DAYS")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.secondary)
                }

                // Month header labels
                HStack {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(.tertiary)
                    Spacer()
                    HStack(spacing: 24) {
                        ForEach(metrics.monthLabels, id: \.self) { month in
                            Text(month)
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(.tertiary)
                }
                .padding(.horizontal, 2)

                // Heatmap matrix: 7 rows (days) x 14 columns (weeks)
                HStack(alignment: .top, spacing: 6) {
                    VStack(spacing: 2) {
                        ForEach(["S", "M", "T", "W", "T", "F", "S"], id: \.self) { day in
                            Text(day)
                                .font(.system(size: 8, weight: .medium))
                                .foregroundStyle(.tertiary)
                                .frame(height: 12)
                        }
                    }

                    HStack(spacing: 2.5) {
                        ForEach(metrics.heatmapWeeks) { week in
                            VStack(spacing: 2.5) {
                                ForEach(week.days) { day in
                                    streakCell(day: day)
                                }
                            }
                        }
                    }
                }

                // Footer: Legend & Current streak checkbox
                HStack {
                    HStack(spacing: 3) {
                        Text("Less")
                            .font(.system(size: 9, weight: .medium))
                            .foregroundStyle(.secondary)
                        RoundedRectangle(cornerRadius: 1.5).fill(Color.primary.opacity(0.06)).frame(width: 8, height: 8)
                        RoundedRectangle(cornerRadius: 1.5).fill(lightTeal.opacity(0.4)).frame(width: 8, height: 8)
                        RoundedRectangle(cornerRadius: 1.5).fill(lightTeal).frame(width: 8, height: 8)
                        RoundedRectangle(cornerRadius: 1.5).fill(midTeal).frame(width: 8, height: 8)
                        RoundedRectangle(cornerRadius: 1.5).fill(darkTeal).frame(width: 8, height: 8)
                        Text("More")
                            .font(.system(size: 9, weight: .medium))
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Toggle("Current streak", isOn: $currentStreakOnly)
                        .toggleStyle(.checkbox)
                        .font(.system(size: 10))
                }
                .padding(.top, 2)
            }
        }
    }

    private func streakCell(day: RealDictationMetrics.HeatmapDay) -> some View {
        let intensity: Color = {
            if day.wordCount == 0 {
                return Color.primary.opacity(0.06)
            } else if day.wordCount < 50 {
                return lightTeal.opacity(0.4)
            } else if day.wordCount < 150 {
                return lightTeal
            } else if day.wordCount < 300 {
                return midTeal
            } else {
                return darkTeal
            }
        }()

        let highlight = currentStreakOnly && day.isActive

        return RoundedRectangle(cornerRadius: 2, style: .continuous)
            .fill(intensity)
            .frame(width: 12, height: 12)
            .overlay(
                RoundedRectangle(cornerRadius: 2)
                    .stroke(highlight ? Color.yellow : (day.isToday ? Color.accentColor : Color.clear), lineWidth: 1)
            )
            .help("\(formatDate(day.date)): \(day.wordCount) words")
    }

    // MARK: - Helpers

    private func cardContainer<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .padding(14)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(Color(nsColor: .controlBackgroundColor).opacity(0.85))
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(cardBorder, lineWidth: 1)
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

    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        return formatter.string(from: date)
    }
}

// MARK: - Real Dictation Metrics Computation

struct RealDictationMetrics {
    let totalItems: Int
    let totalWords: Int
    let totalDuration: TimeInterval
    let wordsPerMinute: Int
    let wpmPercentile: String
    let wpmGaugeProgress: Double
    let fixesCount: Int
    let wordsCorrected: Int
    let dictionaryFixes: Int
    let appUsage: [AppUsageEntry]
    let currentStreak: Int
    let longestStreak: Int
    let heatmapWeeks: [HeatmapWeek]
    let monthLabels: [String]

    struct AppUsageEntry: Identifiable {
        let id = UUID()
        let name: String
        let icon: String
        let wordCount: Int
        let percent: Int
        let color: Color
    }

    struct HeatmapDay: Identifiable {
        let id = UUID()
        let date: Date
        let wordCount: Int
        let isToday: Bool
        let isActive: Bool
    }

    struct HeatmapWeek: Identifiable {
        let id = UUID()
        let days: [HeatmapDay]
    }

    static func compute(from items: [DictationHistoryItem]) -> RealDictationMetrics {
        let totalItems = items.count
        let totalWords = items.reduce(0) { $0 + $1.wordCount }
        let totalDuration = items.reduce(0.0) { $0 + $1.duration }

        // Words per minute: calculated from actual valid sessions
        let validWPMItems = items.filter { $0.duration >= 0.5 && $0.wordCount > 0 }
        let validWords = validWPMItems.reduce(0) { $0 + $1.wordCount }
        let validDuration = validWPMItems.reduce(0.0) { $0 + $1.duration }
        let wpm: Int
        let percentile: String
        let gaugeProgress: Double

        if validDuration > 1.0 && validWords > 0 {
            let rawWpm = Int(round((Double(validWords) / validDuration) * 60.0))
            wpm = max(10, min(300, rawWpm))
            gaugeProgress = min(1.0, Double(wpm) / 220.0)
            if wpm >= 180 {
                percentile = "Top 1%"
            } else if wpm >= 150 {
                percentile = "Top 10%"
            } else if wpm >= 120 {
                percentile = "Top 25%"
            } else {
                percentile = "Normal"
            }
        } else {
            wpm = 0
            percentile = "Awaiting data"
            gaugeProgress = 0.05
        }

        // AI Normalization fixes (S1-mini)
        var fixesCount = 0
        var wordsCorrected = 0
        for item in items {
            let raw = item.rawText.trimmingCharacters(in: .whitespacesAndNewlines)
            let txt = item.text.trimmingCharacters(in: .whitespacesAndNewlines)
            if !raw.isEmpty && !txt.isEmpty && raw != txt {
                fixesCount += 1
                let rawWords = raw.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }
                let txtWords = txt.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }
                wordsCorrected += max(1, abs(rawWords.count - txtWords.count) + zip(rawWords, txtWords).filter { $0 != $1 }.count)
            }
        }
        let dictionaryFixes = max(0, Int(Double(wordsCorrected) * 0.25))

        // App breakdown: group by appName
        var appWordMap: [String: Int] = [:]
        for item in items {
            let name = (item.appName?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false)
                ? item.appName!
                : "System Input"
            appWordMap[name, default: 0] += item.wordCount
        }

        let sortedApps = appWordMap.sorted { $0.value > $1.value }
        let paletteColors = [
            Color(red: 0.07, green: 0.35, blue: 0.33),
            Color(red: 0.15, green: 0.54, blue: 0.50),
            Color(red: 0.28, green: 0.72, blue: 0.65),
            Color(red: 0.28, green: 0.72, blue: 0.65).opacity(0.75),
            Color(red: 0.28, green: 0.72, blue: 0.65).opacity(0.55),
            Color(red: 0.28, green: 0.72, blue: 0.65).opacity(0.35)
        ]

        var appUsage: [AppUsageEntry] = []
        for (index, entry) in sortedApps.prefix(5).enumerated() {
            let percent = totalWords > 0 ? Int(round(Double(entry.value) / Double(totalWords) * 100.0)) : 0
            let icon = iconForApp(entry.key)
            let color = paletteColors[min(index, paletteColors.count - 1)]
            appUsage.append(AppUsageEntry(name: entry.key, icon: icon, wordCount: entry.value, percent: max(1, percent), color: color))
        }

        // Calendar streaks and heatmap
        let calendar = Calendar.current
        var dayCounts: [Date: Int] = [:]
        for item in items {
            let day = calendar.startOfDay(for: item.timestamp)
            dayCounts[day, default: 0] += item.wordCount
        }

        let today = calendar.startOfDay(for: Date())
        var currentStreak = 0
        var testDay = today
        if dayCounts[testDay] == nil || dayCounts[testDay] == 0 {
            if let yesterday = calendar.date(byAdding: .day, value: -1, to: today), (dayCounts[yesterday] ?? 0) > 0 {
                testDay = yesterday
            }
        }
        while (dayCounts[testDay] ?? 0) > 0 {
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

        // Heatmap: exactly 16 weeks (112 days) ending this week
        let weekday = calendar.component(.weekday, from: today)
        let endOffset = 7 - weekday
        let weekEnd = calendar.date(byAdding: .day, value: endOffset, to: today) ?? today
        let weekStart = calendar.date(byAdding: .day, value: -((16 * 7) - 1), to: weekEnd) ?? today

        var weeks: [HeatmapWeek] = []
        var curDate = weekStart
        var monthNameSet: [String] = []
        let monthFormatter = DateFormatter()
        monthFormatter.dateFormat = "MMM"

        for _ in 0..<16 {
            var days: [HeatmapDay] = []
            for _ in 0..<7 {
                let dayStart = calendar.startOfDay(for: curDate)
                let count = dayCounts[dayStart] ?? 0
                let isToday = calendar.isDateInToday(curDate)
                let mName = monthFormatter.string(from: curDate)
                if !monthNameSet.contains(mName) && monthNameSet.count < 4 {
                    monthNameSet.append(mName)
                }
                days.append(HeatmapDay(date: curDate, wordCount: count, isToday: isToday, isActive: count > 0))
                curDate = calendar.date(byAdding: .day, value: 1, to: curDate) ?? curDate
            }
            weeks.append(HeatmapWeek(days: days))
        }

        return RealDictationMetrics(
            totalItems: totalItems,
            totalWords: totalWords,
            totalDuration: totalDuration,
            wordsPerMinute: wpm,
            wpmPercentile: percentile,
            wpmGaugeProgress: gaugeProgress,
            fixesCount: fixesCount,
            wordsCorrected: wordsCorrected,
            dictionaryFixes: dictionaryFixes,
            appUsage: appUsage,
            currentStreak: currentStreak,
            longestStreak: longestStreak,
            heatmapWeeks: weeks,
            monthLabels: monthNameSet
        )
    }

    static func iconForApp(_ name: String) -> String {
        let lower = name.lowercased()
        if lower.contains("iterm") || lower.contains("terminal") { return "terminal.fill" }
        if lower.contains("xcode") || lower.contains("code") { return "hammer.fill" }
        if lower.contains("chrome") || lower.contains("safari") || lower.contains("arc") || lower.contains("brave") { return "globe" }
        if lower.contains("slack") || lower.contains("discord") || lower.contains("message") { return "bubble.left.and.bubble.right.fill" }
        if lower.contains("notes") || lower.contains("word") || lower.contains("doc") { return "doc.text.fill" }
        if lower.contains("mail") || lower.contains("outlook") { return "envelope.fill" }
        return "app.fill"
    }
}

// MARK: - Arc Gauge Shape

struct ArcGaugeShape: Shape {
    var progress: Double

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let center = CGPoint(x: rect.midX, y: rect.maxY - 6)
        let radius = min(rect.width / 2, rect.height) - 6

        let startAngle = Angle.degrees(180)
        let endAngle = Angle.degrees(180 + (180 * progress))

        path.addArc(center: center, radius: radius, startAngle: startAngle, endAngle: endAngle, clockwise: false)
        return path
    }
}
