import AppKit

@MainActor
final class StatsMenuBarManager: NSObject {
    static let shared = StatsMenuBarManager()

    private var cpuItem: NSStatusItem?
    private var ramItem: NSStatusItem?
    private var diskItem: NSStatusItem?
    private var batteryItem: NSStatusItem?
    private var networkItem: NSStatusItem?

    private var settings: AppSettings { AppCore.shared.settings }

    override init() {
        super.init()
        StatsMonitor.shared.onUpdate = { [weak self] snapshot in
            self?.updateTitles(with: snapshot)
        }
    }

    func syncWithSettings() {
        guard settings.statsEnabled else {
            removeAll()
            return
        }

        // CPU Item
        if settings.statsCPUEnabled && settings.statsCPUMenuBar {
            if cpuItem == nil {
                let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
                item.autosaveName = "StatsCPU"
                setupButton(item, action: #selector(cpuClicked))
                cpuItem = item
            }
        } else {
            if let item = cpuItem {
                NSStatusBar.system.removeStatusItem(item)
                cpuItem = nil
            }
        }

        // RAM Item
        if settings.statsRAMEnabled && settings.statsRAMMenuBar {
            if ramItem == nil {
                let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
                item.autosaveName = "StatsRAM"
                setupButton(item, action: #selector(ramClicked))
                ramItem = item
            }
        } else {
            if let item = ramItem {
                NSStatusBar.system.removeStatusItem(item)
                ramItem = nil
            }
        }

        // Disk Item
        if settings.statsDiskEnabled && settings.statsDiskMenuBar {
            if diskItem == nil {
                let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
                item.autosaveName = "StatsDisk"
                setupButton(item, action: #selector(diskClicked))
                diskItem = item
            }
        } else {
            if let item = diskItem {
                NSStatusBar.system.removeStatusItem(item)
                diskItem = nil
            }
        }

        // Battery Item
        if settings.statsBatteryEnabled && settings.statsBatteryMenuBar {
            if batteryItem == nil {
                let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
                item.autosaveName = "StatsBattery"
                setupButton(item, action: #selector(batteryClicked))
                batteryItem = item
            }
        } else {
            if let item = batteryItem {
                NSStatusBar.system.removeStatusItem(item)
                batteryItem = nil
            }
        }

        // Network Item
        if settings.statsNetworkEnabled && settings.statsNetworkMenuBar {
            if networkItem == nil {
                let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
                item.autosaveName = "StatsNetwork"
                setupButton(item, action: #selector(networkClicked))
                networkItem = item
            }
        } else {
            if let item = networkItem {
                NSStatusBar.system.removeStatusItem(item)
                networkItem = nil
            }
        }

        // Populate titles from current snapshot so items have non-zero width
        updateTitles(with: StatsMonitor.shared.snapshot)
    }

    func update(with snapshot: StatsSnapshot) {
        syncWithSettings()
        updateTitles(with: snapshot)
    }

    private func updateTitles(with snapshot: StatsSnapshot) {
        // 1. CPU
        if let btn = cpuItem?.button {
            btn.title = "CPU \(Int(snapshot.cpu.totalUsage.rounded()))%"
        }

        // 2. RAM
        if let btn = ramItem?.button {
            let usedGB = snapshot.ram.usedGB
            btn.title = String(format: "RAM %.1fG", usedGB)
        }

        // 3. Disk
        if let btn = diskItem?.button {
            if let root = snapshot.disk.rootVolume {
                btn.title = String(format: "SSD %.0fG free", root.freeGB)
            } else {
                btn.title = "SSD"
            }
        }

        // 4. Battery
        if let btn = batteryItem?.button {
            if snapshot.battery.hasBattery {
                let bolt = snapshot.battery.isCharging ? "⚡" : ""
                btn.title = "\(bolt)\(snapshot.battery.percentage)%"
            } else {
                btn.title = "AC"
            }
        }

        // 5. Network
        if let btn = networkItem?.button {
            let downStr = formatRate(snapshot.network.downloadBytesPerSecond)
            let upStr = formatRate(snapshot.network.uploadBytesPerSecond)
            btn.title = "↓ \(downStr) ↑ \(upStr)"
        }
    }

    func removeAll() {
        if let item = cpuItem { NSStatusBar.system.removeStatusItem(item); cpuItem = nil }
        if let item = ramItem { NSStatusBar.system.removeStatusItem(item); ramItem = nil }
        if let item = diskItem { NSStatusBar.system.removeStatusItem(item); diskItem = nil }
        if let item = batteryItem { NSStatusBar.system.removeStatusItem(item); batteryItem = nil }
        if let item = networkItem { NSStatusBar.system.removeStatusItem(item); networkItem = nil }
    }

    private func setupButton(_ item: NSStatusItem, action: Selector) {
        guard let button = item.button else { return }
        button.target = self
        button.action = action
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        button.font = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .regular)
    }

    private func formatRate(_ bytesPerSec: Double) -> String {
        if bytesPerSec >= 1_048_576_000 {
            return String(format: "%.1f GB/s", bytesPerSec / 1_073_741_824.0)
        } else if bytesPerSec >= 1_048_576 {
            return String(format: "%.1f MB/s", bytesPerSec / 1_048_576.0)
        } else if bytesPerSec >= 1024 {
            return String(format: "%.0f KB/s", bytesPerSec / 1024.0)
        } else {
            return "0 KB/s"
        }
    }

    // MARK: - Actions

    @objc private func cpuClicked() {
        handleItemClick(buildCPUMenu())
    }

    @objc private func ramClicked() {
        handleItemClick(buildRAMMenu())
    }

    @objc private func diskClicked() {
        handleItemClick(buildDiskMenu())
    }

    @objc private func batteryClicked() {
        handleItemClick(buildBatteryMenu())
    }

    @objc private func networkClicked() {
        handleItemClick(buildNetworkMenu())
    }

    private func handleItemClick(_ menu: NSMenu) {
        guard let event = NSApp.currentEvent,
              event.type == .rightMouseUp || !event.modifierFlags.isDisjoint(with: [.control, .option]) else {
            openSystemStats()
            return
        }
        menu.popUp(positioning: nil, at: NSEvent.mouseLocation, in: nil)
    }

    private func openSystemStats() {
        AppCore.shared.paletteCoordinator.showPalette(mode: .systemStats)
    }

    // MARK: - Context Menus

    private func buildCPUMenu() -> NSMenu {
        let menu = NSMenu()
        let snap = StatsMonitor.shared.snapshot.cpu
        menu.addItem(NSMenuItem(title: "CPU Load: \(Int(snap.totalUsage.rounded()))%", action: nil, keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "User: \(Int(snap.userPercentage.rounded()))% • System: \(Int(snap.systemPercentage.rounded()))%", action: nil, keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "Physical Cores: \(snap.physicalCores) • Logical: \(snap.logicalCores)", action: nil, keyEquivalent: ""))
        menu.addItem(NSMenuItem.separator())
        let openItem = NSMenuItem(title: "Open System Stats…", action: #selector(openStatsAction), keyEquivalent: "")
        openItem.target = self
        menu.addItem(openItem)
        return menu
    }

    private func buildRAMMenu() -> NSMenu {
        let menu = NSMenu()
        let snap = StatsMonitor.shared.snapshot.ram
        menu.addItem(NSMenuItem(title: "Memory: \(String(format: "%.1f", snap.usedGB)) GB / \(String(format: "%.1f", snap.totalGB)) GB", action: nil, keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "Active: \(String(format: "%.1f", Double(snap.activeBytes)/1e9)) GB • Wired: \(String(format: "%.1f", Double(snap.wiredBytes)/1e9)) GB", action: nil, keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "Compressed: \(String(format: "%.1f", Double(snap.compressedBytes)/1e9)) GB", action: nil, keyEquivalent: ""))
        menu.addItem(NSMenuItem.separator())
        let openItem = NSMenuItem(title: "Open System Stats…", action: #selector(openStatsAction), keyEquivalent: "")
        openItem.target = self
        menu.addItem(openItem)
        return menu
    }

    private func buildDiskMenu() -> NSMenu {
        let menu = NSMenu()
        let snap = StatsMonitor.shared.snapshot.disk
        for vol in snap.volumes {
            menu.addItem(NSMenuItem(title: "\(vol.name): \(String(format: "%.1f", vol.freeGB)) GB free of \(String(format: "%.1f", vol.totalGB)) GB", action: nil, keyEquivalent: ""))
        }
        menu.addItem(NSMenuItem.separator())
        let openItem = NSMenuItem(title: "Open System Stats…", action: #selector(openStatsAction), keyEquivalent: "")
        openItem.target = self
        menu.addItem(openItem)
        return menu
    }

    private func buildBatteryMenu() -> NSMenu {
        let menu = NSMenu()
        let snap = StatsMonitor.shared.snapshot.battery
        if snap.hasBattery {
            menu.addItem(NSMenuItem(title: "Battery: \(snap.percentage)% (\(snap.isCharging ? "Charging" : "Discharging"))", action: nil, keyEquivalent: ""))
            menu.addItem(NSMenuItem(title: "Condition: \(snap.health)", action: nil, keyEquivalent: ""))
            if let mins = snap.timeRemainingMinutes {
                let hrs = mins / 60
                let m = mins % 60
                menu.addItem(NSMenuItem(title: "Remaining: \(hrs)h \(m)m", action: nil, keyEquivalent: ""))
            }
        } else {
            menu.addItem(NSMenuItem(title: "Power Source: Power Adapter", action: nil, keyEquivalent: ""))
        }
        menu.addItem(NSMenuItem.separator())
        let openItem = NSMenuItem(title: "Open System Stats…", action: #selector(openStatsAction), keyEquivalent: "")
        openItem.target = self
        menu.addItem(openItem)
        return menu
    }

    private func buildNetworkMenu() -> NSMenu {
        let menu = NSMenu()
        let snap = StatsMonitor.shared.snapshot.network
        menu.addItem(NSMenuItem(title: "Interface: \(snap.interfaceName) (\(snap.localIP))", action: nil, keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "Download: \(formatRate(snap.downloadBytesPerSecond))", action: nil, keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "Upload: \(formatRate(snap.uploadBytesPerSecond))", action: nil, keyEquivalent: ""))
        menu.addItem(NSMenuItem.separator())
        let openItem = NSMenuItem(title: "Open System Stats…", action: #selector(openStatsAction), keyEquivalent: "")
        openItem.target = self
        menu.addItem(openItem)
        return menu
    }

    @objc private func openStatsAction() {
        openSystemStats()
    }
}
