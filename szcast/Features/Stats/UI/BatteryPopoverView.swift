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
                        Text(verbatim: String(format: "%.2f W", abs(watts)))
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
            StatsKeyValueRow(label: "Status:", value: detailStatusValue)
            if let mins = battery.timeRemainingMinutes {
                StatsKeyValueRow(
                    label: battery.isCharging ? "Time to full:" : "Time remaining:",
                    value: StatsFormatting.durationMinutes(mins)
                )
            }
            if let cur = battery.currentCapacityMAh {
                StatsKeyValueRow(label: "Current charge:", value: "\(cur) mAh")
            }

            if battery.hasBattery {
                StatsSectionDivider(title: "Battery")

                if let maxCap = battery.maxCapacityMAh, let designCap = battery.designCapacityMAh, designCap > 0 {
                    capacityComparisonBar(maxCap: maxCap, designCap: designCap)
                        .padding(.bottom, 4)
                }

                if let watts = battery.powerWatts {
                    StatsKeyValueRow(label: "Power:", value: String(format: "%.2f W", abs(watts)))
                }
                if let amps = battery.amperageMilliamps {
                    StatsKeyValueRow(label: "Amperage:", value: "\(amps) mA")
                }
                if let voltage = battery.voltageMillivolts {
                    StatsKeyValueRow(label: "Voltage:", value: String(format: "%.2f V", Double(voltage) / 1000.0))
                }
                let healthLabel = battery.healthPercentage.map { "\($0)% (\(battery.health))" } ?? battery.health
                StatsKeyValueRow(label: "Health:", value: healthLabel)
                if let cycles = battery.cycleCount {
                    StatsKeyValueRow(label: "Cycles:", value: "\(cycles)")
                }
                if let temp = battery.temperature {
                    StatsKeyValueRow(label: "Temperature:", value: String(format: "%.1f °C", temp))
                }
            }

            if battery.isACConnected,
               battery.adapterWatts != nil || battery.adapterPowerWatts != nil || battery.adapterVoltageVolts != nil {
                StatsSectionDivider(title: "Power adapter")
                if let rated = battery.adapterWatts {
                    if let draw = battery.adapterPowerWatts, draw > 0 {
                        StatsKeyValueRow(label: "Power:", value: String(format: "%.2f W / %d W", draw, rated))
                    } else {
                        StatsKeyValueRow(label: "Power:", value: "\(rated) W")
                    }
                } else if let draw = battery.adapterPowerWatts {
                    StatsKeyValueRow(label: "Power:", value: String(format: "%.2f W", draw))
                }
                if let volts = battery.adapterVoltageVolts {
                    StatsKeyValueRow(label: "Voltage:", value: String(format: "%.2f V", volts))
                }
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
        if battery.isCharged || (battery.isACConnected && battery.percentage >= 99) { return "Charged" }
        if battery.isACConnected { return "Not Charging" }
        return "Discharging"
    }

    private var detailStatusValue: String {
        if battery.optimizedChargingEngaged { return "On hold" }
        if battery.isCharged { return "Fully charged" }
        return statusText
    }

    private func capacityComparisonBar(maxCap: Int, designCap: Int) -> some View {
        let ratio = max(0.0, min(1.0, Double(maxCap) / Double(designCap)))
        return VStack(alignment: .leading, spacing: 4) {
            HStack {
                VStack(alignment: .leading, spacing: 1) {
                    Text(verbatim: "Max capacity")
                        .font(.system(size: 10))
                        .foregroundStyle(Theme.Colors.textTertiary)
                    Text(verbatim: "\(maxCap) mAh")
                        .font(.system(size: 12, weight: .medium))
                        .monospacedDigit()
                        .foregroundStyle(Theme.Colors.textPrimary)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 1) {
                    Text(verbatim: "Designed capacity")
                        .font(.system(size: 10))
                        .foregroundStyle(Theme.Colors.textTertiary)
                    Text(verbatim: "\(designCap) mAh")
                        .font(.system(size: 12, weight: .medium))
                        .monospacedDigit()
                        .foregroundStyle(Theme.Colors.textPrimary)
                }
            }

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(StatsPopoverStyle.mutedTrack)
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(StatsPopoverStyle.green)
                        .frame(width: max(0, geo.size.width * CGFloat(ratio)))
                }
            }
            .frame(height: 8)
        }
    }
}
