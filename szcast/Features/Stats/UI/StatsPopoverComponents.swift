import SwiftUI
import AppKit

enum StatsPopoverStyle {
    static let width: CGFloat = 290
    static let cornerRadius: CGFloat = 12
    static let horizontalPadding: CGFloat = 12
    static let verticalPadding: CGFloat = 10

    static let blue = Color(red: 0.08, green: 0.50, blue: 0.98)
    static let red = Color(red: 0.96, green: 0.27, blue: 0.25)
    static let orange = Color(red: 0.98, green: 0.58, blue: 0.16)
    static let pink = Color(red: 0.96, green: 0.24, blue: 0.44)
    static let teal = Color(red: 0.14, green: 0.78, blue: 0.76)
    static let indigo = Color(red: 0.41, green: 0.42, blue: 0.88)
    static let green = Color(red: 0.19, green: 0.82, blue: 0.35)
    static let yellow = Color(red: 1.00, green: 0.80, blue: 0.00)
    static let mutedTrack = Theme.Colors.ramp(dark: 0.14, light: 0.12)
    static let chartSurface = Theme.Colors.adaptive(
        dark: .srgbInk(0.11, alpha: 0.85),
        light: .srgbInk(0.92, alpha: 0.85)
    )
    static let surfaceBackground = Theme.Colors.adaptive(
        dark: NSColor(srgbRed: 0.135, green: 0.138, blue: 0.145, alpha: 0.96),
        light: NSColor(srgbRed: 0.97, green: 0.97, blue: 0.98, alpha: 0.96)
    )
}

struct StatsPopoverHeader: View {
    let title: String
    let onOpenMonitor: () -> Void
    let onOpenSettings: () -> Void

    var body: some View {
        HStack {
            Button(action: onOpenMonitor) {
                Image(systemName: "chart.bar.fill")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .frame(width: 24, height: 24)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Open Activity Monitor")
            .accessibilityLabel("Open Activity Monitor")

            Spacer()

            Text(verbatim: title)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Theme.Colors.textPrimary)

            Spacer()

            Button(action: onOpenSettings) {
                Image(systemName: "command")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .frame(width: 24, height: 24)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("System Stats Settings")
            .accessibilityLabel("System Stats Settings")
        }
        .padding(.bottom, 6)
    }
}

struct StatsSectionDivider: View {
    let title: String
    var accessorySymbol: String? = nil
    var accessoryHelp: String? = nil
    var onAccessory: (() -> Void)? = nil

    var body: some View {
        HStack(spacing: 8) {
            dividerLine
            Text(verbatim: title.uppercased())
                .font(.system(size: 10, weight: .semibold))
                .tracking(0.6)
                .foregroundStyle(Theme.Colors.textTertiary)
                .fixedSize()
            dividerLine
            if let accessorySymbol, let onAccessory {
                Button(action: onAccessory) {
                    Image(systemName: accessorySymbol)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Theme.Colors.textSecondary)
                        .frame(width: 18, height: 18)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(accessoryHelp ?? "")
            }
        }
        .padding(.top, 8)
        .padding(.bottom, 4)
    }

    private var dividerLine: some View {
        Rectangle()
            .fill(Theme.Colors.separator)
            .frame(height: 1)
    }
}

struct StatsColorSquare: View {
    let color: Color

    var body: some View {
        RoundedRectangle(cornerRadius: 2.5, style: .continuous)
            .fill(color)
            .frame(width: 9, height: 9)
    }
}

struct StatsKeyValueRow: View {
    var dotColor: Color? = nil
    let label: String
    let value: String

    var body: some View {
        HStack(spacing: 6) {
            if let dotColor {
                StatsColorSquare(color: dotColor)
            }
            Text(verbatim: label)
                .font(.system(size: 11.5, weight: .regular))
                .foregroundStyle(Theme.Colors.textSecondary)
                .lineLimit(1)
            Spacer(minLength: 8)
            Text(verbatim: value)
                .font(.system(size: 11.5, weight: .medium))
                .monospacedDigit()
                .foregroundStyle(Theme.Colors.textPrimary)
                .lineLimit(1)
        }
        .padding(.vertical, 1.5)
    }
}

struct StatsAreaChartView: View {
    let values: [Double]
    var maxValue: Double = 100.0
    var fillColor: Color = StatsPopoverStyle.blue

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            let cap = max(maxValue, 1.0)
            let count = max(values.count, 2)

