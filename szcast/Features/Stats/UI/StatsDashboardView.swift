import SwiftUI

struct StatsDashboardView: View {
    @Environment(\.metrics) private var metrics
    @Environment(AppSettings.self) private var settings
    var monitor: StatsMonitor = .shared

    var body: some View {
        let snap = monitor.snapshot
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                // Top Row: CPU & Memory
                HStack(alignment: .top, spacing: Theme.Spacing.md) {
                    if settings.statsCPUEnabled {
                        CPUMetricCard(cpu: snap.cpu, history: monitor.cpuHistory)
                    }
                    if settings.statsRAMEnabled {
                        RAMMetricCard(ram: snap.ram, history: monitor.ramHistory)
                    }
                }

                // Middle Row: Disk, Battery & Network
                HStack(alignment: .top, spacing: Theme.Spacing.md) {
                    if settings.statsDiskEnabled {
                        DiskMetricCard(disk: snap.disk)
                    }
                    if settings.statsBatteryEnabled {
                        BatteryMetricCard(battery: snap.battery)
                    }
                    if settings.statsNetworkEnabled {
                        NetworkMetricCard(
                            network: snap.network,
                            downloadHistory: monitor.networkDownloadHistory,
                            uploadHistory: monitor.networkUploadHistory
                        )
                    }
                }

                // Bottom Section: Top Resource Processes
                TopProcessesCard(
                    byCPU: snap.topProcessesByCPU,
                    byRAM: snap.topProcessesByRAM
                )
            }
            .padding(Theme.Spacing.lg)
        }
    }
}

// MARK: - CPU Card

private struct CPUMetricCard: View {
    let cpu: CPUStats
    let history: [Double]

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            HStack {
                Label("CPU", systemImage: "cpu")
                    .font(Theme.Typography.compactKeyCap)
                    .foregroundStyle(Theme.Colors.textSecondary)
                Spacer()
                Text("\(Int(cpu.totalUsage.rounded()))%")
                    .font(Theme.Typography.panelTitle)
                    .fontWeight(.semibold)
                    .foregroundStyle(Theme.Colors.textPrimary)
            }

            // Progress bar
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .fill(Theme.Colors.border)
                        .frame(height: 6)
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .fill(Theme.Colors.accent)
                        .frame(width: max(0, min(geo.size.width, geo.size.width * CGFloat(cpu.totalUsage / 100.0))), height: 6)
                }
            }
            .frame(height: 6)

            // User / System Breakdown
            HStack(spacing: Theme.Spacing.md) {
                Text("User: \(Int(cpu.userPercentage.rounded()))%")
                    .font(Theme.Typography.metaLabel)
                    .foregroundStyle(Theme.Colors.textTertiary)
                Text("System: \(Int(cpu.systemPercentage.rounded()))%")
                    .font(Theme.Typography.metaLabel)
                    .foregroundStyle(Theme.Colors.textTertiary)
                Spacer()
                Text("\(cpu.logicalCores) Cores")
                    .font(Theme.Typography.metaLabel)
                    .foregroundStyle(Theme.Colors.textTertiary)
            }

            // CPU Load Sparkline
            SparklineGraphView(data: history, maxValue: 100.0, strokeColor: Theme.Colors.accent)
                .frame(height: 28)

            // Multi-core Mini Bars
            if !cpu.coreBreakdown.isEmpty {
                HStack(alignment: .bottom, spacing: 2) {
                    ForEach(cpu.coreBreakdown) { core in
                        GeometryReader { g in
                            VStack {
                                Spacer()
                                RoundedRectangle(cornerRadius: 1)
                                    .fill(Theme.Colors.accent.opacity(0.85))
                                    .frame(height: max(2, g.size.height * CGFloat(core.usagePercentage / 100.0)))
                            }
                        }
                        .frame(height: 18)
                    }
                }
                .padding(.top, 2)
            }
        }
        .padding(Theme.Spacing.md)
        .frame(maxWidth: .infinity)
        .background(Theme.Colors.controlSurface)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                .strokeBorder(Theme.Colors.cardStroke, lineWidth: 1)
        )
    }
}

// MARK: - RAM Card

