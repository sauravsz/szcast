import SwiftUI
import AppKit

struct NetworkPopoverView: View {
    let network: NetworkStats
    let downloadHistory: [Double]
    let uploadHistory: [Double]
    let topProcesses: [NetworkProcessInfo]
    let onOpenMonitor: () -> Void
    let onOpenSettings: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            StatsPopoverHeader(
                title: "Network",
                onOpenMonitor: onOpenMonitor,
                onOpenSettings: onOpenSettings
            )

            topSpeedsRow

            StatsSectionDivider(title: "Usage history")

            NetworkMirroredChart(downloads: downloadHistory, uploads: uploadHistory)
                .frame(height: 74)

            StatsSectionDivider(title: "Top processes")

            HStack(spacing: 6) {
                Text(verbatim: "Process")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.Colors.textTertiary)
                    .padding(.leading, 22)
                Spacer()
                StatsColorSquare(color: StatsPopoverStyle.blue)
                    .frame(width: 58, alignment: .trailing)
                StatsColorSquare(color: StatsPopoverStyle.red)
                    .frame(width: 54, alignment: .trailing)
            }
            .padding(.bottom, 2)

            ForEach(topProcesses.prefix(8)) { proc in
                HStack(spacing: 6) {
                    Image(nsImage: StatsProcessIconCache.shared.icon(
                        forPID: proc.id,
                        executablePath: proc.executablePath
                    ))
                    .resizable()
                    .interpolation(.high)
                    .frame(width: 15, height: 15)

                    Text(verbatim: proc.name)
                        .font(.system(size: 11.5))
                        .foregroundStyle(Theme.Colors.textPrimary)
                        .lineLimit(1)
                        .truncationMode(.tail)

                    Spacer(minLength: 4)

                    Text(verbatim: StatsFormatting.speed(proc.downloadBytesPerSecond))
                        .font(.system(size: 11, weight: .medium))
                        .monospacedDigit()
                        .foregroundStyle(Theme.Colors.textPrimary)
                        .frame(width: 58, alignment: .trailing)
                        .lineLimit(1)

                    Text(verbatim: StatsFormatting.speed(proc.uploadBytesPerSecond))
                        .font(.system(size: 11, weight: .medium))
                        .monospacedDigit()
                        .foregroundStyle(Theme.Colors.textPrimary)
                        .frame(width: 54, alignment: .trailing)
                        .lineLimit(1)
                }
                .padding(.vertical, 1.5)
            }
        }
    }

    private var topSpeedsRow: some View {
        let down = StatsFormatting.speedParts(network.downloadBytesPerSecond)
        let up = StatsFormatting.speedParts(network.uploadBytesPerSecond)

        return HStack(spacing: 0) {
            speedColumn(value: down.value, unit: down.unit, color: StatsPopoverStyle.blue, label: "Download")
            speedColumn(value: up.value, unit: up.unit, color: StatsPopoverStyle.red, label: "Upload")
        }
        .padding(.vertical, 4)
    }

    private func speedColumn(value: String, unit: String, color: Color, label: String) -> some View {
        VStack(spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(verbatim: value)
                    .font(.system(size: 22, weight: .regular))
                    .monospacedDigit()
                    .foregroundStyle(Theme.Colors.textPrimary)
                Text(verbatim: unit)
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(Theme.Colors.textPrimary)
            }
            HStack(spacing: 5) {
                StatsColorSquare(color: color)
                Text(verbatim: label)
                    .font(.system(size: 11.5, weight: .regular))
                    .foregroundStyle(Theme.Colors.textSecondary)
            }
        }
        .frame(maxWidth: .infinity)
    }
}

private struct NetworkMirroredChart: View {
    let downloads: [Double]
    let uploads: [Double]

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            let midY = h / 2
            let maxDown = max(downloads.max() ?? 1024, 1024)
            let maxUp = max(uploads.max() ?? 1024, 1024)
            let peakMax = max(maxDown, maxUp)

            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(StatsPopoverStyle.chartSurface)

                Rectangle()
                    .fill(Theme.Colors.separator)
                    .frame(height: 1)
                    .position(x: w / 2, y: midY)

                if uploads.count >= 2 {
                    mirroredPath(values: uploads, maxVal: peakMax, width: w, midY: midY, upward: true)
                        .fill(StatsPopoverStyle.red.opacity(0.65))
                    mirroredStroke(values: uploads, maxVal: peakMax, width: w, midY: midY, upward: true)
                        .stroke(StatsPopoverStyle.red, lineWidth: 1.1)
                }

                if downloads.count >= 2 {
                    mirroredPath(values: downloads, maxVal: peakMax, width: w, midY: midY, upward: false)
                        .fill(StatsPopoverStyle.blue.opacity(0.65))
                    mirroredStroke(values: downloads, maxVal: peakMax, width: w, midY: midY, upward: false)
                        .stroke(StatsPopoverStyle.blue, lineWidth: 1.1)
                }

                VStack(alignment: .leading) {
                    Text(verbatim: StatsFormatting.speed(maxUp))
                    Spacer()
                    Text(verbatim: StatsFormatting.speed(maxDown))
                }
                .font(.system(size: 9.5, weight: .medium))
                .monospacedDigit()
                .foregroundStyle(Theme.Colors.textPrimary.opacity(0.9))
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
            }
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        }
    }

    private func mirroredPath(
        values: [Double], maxVal: Double, width: CGFloat, midY: CGFloat, upward: Bool
    ) -> Path {
        var path = Path()
        let count = max(values.count, 2)
        path.move(to: CGPoint(x: 0, y: midY))
        for (idx, val) in values.enumerated() {
            let x = width * CGFloat(idx) / CGFloat(count - 1)
            let mag = CGFloat(min(1.0, max(0.0, val / maxVal))) * (midY - 3)
            let y = upward ? (midY - mag) : (midY + mag)
            path.addLine(to: CGPoint(x: x, y: y))
        }
        path.addLine(to: CGPoint(x: width, y: midY))
        path.closeSubpath()
        return path
    }

    private func mirroredStroke(
        values: [Double], maxVal: Double, width: CGFloat, midY: CGFloat, upward: Bool
    ) -> Path {
        var path = Path()
        let count = max(values.count, 2)
        for (idx, val) in values.enumerated() {
            let x = width * CGFloat(idx) / CGFloat(count - 1)
            let mag = CGFloat(min(1.0, max(0.0, val / maxVal))) * (midY - 3)
            let y = upward ? (midY - mag) : (midY + mag)
            if idx == 0 { path.move(to: CGPoint(x: x, y: y)) }
            else { path.addLine(to: CGPoint(x: x, y: y)) }
        }
        return path
    }
}