            ZStack {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(StatsPopoverStyle.chartSurface)

                if values.count >= 2 {
                    let points: [CGPoint] = values.enumerated().map { idx, raw in
                        let x = w * CGFloat(idx) / CGFloat(count - 1)
                        let norm = CGFloat(min(1.0, max(0.0, raw / cap)))
                        let y = h - (norm * (h - 4))
                        return CGPoint(x: x, y: y)
                    }

                    Path { path in
                        path.move(to: CGPoint(x: points[0].x, y: h))
                        path.addLine(to: points[0])
                        for p in points.dropFirst() {
                            path.addLine(to: p)
                        }
                        path.addLine(to: CGPoint(x: points[points.count - 1].x, y: h))
                        path.closeSubpath()
                    }
                    .fill(fillColor.opacity(0.85))
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))

                    Path { path in
                        path.move(to: points[0])
                        for p in points.dropFirst() {
                            path.addLine(to: p)
                        }
                    }
                    .stroke(fillColor, lineWidth: 1.2)
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                }
            }
        }
    }
}

struct StatsDonutSegment {
    let fraction: Double
    let color: Color
}

struct StatsDonutRing: View {
    let segments: [StatsDonutSegment]
    let centerText: String
    var diameter: CGFloat = 56
    var lineWidth: CGFloat = 6
    var fontSize: CGFloat = 14

    var body: some View {
        ZStack {
            Circle()
                .stroke(StatsPopoverStyle.mutedTrack, lineWidth: lineWidth)

            ForEach(Array(segmentsWithOffsets().enumerated()), id: \.offset) { _, item in
                Circle()
                    .trim(from: item.start, to: item.end)
                    .stroke(
                        item.color,
                        style: StrokeStyle(lineWidth: lineWidth, lineCap: .butt)
                    )
                    .rotationEffect(.degrees(-90))
            }

            Text(verbatim: centerText)
                .font(.system(size: fontSize, weight: .medium))
                .monospacedDigit()
                .foregroundStyle(Theme.Colors.textPrimary)
        }
        .frame(width: diameter, height: diameter)
    }

    private func segmentsWithOffsets() -> [(start: CGFloat, end: CGFloat, color: Color)] {
        var cursor: CGFloat = 0
        var out: [(CGFloat, CGFloat, Color)] = []
        for seg in segments {
            let clamped = max(0, min(1.0 - Double(cursor), seg.fraction))
            guard clamped > 0.002 else { continue }
            let end = cursor + CGFloat(clamped)
            out.append((cursor, end, seg.color))
            cursor = end
        }
        return out
    }
}

struct StatsProcessRowView: View {
    let pid: Int32
    let name: String
    let executablePath: String?
    let trailing: String

    var body: some View {
        HStack(spacing: 7) {
            Image(nsImage: StatsProcessIconCache.shared.icon(forPID: pid, executablePath: executablePath))
                .resizable()
                .interpolation(.high)
                .frame(width: 15, height: 15)
            Text(verbatim: name)
                .font(.system(size: 11.5, weight: .regular))
                .foregroundStyle(Theme.Colors.textPrimary)
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: 6)
            Text(verbatim: trailing)
                .font(.system(size: 11.5, weight: .medium))
                .monospacedDigit()
                .foregroundStyle(Theme.Colors.textPrimary)
                .lineLimit(1)
        }
        .padding(.vertical, 1.5)
    }
}

struct StatsStatusBadge: View {
    let text: String
    let isGood: Bool

    var body: some View {
        Text(verbatim: text)
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(Color.white)
            .padding(.horizontal, 12)
            .padding(.vertical, 2)
            .background(
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(isGood ? StatsPopoverStyle.green : StatsPopoverStyle.red)
            )
    }
}
