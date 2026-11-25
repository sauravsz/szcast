import SwiftUI

struct RAMPopoverView: View {
    let ram: RAMStats
    let history: [Double]
    let topProcesses: [SystemProcessInfo]
    let onOpenMonitor: () -> Void
    let onOpenSettings: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            StatsPopoverHeader(
                title: "RAM",
                onOpenMonitor: onOpenMonitor,
                onOpenSettings: onOpenSettings
            )

            gaugesRow

            StatsSectionDivider(title: "Usage history")

            StatsAreaChartView(values: history, maxValue: 100.0, fillColor: StatsPopoverStyle.blue)
                .frame(height: 68)

            StatsSectionDivider(title: "Details")

            StatsKeyValueRow(
                label: "Used:",
                value: StatsFormatting.bytes(ram.usedBytes)
            )

            memorySplitBar
                .padding(.vertical, 3)

            StatsKeyValueRow(
                dotColor: StatsPopoverStyle.blue,
                label: "App:",
                value: StatsFormatting.bytes(ram.appBytes)
            )
            StatsKeyValueRow(
                dotColor: StatsPopoverStyle.orange,
                label: "Wired:",
                value: StatsFormatting.bytes(ram.wiredBytes)
            )
            StatsKeyValueRow(
                dotColor: StatsPopoverStyle.pink,
                label: "Compressed:",
                value: StatsFormatting.bytes(ram.compressedBytes)
            )
            StatsKeyValueRow(
                dotColor: Color.gray.opacity(0.65),
                label: "Free:",
                value: StatsFormatting.bytes(ram.freeBytes)
            )
            StatsKeyValueRow(
                label: "Swap:",
                value: StatsFormatting.bytes(ram.swapUsedBytes)
            )
            StatsKeyValueRow(
                label: "Memory pressure:",
                value: "\(ram.pressurePercentage)%"
            )

            StatsSectionDivider(title: "Top processes")

            HStack {
                Text(verbatim: "Process")
                Spacer()
                Text(verbatim: "Usage")
            }
            .font(.system(size: 11, weight: .regular))
            .foregroundStyle(Theme.Colors.textTertiary)
            .padding(.leading, 22)
            .padding(.bottom, 2)

            ForEach(topProcesses.prefix(8)) { proc in
                StatsProcessRowView(
                    pid: proc.id,
                    name: proc.name,
                    executablePath: proc.executablePath,
                    trailing: StatsFormatting.bytes(proc.memoryBytes)
                )
            }
        }
    }

    private var gaugesRow: some View {
        let total = Double(max(1, ram.totalBytes))
        return HStack(spacing: 24) {
            Spacer()
            RAMPressureGauge(level: ram.pressureLevel, percentage: ram.pressurePercentage)
            StatsDonutRing(
                segments: [
                    StatsDonutSegment(fraction: Double(ram.appBytes) / total, color: StatsPopoverStyle.blue),
                    StatsDonutSegment(fraction: Double(ram.wiredBytes) / total, color: StatsPopoverStyle.orange),
                    StatsDonutSegment(fraction: Double(ram.compressedBytes) / total, color: StatsPopoverStyle.pink)
                ],
                centerText: "\(Int(ram.usagePercentage.rounded()))%",
                diameter: 66,
                lineWidth: 6.5,
                fontSize: 15
            )
            Spacer()
        }
        .padding(.vertical, 4)
    }

    private var memorySplitBar: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let total = Double(max(1, ram.totalBytes))
            let appW = w * CGFloat(Double(ram.appBytes) / total)
            let wiredW = w * CGFloat(Double(ram.wiredBytes) / total)
            let compW = w * CGFloat(Double(ram.compressedBytes) / total)

            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(StatsPopoverStyle.mutedTrack)
                HStack(spacing: 0) {
                    Rectangle().fill(StatsPopoverStyle.blue).frame(width: max(0, appW))
                    Rectangle().fill(StatsPopoverStyle.orange).frame(width: max(0, wiredW))
                    Rectangle().fill(StatsPopoverStyle.pink).frame(width: max(0, compW))
                }
                .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
            }
        }
        .frame(height: 8)
    }
}

private struct RAMPressureGauge: View {
    let level: MemoryPressureLevel
    let percentage: Int

    var body: some View {
        VStack(spacing: 2) {
            ZStack(alignment: .bottom) {
                ArcSegment(startDeg: 180, endDeg: 245)
                    .stroke(StatsPopoverStyle.green, style: StrokeStyle(lineWidth: 5.5, lineCap: .round))
                ArcSegment(startDeg: 248, endDeg: 298)
                    .stroke(StatsPopoverStyle.yellow, style: StrokeStyle(lineWidth: 5.5, lineCap: .butt))
                ArcSegment(startDeg: 301, endDeg: 360)
                    .stroke(StatsPopoverStyle.red, style: StrokeStyle(lineWidth: 5.5, lineCap: .round))

                NeedleShape(angleDegrees: needleAngle)
                    .fill(StatsPopoverStyle.blue)
            }
            .frame(width: 64, height: 34)

            Text(verbatim: level.label)
                .font(.system(size: 10.5, weight: .semibold))
                .foregroundStyle(Theme.Colors.textPrimary)
        }
    }

    private var needleAngle: Double {
        let ratio: Double
        switch level {
        case .normal:
            ratio = min(0.36, max(0.08, Double(percentage) / 160.0))
        case .warning:
            ratio = 0.50
        case .critical:
            ratio = 0.85
        }
        return 180.0 + ratio * 180.0
    }
}

private struct ArcSegment: Shape {
    let startDeg: Double
    let endDeg: Double

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let radius = min(rect.width / 2, rect.height) - 4
        let center = CGPoint(x: rect.midX, y: rect.maxY - 2)
        path.addArc(
            center: center,
            radius: radius,
            startAngle: .degrees(startDeg),
            endAngle: .degrees(endDeg),
            clockwise: false
        )
        return path
    }
}

private struct NeedleShape: Shape {
    let angleDegrees: Double

    func path(in rect: CGRect) -> Path {
        let center = CGPoint(x: rect.midX, y: rect.maxY - 2)
        let length = min(rect.width / 2, rect.height) - 7
        let rad = angleDegrees * .pi / 180.0
        let tip = CGPoint(
            x: center.x + cos(rad) * length,
            y: center.y + sin(rad) * length
        )
        let perp = rad + .pi / 2
        let baseRadius: CGFloat = 2.6
        let p1 = CGPoint(x: center.x + cos(perp) * baseRadius, y: center.y + sin(perp) * baseRadius)
        let p2 = CGPoint(x: center.x - cos(perp) * baseRadius, y: center.y - sin(perp) * baseRadius)

        var path = Path()
        path.move(to: p1)
        path.addLine(to: tip)
        path.addLine(to: p2)
        path.closeSubpath()
        return path
    }
}
