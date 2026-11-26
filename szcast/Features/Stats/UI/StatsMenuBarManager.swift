import AppKit

@MainActor
final class StatsMenuBarManager: NSObject {
    static let shared = StatsMenuBarManager()

    private var cpuItem: NSStatusItem?
    private var ramItem: NSStatusItem?
    private var diskItem: NSStatusItem?
    private var batteryItem: NSStatusItem?
    private var networkItem: NSStatusItem?

    private let popoverController = StatsPopoverController()
    private var settings: AppSettings { AppCore.shared.settings }

    override init() {
        super.init()
        StatsMonitor.shared.onUpdate = { [weak self] snapshot in
            self?.updateStatusItems(with: snapshot)
        }
        popoverController.onDismiss = {
            StatsMonitor.shared.activePopover = nil
        }
    }

    func syncWithSettings() {
        guard settings.statsEnabled else {
            removeAll()
            return
        }

        syncItem(
            &cpuItem, enabled: settings.statsCPUEnabled && settings.statsCPUMenuBar,
            autosave: "StatsCPU", action: #selector(cpuClicked))
        syncItem(
            &ramItem, enabled: settings.statsRAMEnabled && settings.statsRAMMenuBar,
            autosave: "StatsRAM", action: #selector(ramClicked))
        syncItem(
            &diskItem, enabled: settings.statsDiskEnabled && settings.statsDiskMenuBar,
            autosave: "StatsDisk", action: #selector(diskClicked))
        syncItem(
            &batteryItem, enabled: settings.statsBatteryEnabled && settings.statsBatteryMenuBar,
            autosave: "StatsBattery", action: #selector(batteryClicked))
        syncItem(
            &networkItem, enabled: settings.statsNetworkEnabled && settings.statsNetworkMenuBar,
            autosave: "StatsNetwork", action: #selector(networkClicked))

        updateStatusItems(with: StatsMonitor.shared.snapshot)
    }

    func update(with snapshot: StatsSnapshot) {
        syncWithSettings()
        updateStatusItems(with: snapshot)
    }

    func removeAll() {
        popoverController.dismiss()
        if let item = cpuItem { NSStatusBar.system.removeStatusItem(item); cpuItem = nil }
        if let item = ramItem { NSStatusBar.system.removeStatusItem(item); ramItem = nil }
        if let item = diskItem { NSStatusBar.system.removeStatusItem(item); diskItem = nil }
        if let item = batteryItem { NSStatusBar.system.removeStatusItem(item); batteryItem = nil }
        if let item = networkItem { NSStatusBar.system.removeStatusItem(item); networkItem = nil }
    }

    private func syncItem(
        _ slot: inout NSStatusItem?,
        enabled: Bool,
        autosave: String,
        action: Selector
    ) {
        if enabled {
            if slot == nil {
                let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
                item.autosaveName = autosave
                setupButton(item, action: action)
                slot = item
            }
        } else if let item = slot {
            NSStatusBar.system.removeStatusItem(item)
            slot = nil
        }
    }

    private func updateStatusItems(with snapshot: StatsSnapshot) {
        if let item = cpuItem {
            let value = "\(Int(snapshot.cpu.totalUsage.rounded()))%"
            StatsMenuBarRenderer.apply(
                content: .stackedMetric(label: "CPU", value: value),
                accessibilityText: "CPU \(value)",
                to: item
            )
        }

        if let item = ramItem {
            let value = "\(Int(snapshot.ram.usagePercentage.rounded()))%"
            StatsMenuBarRenderer.apply(
                content: .stackedMetric(label: "RAM", value: value),
                accessibilityText: "Memory \(value)",
                to: item
            )
        }

        if let item = diskItem {
            let value = "\(Int((snapshot.disk.rootVolume?.usagePercentage ?? 0).rounded()))%"
            StatsMenuBarRenderer.apply(
                content: .stackedMetric(label: "SSD", value: value),
                accessibilityText: "Disk \(value)",
                to: item
            )
        }

        if let item = batteryItem {
            let bat = snapshot.battery
            let label = bat.hasBattery ? "Battery \(bat.percentage)%" : "AC Power"
            StatsMenuBarRenderer.apply(
                content: .battery(
                    percentage: bat.percentage,
                    isCharging: bat.isCharging,
                    isACConnected: bat.isACConnected,
                    hasBattery: bat.hasBattery
                ),
                accessibilityText: label,
                to: item
            )
        }

        if let item = networkItem {
            let downStr = StatsFormatting.speed(snapshot.network.downloadBytesPerSecond)
            let upStr = StatsFormatting.speed(snapshot.network.uploadBytesPerSecond)
            StatsMenuBarRenderer.apply(
                content: .networkSpeed(download: downStr, upload: upStr),
                accessibilityText: "Network down \(downStr), up \(upStr)",
                to: item
            )
        }
    }

    private func setupButton(_ item: NSStatusItem, action: Selector) {
        guard let button = item.button else { return }
        button.target = self
        button.action = action
        // Left-down gives instant popover toggle before resignKey clears currentModule.
        button.sendAction(on: [.leftMouseDown, .rightMouseUp])
        button.imagePosition = .noImage
        button.image = nil
        button.title = ""
    }

    // MARK: - Actions

    @objc private func cpuClicked() {
        handleItemClick(module: .cpu, item: cpuItem)
    }

    @objc private func ramClicked() {
        handleItemClick(module: .ram, item: ramItem)
    }

    @objc private func diskClicked() {
        handleItemClick(module: .disk, item: diskItem)
    }

    @objc private func batteryClicked() {
        handleItemClick(module: .battery, item: batteryItem)
    }

    @objc private func networkClicked() {
        handleItemClick(module: .network, item: networkItem)
    }

    private func handleItemClick(module: StatsModule, item: NSStatusItem?) {
        let event = NSApp.currentEvent
        let isContextClick = event?.type == .rightMouseUp
            || !(event?.modifierFlags.isDisjoint(with: [.control, .option]) ?? true)

        if isContextClick {
            popoverController.dismiss()
            buildContextMenu().popUp(positioning: nil, at: NSEvent.mouseLocation, in: nil)
            return
        }

        if popoverController.currentModule == module {
            popoverController.dismiss()
            return
        }
        if popoverController.wasJustDismissedByResign(module: module) {
            return
        }

        guard let button = item?.button else { return }
        StatsMonitor.shared.activePopover = module
        popoverController.show(
            module: module,
            anchoredTo: button,
            onOpenMonitor: { [weak self] in
                self?.openActivityMonitor()
            },
            onOpenSettings: { [weak self] in
                self?.openStatsSettings()
            }
        )
    }

    // MARK: - Context Menu & Targets

    private func buildContextMenu() -> NSMenu {
        let menu = NSMenu()
        let dashboard = NSMenuItem(
            title: String(localized: "Open System Stats Dashboard"),
            action: #selector(openDashboardAction),
            keyEquivalent: ""
        )
        dashboard.target = self
        menu.addItem(dashboard)

        let monitor = NSMenuItem(
            title: String(localized: "Open Activity Monitor"),
            action: #selector(openActivityMonitorAction),
            keyEquivalent: ""
        )
        monitor.target = self
        menu.addItem(monitor)

        menu.addItem(NSMenuItem.separator())

        let settingsItem = NSMenuItem(
            title: String(localized: "System Stats Settings…"),
            action: #selector(openStatsSettingsAction),
            keyEquivalent: ","
        )
        settingsItem.target = self
        menu.addItem(settingsItem)
        return menu
    }

    private func openActivityMonitor() {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.ActivityMonitor") {
            NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
        }
    }

    private func openStatsSettings() {
        AppCore.shared.settingsCoordinator.showSettings(tab: .stats)
    }

    @objc private func openDashboardAction() {
        AppCore.shared.paletteCoordinator.showPalette(mode: .systemStats)
    }

    @objc private func openActivityMonitorAction() {
        openActivityMonitor()
    }

    @objc private func openStatsSettingsAction() {
        openStatsSettings()
    }
}