private struct RAMMetricCard: View {
    let ram: RAMStats
    let history: [Double]

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            HStack {
                Label("Memory", systemImage: "memorychip")
                    .font(Theme.Typography.compactKeyCap)
                    .foregroundStyle(Theme.Colors.textSecondary)
                Spacer()
                Text(String(format: "%.1f / %.1f GB", ram.usedGB, ram.totalGB))
                    .font(Theme.Typography.rowTitle)
                    .fontWeight(.semibold)
                    .foregroundStyle(Theme.Colors.textPrimary)
            }

            // Multi-segmented bar (Active, Wired, Compressed)
            GeometryReader { geo in
                let w = geo.size.width
                let activeW = w * CGFloat(Double(ram.activeBytes) / Double(ram.totalBytes))
                let wiredW = w * CGFloat(Double(ram.wiredBytes) / Double(ram.totalBytes))
                let compW = w * CGFloat(Double(ram.compressedBytes) / Double(ram.totalBytes))

                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .fill(Theme.Colors.border)
                        .frame(height: 6)

                    HStack(spacing: 0) {
                        Rectangle().fill(Color.blue).frame(width: max(0, activeW))
                        Rectangle().fill(Color.orange).frame(width: max(0, wiredW))
                        Rectangle().fill(Color.purple).frame(width: max(0, compW))
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 3, style: .continuous))
                    .frame(height: 6)
                }
            }
            .frame(height: 6)

            // Memory Usage Sparkline
            SparklineGraphView(data: history, maxValue: 100.0, strokeColor: Color.blue)
                .frame(height: 28)

            // Legend / breakdown
            HStack(spacing: Theme.Spacing.sm) {
                Text("Active: \(String(format: "%.1f", Double(ram.activeBytes)/1e9))G")
                    .font(Theme.Typography.metaLabel)
                    .foregroundStyle(.blue)
                Text("Wired: \(String(format: "%.1f", Double(ram.wiredBytes)/1e9))G")
                    .font(Theme.Typography.metaLabel)
                    .foregroundStyle(.orange)
                Text("Comp: \(String(format: "%.1f", Double(ram.compressedBytes)/1e9))G")
                    .font(Theme.Typography.metaLabel)
                    .foregroundStyle(.purple)
                Spacer()
                Text("Free: \(String(format: "%.1f", ram.freeGB))G")
                    .font(Theme.Typography.metaLabel)
                    .foregroundStyle(Theme.Colors.textTertiary)
            }
        }
        .padding(Theme.Spacing.md)
        .frame(maxWidth: .infinity)
        .background(Theme.Colors.controlSurface)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                .strokeBorder(Theme.Colors.cardStroke, lineWidth: 1)
        )
    }
}

// MARK: - Disk Card

private struct DiskMetricCard: View {
    let disk: DiskStats

    var body: some View {
        let root = disk.rootVolume
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            HStack {
                Label("Disk", systemImage: "internaldrive")
                    .font(Theme.Typography.compactKeyCap)
                    .foregroundStyle(Theme.Colors.textSecondary)
                Spacer()
                Text(String(format: "%.0f%%", root?.usagePercentage ?? 0))
                    .font(Theme.Typography.rowTitle)
                    .fontWeight(.semibold)
                    .foregroundStyle(Theme.Colors.textPrimary)
            }

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .fill(Theme.Colors.border)
                        .frame(height: 5)
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .fill(Color.teal)
                        .frame(width: max(0, min(geo.size.width, geo.size.width * CGFloat((root?.usagePercentage ?? 0) / 100.0))), height: 5)
                }
            }
            .frame(height: 5)

            HStack {
                Text(String(format: "Free: %.0f GB", Double(root?.freeBytes ?? 0) / 1e9))
                    .font(Theme.Typography.metaLabel)
                    .foregroundStyle(Theme.Colors.textTertiary)
                Spacer()
                Text(String(format: "Total: %.0f GB", Double(root?.totalBytes ?? 0) / 1e9))
                    .font(Theme.Typography.metaLabel)
                    .foregroundStyle(Theme.Colors.textTertiary)
            }
        }
        .padding(Theme.Spacing.md)
        .frame(maxWidth: .infinity)
        .background(Theme.Colors.controlSurface)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                .strokeBorder(Theme.Colors.cardStroke, lineWidth: 1)
        )
    }
}

// MARK: - Battery Card

