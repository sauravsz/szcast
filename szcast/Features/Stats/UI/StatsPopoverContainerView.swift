import SwiftUI
import AppKit

struct StatsPopoverContainerView: View {
    let module: StatsModule
    var monitor: StatsMonitor = .shared
    let maxHeight: CGFloat
    let onContentHeightChange: (CGFloat) -> Void
    let onOpenMonitor: () -> Void
    let onOpenSettings: () -> Void

    @State private var measuredHeight: CGFloat = 460

    var body: some View {
        let snap = monitor.snapshot
        let needsScroll = measuredHeight > maxHeight

        ScrollView(.vertical) {
            moduleBody(snap: snap)
                .padding(.horizontal, StatsPopoverStyle.horizontalPadding)
                .padding(.vertical, StatsPopoverStyle.verticalPadding)
                .frame(width: StatsPopoverStyle.width, alignment: .leading)
                .onGeometryChange(for: CGFloat.self) { proxy in
                    ceil(proxy.size.height)
                } action: { newHeight in
                    if newHeight > 0, abs(newHeight - measuredHeight) > 0.5 {
                        measuredHeight = newHeight
                        onContentHeightChange(min(newHeight, maxHeight))
                    }
                }
        }
        .scrollIndicators(needsScroll ? .automatic : .never)
        .scrollDisabled(!needsScroll)
        .frame(width: StatsPopoverStyle.width, height: min(measuredHeight, maxHeight))
        .background(StatsPopoverStyle.surfaceBackground)
        .clipShape(RoundedRectangle(cornerRadius: StatsPopoverStyle.cornerRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: StatsPopoverStyle.cornerRadius, style: .continuous)
                .strokeBorder(Theme.Colors.cardStroke, lineWidth: 1)
        )
        .motionScope()
    }

    @ViewBuilder
    private func moduleBody(snap: StatsSnapshot) -> some View {
        switch module {
        case .cpu:
            CPUPopoverView(
                cpu: snap.cpu,
                history: monitor.cpuHistory,
                topProcesses: snap.topProcessesByCPU,
                onOpenMonitor: onOpenMonitor,
                onOpenSettings: onOpenSettings
            )
        case .ram:
            RAMPopoverView(
                ram: snap.ram,
                history: monitor.ramHistory,
                topProcesses: snap.topProcessesByRAM,
                onOpenMonitor: onOpenMonitor,
                onOpenSettings: onOpenSettings
            )
        case .network:
            NetworkPopoverView(
                network: snap.network,
                downloadHistory: monitor.networkDownloadHistory,
                uploadHistory: monitor.networkUploadHistory,
                topProcesses: snap.topProcessesByNetwork,
                onOpenMonitor: onOpenMonitor,
                onOpenSettings: onOpenSettings
            )
        case .disk:
            DiskPopoverView(
                disk: snap.disk,
                readHistory: monitor.diskReadHistory,
                writeHistory: monitor.diskWriteHistory,
                onOpenMonitor: onOpenMonitor,
                onOpenSettings: onOpenSettings
            )
        case .battery:
            BatteryPopoverView(
                battery: snap.battery,
                topProcesses: snap.topProcessesByCPU,
                onOpenMonitor: onOpenMonitor,
                onOpenSettings: onOpenSettings
            )
        }
    }
}
