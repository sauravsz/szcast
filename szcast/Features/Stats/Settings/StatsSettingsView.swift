import SwiftUI

struct StatsSettingsView: View {
    @Environment(AppSettings.self) private var settings

    var body: some View {
        @Bindable var settings = settings
        Form {
            Section {
                Toggle(isOn: $settings.statsEnabled) {
                    SettingsFeatureToggleLabel(
                        anchor: .stats,
                        title: "Enable System Stats",
                        subtitle: "Real-time native macOS hardware and resource telemetry (inspired by Stats)."
                    )
                }
            }

            if settings.statsEnabled {
                modulesSection
                menuBarSection
                cadenceSection
            }
        }
        .formStyle(.grouped)
        .onChange(of: settings.statsEnabled) { _, _ in
            StatsMenuBarManager.shared.syncWithSettings()
        }
        .onChange(of: settings.statsCPUMenuBar) { _, _ in
            StatsMenuBarManager.shared.syncWithSettings()
        }
        .onChange(of: settings.statsRAMMenuBar) { _, _ in
            StatsMenuBarManager.shared.syncWithSettings()
        }
        .onChange(of: settings.statsDiskMenuBar) { _, _ in
            StatsMenuBarManager.shared.syncWithSettings()
        }
        .onChange(of: settings.statsBatteryMenuBar) { _, _ in
            StatsMenuBarManager.shared.syncWithSettings()
        }
        .onChange(of: settings.statsNetworkMenuBar) { _, _ in
            StatsMenuBarManager.shared.syncWithSettings()
        }
        .onChange(of: settings.statsRefreshInterval) { _, newInterval in
            StatsMonitor.shared.start(interval: newInterval)
        }
    }

    @ViewBuilder
    private var modulesSection: some View {
        @Bindable var settings = settings
        Section {
            Toggle(isOn: $settings.statsCPUEnabled) {
                SettingsRowTitle(.stats, "CPU Monitoring")
                Text("Track overall load, user/system breakdown, and per-core activity.")
            }
            Toggle(isOn: $settings.statsRAMEnabled) {
                SettingsRowTitle(.stats, "Memory Monitoring")
                Text("Track active, wired, compressed, and swap memory allocations.")
            }
            Toggle(isOn: $settings.statsDiskEnabled) {
                SettingsRowTitle(.stats, "Disk Monitoring")
                Text("Track free space and capacity on root and mounted volumes.")
            }
            Toggle(isOn: $settings.statsBatteryEnabled) {
                SettingsRowTitle(.stats, "Battery & Power")
                Text("Track battery charge, AC status, health condition, and time remaining.")
            }
            Toggle(isOn: $settings.statsNetworkEnabled) {
                SettingsRowTitle(.stats, "Network Monitoring")
                Text("Track live download/upload throughput and local interface addresses.")
            }
        } header: {
            SettingsSectionHeader(anchor: .stats) {
                Text("Modules")
            }
        }
    }

    @ViewBuilder
    private var menuBarSection: some View {
        @Bindable var settings = settings
        Section {
            Toggle("Show CPU in Menu Bar", isOn: $settings.statsCPUMenuBar)
                .disabled(!settings.statsCPUEnabled)
            Toggle("Show Memory in Menu Bar", isOn: $settings.statsRAMMenuBar)
                .disabled(!settings.statsRAMEnabled)
            Toggle("Show Disk in Menu Bar", isOn: $settings.statsDiskMenuBar)
                .disabled(!settings.statsDiskEnabled)
            Toggle("Show Battery in Menu Bar", isOn: $settings.statsBatteryMenuBar)
                .disabled(!settings.statsBatteryEnabled)
            Toggle("Show Network in Menu Bar", isOn: $settings.statsNetworkMenuBar)
                .disabled(!settings.statsNetworkEnabled)
        } header: {
            SettingsSectionHeader(anchor: .stats) {
                Text("Menu Bar Items")
            }
        }
    }

    @ViewBuilder
    private var cadenceSection: some View {
        @Bindable var settings = settings
        Section {
            Picker(selection: $settings.statsRefreshInterval) {
                Text("1 second").tag(1.0)
                Text("2 seconds (Recommended)").tag(2.0)
                Text("3 seconds").tag(3.0)
                Text("5 seconds").tag(5.0)
            } label: {
                SettingsRowTitle(.stats, "Refresh Cadence")
                Text("How often background hardware telemetry is sampled.")
            }
        } header: {
            SettingsSectionHeader(anchor: .stats) {
                Text("Performance")
            }
        }
    }
}