private struct BatteryMetricCard: View {
    let battery: BatteryStats

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            HStack {
                Label("Battery", systemImage: battery.isCharging ? "bolt.batteryblock" : "battery.100")
                    .font(Theme.Typography.compactKeyCap)
                    .foregroundStyle(Theme.Colors.textSecondary)
                Spacer()
                Text("\(battery.percentage)%")
                    .font(Theme.Typography.rowTitle)
                    .fontWeight(.semibold)
                    .foregroundStyle(Theme.Colors.textPrimary)
            }

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .fill(Theme.Colors.border)
                        .frame(height: 5)
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .fill(battery.percentage < 20 ? Color.red : Color.green)
                        .frame(width: max(0, min(geo.size.width, geo.size.width * CGFloat(Double(battery.percentage) / 100.0))), height: 5)
                }
            }
            .frame(height: 5)

            HStack {
                Text(battery.isCharging ? "Charging" : (battery.isACConnected ? "Power Adapter" : "On Battery"))
                    .font(Theme.Typography.metaLabel)
                    .foregroundStyle(Theme.Colors.textTertiary)
                Spacer()
                Text(battery.health)
                    .font(Theme.Typography.metaLabel)
                    .foregroundStyle(Theme.Colors.textTertiary)
            }
        }
        .padding(Theme.Spacing.md)
        .frame(maxWidth: .infinity)
        .background(Theme.Colors.controlSurface)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                .strokeBorder(Theme.Colors.cardStroke, lineWidth: 1)
        )
    }
}

// MARK: - Network Card

private struct NetworkMetricCard: View {
    let network: NetworkStats
    let downloadHistory: [Double]
    let uploadHistory: [Double]

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            HStack {
                Label("Network", systemImage: "network")
                    .font(Theme.Typography.compactKeyCap)
                    .foregroundStyle(Theme.Colors.textSecondary)
                Spacer()
                Text(network.interfaceName)
                    .font(Theme.Typography.compactKeyCap)
                    .foregroundStyle(Theme.Colors.textSecondary)
            }

            HStack(spacing: Theme.Spacing.md) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("↓ \(formatRate(network.downloadBytesPerSecond))")
                        .font(Theme.Typography.rowTitle)
                        .fontWeight(.semibold)
                        .foregroundStyle(Color.cyan)
                    Text("Download")
                        .font(Theme.Typography.metaLabel)
                        .foregroundStyle(Theme.Colors.textTertiary)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text("↑ \(formatRate(network.uploadBytesPerSecond))")
                        .font(Theme.Typography.rowTitle)
                        .fontWeight(.semibold)
                        .foregroundStyle(Color.mint)
                    Text("Upload")
                        .font(Theme.Typography.metaLabel)
                        .foregroundStyle(Theme.Colors.textTertiary)
                }
            }

            // Dual Download / Upload Sparklines
            HStack(spacing: Theme.Spacing.sm) {
                SparklineGraphView(data: downloadHistory, strokeColor: Color.cyan)
                    .frame(height: 22)
                SparklineGraphView(data: uploadHistory, strokeColor: Color.mint)
                    .frame(height: 22)
            }

            HStack {
                Text(network.localIP)
                    .font(Theme.Typography.metaLabel)
                    .foregroundStyle(Theme.Colors.textTertiary)
                Spacer()
            }
        }
        .padding(Theme.Spacing.md)
        .frame(maxWidth: .infinity)
        .background(Theme.Colors.controlSurface)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                .strokeBorder(Theme.Colors.cardStroke, lineWidth: 1)
        )
    }

    private func formatRate(_ bytesPerSec: Double) -> String {
        if bytesPerSec >= 1_048_576 {
            return String(format: "%.1f MB/s", bytesPerSec / 1_048_576.0)
        } else if bytesPerSec >= 1024 {
            return String(format: "%.0f KB/s", bytesPerSec / 1024.0)
        } else {
            return "0 KB/s"
        }
    }
}

// MARK: - Top Processes Card

private struct TopProcessesCard: View {
    let byCPU: [SystemProcessInfo]
    let byRAM: [SystemProcessInfo]

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            Text("Top Active Processes")
                .font(Theme.Typography.sectionHeader)
                .foregroundStyle(Theme.Colors.textSecondary)

