import AppKit
import SwiftUI

struct StatsScreen: PaletteScreen {
    let core: AppCore
    let vm: PaletteState
    let monitor: StatsMonitor = .shared

    struct Row: Identifiable {
        let id: Int
    }

    var rows: [Row] { [Row(id: 0)] }

    var primaryActionTitle: String { String(localized: "Refresh Metrics") }

    func actions(at selection: Int) -> PopoverMenuContent? {
        PopoverMenuContent(
            header: String(localized: "System Stats"),
            items: [
                PopoverMenuItem(
                    title: String(localized: "Refresh Metrics"),
                    systemImage: "arrow.clockwise",
                    shortcut: "↵"
                ) {
                    monitor.refresh()
                },
                PopoverMenuItem(
                    title: String(localized: "System Stats Settings"),
                    systemImage: "gearshape",
                    startsSection: true,
                    shortcut: "⌘,"
                ) {
                    core.settingsCoordinator.showSettings(tab: .stats)
                }
            ]
        )
    }

    func activate(at selection: Int) {
        monitor.refresh()
    }

    func secondary(at selection: Int) -> Bool {
        core.settingsCoordinator.showSettings(tab: .stats)
        return true
    }

    func perform(_ shortcut: PaletteShortcut, at selection: Int) -> Bool {
        switch shortcut {
        case .restart:
            monitor.refresh()
            return true
        default:
            return false
        }
    }

    func body(selection: Int, scroll: ScrollIntent) -> AnyView {
        AnyView(
            StatsDashboardView(monitor: monitor)
                .onAppear {
                    monitor.isDashboardActive = true
                    monitor.start(interval: core.settings.statsRefreshInterval)
                }
                .onDisappear {
                    monitor.isDashboardActive = false
                }
        )
    }
}
