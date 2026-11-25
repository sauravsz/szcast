import SwiftUI

struct DiskPopoverView: View {
    let disk: DiskStats
    let readHistory: [Double]
    let writeHistory: [Double]
    let onOpenMonitor: () -> Void
    let onOpenSettings: () -> Void

    var body: some View {
        let root = disk.rootVolume
        let usedPct = root?.usagePercentage ?? 0

        VStack(alignment: .leading, spacing: 4) {
            StatsPopoverHeader(
                title: "Disk",
                onOpenMonitor: onOpenMonitor,
                onOpenSettings: onOpenSettings
            )

            HStack(spacing: 20) {
                Spacer()
                StatsDonutRing(
                    segments: [
                        StatsDonutSegment(fraction: usedPct / 100.0, color: StatsPopoverStyle.teal)
                    ],
                    centerText: "\(Int(usedPct.rounded()))%",
                    diameter: 66,
                    lineWidth: 6.5,
                    fontSize: 15
                )
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 5) {
                        StatsColorSquare(color: StatsPopoverStyle.blue)
                        Text(verbatim: "Read: \(StatsFormatting.speed(disk.readBytesPerSecond))")
                            .font(.system(size: 11.5, weight: .medium))
                            .monospacedDigit()
                            .foregroundStyle(Theme.Colors.textPrimary)
                    }
                    HStack(spacing: 5) {
                        StatsColorSquare(color: StatsPopoverStyle.red)
                        Text(verbatim: "Write: \(StatsFormatting.speed(disk.writeBytesPerSecond))")
                            .font(.system(size: 11.5, weight: .medium))
                            .monospacedDigit()
                            .foregroundStyle(Theme.Colors.textPrimary)
                    }
                }
                Spacer()
            }
            .padding(.vertical, 4)

            StatsSectionDivider(title: "Throughput history")

            let peak = max(readHistory.max() ?? 1024, writeHistory.max() ?? 1024, 1024)
            HStack(spacing: 6) {
                StatsAreaChartView(values: readHistory, maxValue: peak, fillColor: StatsPopoverStyle.blue)
                    .frame(height: 52)
                StatsAreaChartView(values: writeHistory, maxValue: peak, fillColor: StatsPopoverStyle.red)
                    .frame(height: 52)
            }

            StatsSectionDivider(title: "Details")

            StatsKeyValueRow(
                dotColor: StatsPopoverStyle.blue,
                label: "Total read:",
                value: StatsFormatting.bytes(disk.totalReadBytes)
            )
            StatsKeyValueRow(
                dotColor: StatsPopoverStyle.red,
                label: "Total written:",
                value: StatsFormatting.bytes(disk.totalWriteBytes)
            )

            StatsSectionDivider(title: "Volumes")

            ForEach(disk.volumes) { vol in
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(verbatim: vol.name)
                            .font(.system(size: 11.5, weight: .medium))
                            .foregroundStyle(Theme.Colors.textPrimary)
                        Spacer()
                        Text(verbatim: "\(Int(vol.usagePercentage.rounded()))%")
                            .font(.system(size: 11.5, weight: .medium))
                            .monospacedDigit()
                            .foregroundStyle(Theme.Colors.textPrimary)
                    }
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 3, style: .continuous)
                                .fill(StatsPopoverStyle.mutedTrack)
                            RoundedRectangle(cornerRadius: 3, style: .continuous)
                                .fill(StatsPopoverStyle.teal)
                                .frame(width: max(0, geo.size.width * CGFloat(min(1, max(0, vol.usagePercentage / 100.0)))))
                        }
                    }
                    .frame(height: 6)

                    HStack {
                        Text(verbatim: "\(StatsFormatting.bytes(UInt64(max(0, vol.freeBytes)))) free")
                        Spacer()
                        Text(verbatim: "\(StatsFormatting.bytes(UInt64(max(0, vol.totalBytes)))) total")
                    }
                    .font(.system(size: 10.5))
                    .foregroundStyle(Theme.Colors.textTertiary)
                }
                .padding(.vertical, 3)
            }
        }
    }
}
