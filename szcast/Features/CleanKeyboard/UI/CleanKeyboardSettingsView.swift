import SwiftUI

struct CleanKeyboardSettingsView: View {
    @State private var cleanService = CleanKeyboardService.shared
    @AppStorage("cleanKeyboard.defaultDuration") private var defaultDuration: Int = 60

    var body: some View {
        Form {
            Section {
                VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                    HStack(spacing: Theme.Spacing.md) {
                        Image(systemName: "keyboard")
                            .font(.system(size: 20))
                            .foregroundStyle(Color.accentColor)

                        VStack(alignment: .leading, spacing: 2) {
                            Text("Clean Keyboard Mode")
                                .font(.system(size: 13, weight: .semibold))
                            Text("Temporarily locks your physical keyboard so you can safely clean keys without accidental input.")
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 2)

                    Picker("Default cleaning duration", selection: $defaultDuration) {
                        Text("30 seconds").tag(30)
                        Text("60 seconds (1 minute)").tag(60)
                        Text("90 seconds").tag(90)
                        Text("120 seconds (2 minutes)").tag(120)
                    }

                    Button("Start Cleaning Mode Now") {
                        cleanService.startCleaning(duration: defaultDuration)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                }
                .padding(.vertical, 4)
            } header: {
                Text("Keyboard Lock")
            }

            Section {
                VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: "lock.shield.fill")
                            .foregroundStyle(Color.green)
                        VStack(alignment: .leading, spacing: 3) {
                            Text("How to Unlock Early")
                                .font(.system(size: 12, weight: .semibold))
                            Text("1. Hold the Escape key for 3 seconds, OR\n2. Press Control + U (⌃U) anytime.")
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 2)
                }
            } header: {
                Text("Safety Unlock")
            } footer: {
                Text("Requires Accessibility permission to block keystrokes during cleaning.")
            }

            Section {
                HStack {
                    Text("Launcher Command")
                        .font(.system(size: 12, weight: .medium))
                    Spacer()
                    Text("Clean Keyboard")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text("Launcher Trigger")
            }
        }
    }
}