            HStack(alignment: .top, spacing: Theme.Spacing.xl) {
                // By CPU
                VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                    Text("By CPU")
                        .font(Theme.Typography.metaLabel)
                        .foregroundStyle(Theme.Colors.textTertiary)
                        .padding(.bottom, 2)

                    ForEach(byCPU) { proc in
                        HStack {
                            Text(proc.name)
                                .font(Theme.Typography.rowTitle)
                                .lineLimit(1)
                            Spacer()
                            Text(String(format: "%.1f%%", proc.cpuPercentage))
                                .font(Theme.Typography.compactKeyCap)
                                .foregroundStyle(Color.orange)
                        }
                        .padding(.vertical, 2)
                    }
                }
                .frame(maxWidth: .infinity)

                Divider()

                // By RAM
                VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                    Text("By Memory")
                        .font(Theme.Typography.metaLabel)
                        .foregroundStyle(Theme.Colors.textTertiary)
                        .padding(.bottom, 2)

                    ForEach(byRAM) { proc in
                        HStack {
                            Text(proc.name)
                                .font(Theme.Typography.rowTitle)
                                .lineLimit(1)
                            Spacer()
                            Text(String(format: "%.0f MB", proc.memoryMB))
                                .font(Theme.Typography.compactKeyCap)
                                .foregroundStyle(Color.purple)
                        }
                        .padding(.vertical, 2)
                    }
                }
                .frame(maxWidth: .infinity)
            }
        }
        .padding(Theme.Spacing.md)
        .frame(maxWidth: .infinity)
        .background(Theme.Colors.controlSurface)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                .strokeBorder(Theme.Colors.cardStroke, lineWidth: 1)
        )
    }
}

// MARK: - Sparkline Graph Component

struct SparklineGraphView: View {
    let data: [Double]
    var maxValue: Double? = nil
    var strokeColor: Color = Theme.Colors.accent
    var fillColor: Color? = nil

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height

            if data.count >= 2 {
                let maxVal = max(maxValue ?? (data.max() ?? 100.0), 1.0)
                let points = data.enumerated().map { idx, val -> CGPoint in
                    let x = w * CGFloat(idx) / CGFloat(max(1, data.count - 1))
                    let normalized = CGFloat(max(0.0, min(val / maxVal, 1.0)))
                    let y = max(1.0, h - (normalized * (h - 2.0)) - 1.0)
                    return CGPoint(x: x, y: y)
                }

                // Fill gradient area
                Path { path in
                    path.move(to: CGPoint(x: points[0].x, y: h))
                    path.addLine(to: points[0])
                    for i in 1..<points.count {
                        let p0 = points[i - 1]
                        let p1 = points[i]
                        let mid = CGPoint(x: (p0.x + p1.x) / 2, y: (p0.y + p1.y) / 2)
                        path.addQuadCurve(to: mid, control: CGPoint(x: (mid.x + p0.x) / 2, y: p0.y))
                        path.addQuadCurve(to: p1, control: CGPoint(x: (mid.x + p1.x) / 2, y: p1.y))
                    }
                    path.addLine(to: CGPoint(x: points.last!.x, y: h))
                    path.closeSubpath()
                }
                .fill(
                    LinearGradient(
                        colors: [
                            (fillColor ?? strokeColor).opacity(0.25),
                            (fillColor ?? strokeColor).opacity(0.03)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )

                // Smooth Bezier line stroke
                Path { path in
                    path.move(to: points[0])
                    for i in 1..<points.count {
                        let p0 = points[i - 1]
                        let p1 = points[i]
                        let mid = CGPoint(x: (p0.x + p1.x) / 2, y: (p0.y + p1.y) / 2)
                        path.addQuadCurve(to: mid, control: CGPoint(x: (mid.x + p0.x) / 2, y: p0.y))
                        path.addQuadCurve(to: p1, control: CGPoint(x: (mid.x + p1.x) / 2, y: p1.y))
                    }
                }
                .stroke(strokeColor, style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
            } else {
                // Subtle dashed baseline placeholder
                Path { path in
                    path.move(to: CGPoint(x: 0, y: h - 1))
                    path.addLine(to: CGPoint(x: w, y: h - 1))
                }
                .stroke(Theme.Colors.border, style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
            }
        }
    }
}
