import SwiftUI

struct CleanKeyboardSettingsView: View {
    @State private var cleanService = CleanKeyboardService.shared
    @AppStorage("cleanKeyboard.defaultDuration") private var defaultDuration: Int = 60

    var body: some View {
        Form {
            Section {
                SettingsRow(
                    title: "Clean Keyboard Mode",
                    subtitle: "Temporarily locks your physical keyboard so you can safely clean keys without accidental input."
                ) {
                    SettingsTabIcon(
                        systemImage: "keyboard",
                        tint: .accentColor,
                        size: Theme.Size.settingsRowIcon * 1.5
                    )
                } trailing: {
                    Button("Start Cleaning Mode") {
                        cleanService.startCleaning(duration: defaultDuration)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.regular)
                }

                Picker(selection: $defaultDuration) {
                    Text("30 seconds").tag(30)
                    Text("60 seconds (1 minute)").tag(60)
                    Text("90 seconds").tag(90)
                    Text("120 seconds (2 minutes)").tag(120)
                } label: {
                    SettingsRowTitle(.cleanKeyboardCleanKeyboard, "Default cleaning duration")
                    Text("How long keyboard inputs stay locked.")
                }
            } header: {
                SettingsSectionHeader(.cleanKeyboardCleanKeyboard)
            }

            FeatureCommandsSection(owner: .cleanKeyboard, anchor: .cleanKeyboardCommands)

            Section {
                SettingsRow(
                    title: "Hold Escape for 3 seconds",
                    subtitle: "Press and hold the Escape key continuously until the cleaning lock releases."
                ) {
                    Image(systemName: "lock.open")
                        .foregroundStyle(.secondary)
                        .frame(width: SettingsListMetrics.iconSize)
                } trailing: {
                    Text("Primary")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Theme.Colors.controlSurface)
                        .clipShape(Capsule())
                }

                SettingsRow(
                    title: "Emergency Chord: ⌃U",
                    subtitle: "Press Control + U at any time to immediately cancel keyboard lock."
                ) {
                    Image(systemName: "bolt.shield")
                        .foregroundStyle(.secondary)
                        .frame(width: SettingsListMetrics.iconSize)
                } trailing: {
                    Text("⌃U")
                        .font(.caption.weight(.semibold).monospaced())
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Theme.Colors.controlSurface)
                        .clipShape(Capsule())
                }
            } header: {
                SettingsSectionHeader(.cleanKeyboardSafety)
            } footer: {
                Text("Requires Accessibility permission to block keystrokes during cleaning.")
            }
        }
        .formStyle(.grouped)
        .settingsScrollTarget(.cleanKeyboard)
    }
}
