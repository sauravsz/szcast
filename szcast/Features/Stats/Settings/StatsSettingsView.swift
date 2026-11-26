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
                Section {
                    Toggle(isOn: $settings.statsCPUEnabled) {
                        SettingsRowTitle(.statsModules, "CPU Monitoring")
                        Text("Track overall load, user/system breakdown, and per-core activity.")
                    }
                    Toggle(isOn: $settings.statsRAMEnabled) {
                        SettingsRowTitle(.statsModules, "Memory Monitoring")
                        Text("Track active, wired, compressed, and swap memory allocations.")
                    }
                    Toggle(isOn: $settings.statsDiskEnabled) {
                        SettingsRowTitle(.statsModules, "Disk Monitoring")
                        Text("Track free space and capacity on root and mounted volumes.")
                    }
                    Toggle(isOn: $settings.statsBatteryEnabled) {
                        SettingsRowTitle(.statsModules, "Battery & Power")
                        Text("Track battery charge, AC status, health condition, and time remaining.")
                    }
                    Toggle(isOn: $settings.statsNetworkEnabled) {
                        SettingsRowTitle(.statsModules, "Network Monitoring")
                        Text("Track live download/upload throughput and local interface addresses.")
                    }
                } header: {
                    SettingsSectionHeader(.statsModules)
                }

                Section {
                    Toggle(isOn: $settings.statsCPUMenuBar) {
                        SettingsRowTitle(.statsMenuBar, "Show CPU in Menu Bar")
                    }
                    .disabled(!settings.statsCPUEnabled)
                    Toggle(isOn: $settings.statsRAMMenuBar) {
                        SettingsRowTitle(.statsMenuBar, "Show Memory in Menu Bar")
                    }
                    .disabled(!settings.statsRAMEnabled)
                    Toggle(isOn: $settings.statsDiskMenuBar) {
                        SettingsRowTitle(.statsMenuBar, "Show Disk in Menu Bar")
                    }
                    .disabled(!settings.statsDiskEnabled)
                    Toggle(isOn: $settings.statsBatteryMenuBar) {
                        SettingsRowTitle(.statsMenuBar, "Show Battery in Menu Bar")
                    }
                    .disabled(!settings.statsBatteryEnabled)
                    Toggle(isOn: $settings.statsNetworkMenuBar) {
                        SettingsRowTitle(.statsMenuBar, "Show Network in Menu Bar")
                    }
                    .disabled(!settings.statsNetworkEnabled)

                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 2) {
                            SettingsRowTitle(.statsMenuBar, "Menu bar spacing")
                            Text("Side padding around each item in points.")
                        }
                        Spacer()
                        Slider(value: $settings.statsMenuBarSpacing, in: 0...12, step: 1)
                            .frame(width: 110)
                        Stepper(
                            value: $settings.statsMenuBarSpacing,
                            in: 0...12,
                            step: 1
                        ) {
                            Text(verbatim: "\(Int(settings.statsMenuBarSpacing.rounded())) pt")
                                .monospacedDigit()
                                .frame(minWidth: 36, alignment: .trailing)
                        }
                    }
                } header: {
                    SettingsSectionHeader(.statsMenuBar)
                }

                Section {
                    Picker(selection: $settings.statsRefreshInterval) {
                        Text("1 second (Recommended)").tag(1.0)
                        Text("2 seconds").tag(2.0)
                        Text("3 seconds").tag(3.0)
                        Text("5 seconds").tag(5.0)
                    } label: {
                        SettingsRowTitle(.statsPerformance, "Refresh Cadence")
                        Text("How often background hardware telemetry is sampled.")
                    }
                } header: {
                    SettingsSectionHeader(.statsPerformance)
                }
            }
        }
        .formStyle(.grouped)
        .settingsScrollTarget(.stats)
        .onChange(of: settings.statsEnabled) { _, isEnabled in
            if isEnabled {
                StatsMonitor.shared.start(interval: settings.statsRefreshInterval)
                StatsMenuBarManager.shared.syncWithSettings()
            } else {
                StatsMonitor.shared.stop()
                StatsMenuBarManager.shared.removeAll()
            }
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
        .onChange(of: settings.statsMenuBarSpacing) { _, _ in
            StatsMenuBarManager.shared.syncWithSettings()
        }
        .onChange(of: settings.statsRefreshInterval) { _, newInterval in
            StatsMonitor.shared.start(interval: newInterval)
        }
    }
}
