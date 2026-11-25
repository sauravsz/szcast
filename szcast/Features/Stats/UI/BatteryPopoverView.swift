import SwiftUI

struct BatteryPopoverView: View {
    let battery: BatteryStats
    let topProcesses: [SystemProcessInfo]
    let onOpenMonitor: () -> Void
    let onOpenSettings: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            StatsPopoverHeader(
                title: "Battery",
                onOpenMonitor: onOpenMonitor,
                onOpenSettings: onOpenSettings
            )

            HStack(spacing: 22) {
                Spacer()
                StatsDonutRing(
                    segments: [
                        StatsDonutSegment(
                            fraction: Double(battery.percentage) / 100.0,
                            color: batteryColor
                        )
                    ],
                    centerText: battery.hasBattery ? "\(battery.percentage)%" : "AC",
                    diameter: 66,
                    lineWidth: 6.5,
                    fontSize: 15
                )
                VStack(alignment: .leading, spacing: 3) {
                    Text(verbatim: statusText)
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundStyle(Theme.Colors.textPrimary)
                    if let watts = battery.powerWatts {
                        Text(verbatim: String(format: "%.1f W", abs(watts)))
                            .font(.system(size: 11.5, weight: .medium))
                            .monospacedDigit()
                            .foregroundStyle(Theme.Colors.textSecondary)
                    }
                }
                Spacer()
            }
            .padding(.vertical, 4)

            StatsSectionDivider(title: "Details")

            StatsKeyValueRow(
                label: "Power source:",
                value: battery.isACConnected ? "Power Adapter" : "Battery"
            )
            StatsKeyValueRow(label: "Status:", value: statusText)
            if let mins = battery.timeRemainingMinutes {
                StatsKeyValueRow(
                    label: battery.isCharging ? "Time to full:" : "Time remaining:",
                    value: StatsFormatting.durationMinutes(mins)
                )
            }
            if let cycles = battery.cycleCount {
                StatsKeyValueRow(label: "Cycle count:", value: "\(cycles)")
            }
            let healthLabel = battery.healthPercentage.map { "\($0)% (\(battery.health))" } ?? battery.health
            StatsKeyValueRow(label: "Health:", value: healthLabel)

            if let cur = battery.currentCapacityMAh, let maxCap = battery.maxCapacityMAh {
                StatsKeyValueRow(label: "Capacity:", value: "\(cur) / \(maxCap) mAh")
            }
            if let voltage = battery.voltageMillivolts {
                StatsKeyValueRow(label: "Voltage:", value: String(format: "%.2f V", Double(voltage) / 1000.0))
            }
            if let amps = battery.amperageMilliamps {
                StatsKeyValueRow(label: "Amperage:", value: "\(amps) mA")
            }
            if let temp = battery.temperature {
                StatsKeyValueRow(label: "Temperature:", value: String(format: "%.1f °C", temp))
            }
            if let adapter = battery.adapterWatts {
                StatsKeyValueRow(label: "Power adapter:", value: "\(adapter) W")
            }

            if !topProcesses.isEmpty {
                StatsSectionDivider(title: "Top processes")
                HStack {
                    Text(verbatim: "Process")
                    Spacer()
                    Text(verbatim: "CPU")
                }
                .font(.system(size: 11))
                .foregroundStyle(Theme.Colors.textTertiary)
                .padding(.leading, 22)
                .padding(.bottom, 2)

                ForEach(topProcesses.prefix(5)) { proc in
                    StatsProcessRowView(
                        pid: proc.id,
                        name: proc.name,
                        executablePath: proc.executablePath,
                        trailing: String(format: "%.1f%%", proc.cpuPercentage)
                    )
                }
            }
        }
    }

    private var batteryColor: Color {
        if battery.isCharging { return StatsPopoverStyle.green }
        if battery.percentage <= 15 { return StatsPopoverStyle.red }
        if battery.percentage <= 30 { return StatsPopoverStyle.orange }
        return StatsPopoverStyle.green
    }

    private var statusText: String {
        if !battery.hasBattery { return "Power Adapter" }
        if battery.isCharging { return "Charging" }
        if battery.isACConnected && battery.percentage >= 99 { return "Charged" }
        if battery.isACConnected { return "Not Charging" }
        return "Discharging"
    }
}
