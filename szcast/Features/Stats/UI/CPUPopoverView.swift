import SwiftUI

struct CPUPopoverView: View {
    let cpu: CPUStats
    let history: [Double]
    let topProcesses: [SystemProcessInfo]
    let onOpenMonitor: () -> Void
    let onOpenSettings: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            StatsPopoverHeader(
                title: "CPU",
                onOpenMonitor: onOpenMonitor,
                onOpenSettings: onOpenSettings
            )

            gaugesRow

            StatsSectionDivider(title: "Usage history")

            StatsAreaChartView(values: history, maxValue: 100.0, fillColor: StatsPopoverStyle.blue)
                .frame(height: 54)

            if !cpu.coreBreakdown.isEmpty {
                coreBarsRow
            }

            StatsSectionDivider(title: "Details")

            StatsKeyValueRow(
                dotColor: StatsPopoverStyle.red,
                label: "System:",
                value: "\(Int(cpu.systemPercentage.rounded()))%"
            )
            StatsKeyValueRow(
                dotColor: StatsPopoverStyle.blue,
                label: "User:",
                value: "\(Int(cpu.userPercentage.rounded()))%"
            )
            StatsKeyValueRow(
                dotColor: Color.gray.opacity(0.65),
                label: "Idle:",
                value: "\(Int(cpu.idlePercentage.rounded()))%"
            )
            if let eff = cpu.efficiencyUsage {
                StatsKeyValueRow(
                    dotColor: StatsPopoverStyle.teal,
                    label: "Efficiency cores:",
                    value: "\(Int(eff.rounded()))%"
                )
            }
            if let perf = cpu.performanceUsage {
                StatsKeyValueRow(
                    dotColor: StatsPopoverStyle.indigo,
                    label: "Performance cores:",
                    value: "\(Int(perf.rounded()))%"
                )
            }
            StatsKeyValueRow(
                label: "Uptime:",
                value: StatsFormatting.uptime(cpu.uptimeSeconds)
            )

            StatsSectionDivider(title: "Average load")

            StatsKeyValueRow(label: "1 minute:", value: String(format: "%.2f", cpu.loadAverage1m))
            StatsKeyValueRow(label: "5 minutes:", value: String(format: "%.2f", cpu.loadAverage5m))
            StatsKeyValueRow(label: "15 minutes:", value: String(format: "%.2f", cpu.loadAverage15m))

            if let allMHz = cpu.allCoresFrequencyMHz {
                StatsSectionDivider(title: "Frequency")
                StatsKeyValueRow(label: "All cores:", value: "\(allMHz) MHz")
                if let eMHz = cpu.efficiencyFrequencyMHz {
                    StatsKeyValueRow(
                        dotColor: StatsPopoverStyle.teal,
                        label: "Efficiency cores:",
                        value: "\(eMHz) MHz"
                    )
                }
                if let pMHz = cpu.performanceFrequencyMHz {
                    StatsKeyValueRow(
                        dotColor: StatsPopoverStyle.indigo,
                        label: "Performance cores:",
                        value: "\(pMHz) MHz"
                    )
                }
            }

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
                    trailing: String(format: "%.1f%%", proc.cpuPercentage)
                )
            }
        }
    }

    private var gaugesRow: some View {
        HStack(spacing: 20) {
            Spacer()
            StatsDonutRing(
                segments: [
                    StatsDonutSegment(fraction: cpu.systemPercentage / 100.0, color: StatsPopoverStyle.red),
                    StatsDonutSegment(fraction: cpu.userPercentage / 100.0, color: StatsPopoverStyle.blue)
                ],
                centerText: "\(Int(cpu.totalUsage.rounded()))%",
                diameter: 66,
                lineWidth: 6.5,
                fontSize: 15
            )
            if let allMHz = cpu.allCoresFrequencyMHz {
                let maxMHz = Double(max(cpu.performanceFrequencyMHz ?? 3200, allMHz, 3200))
                StatsDonutRing(
                    segments: [
                        StatsDonutSegment(
                            fraction: min(1.0, Double(allMHz) / maxMHz),
                            color: StatsPopoverStyle.blue
                        )
                    ],
                    centerText: String(format: "%.2f", Double(allMHz) / 1000.0),
                    diameter: 46,
                    lineWidth: 5,
                    fontSize: 10.5
                )
            }
            Spacer()
        }
        .padding(.vertical, 4)
    }

    private var coreBarsRow: some View {
        HStack(spacing: 3) {
            ForEach(cpu.coreBreakdown) { core in
                GeometryReader { geo in
                    let h = geo.size.height
                    let fillHeight = max(2, h * CGFloat(min(100, max(0, core.usagePercentage)) / 100.0))
                    let barColor = core.isEfficiency ? StatsPopoverStyle.teal : StatsPopoverStyle.indigo
                    ZStack(alignment: .bottom) {
                        RoundedRectangle(cornerRadius: 2.5, style: .continuous)
                            .fill(StatsPopoverStyle.chartSurface)
                        RoundedRectangle(cornerRadius: 2.5, style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: [barColor, barColor.opacity(0.82)],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )
                            .frame(height: fillHeight)
                    }
                }
                .frame(height: 30)
            }
        }
        .padding(.top, 2)
    }
}
