import SwiftUI

struct CleanKeyboardSettingsView: View {
    @State private var cleanService = CleanKeyboardService.shared
    @AppStorage("cleanKeyboard.defaultDuration") private var defaultDuration: Int = 60

    var body: some View {
        Form {
            Section {
                HStack(spacing: Theme.Spacing.md) {
                    Image(systemName: "keyboard")
                        .font(.system(size: 24))
                        .foregroundStyle(Color.accentColor)
                        .frame(width: 32)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Clean Keyboard Mode")
                            .font(.headline)
                        Text("Temporarily locks your physical keyboard so you can safely clean keys without accidental input.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 4)

                Picker(selection: $defaultDuration) {
                    Text("30 seconds").tag(30)
                    Text("60 seconds (1 minute)").tag(60)
                    Text("90 seconds").tag(90)
                    Text("120 seconds (2 minutes)").tag(120)
                } label: {
                    Text("Default cleaning duration")
                    Text("How long keyboard inputs stay locked.")
                }

                LabeledContent {
                    Button("Start Cleaning Mode Now") {
                        cleanService.startCleaning(duration: defaultDuration)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.regular)
                } label: {
                    Text("Activate lock")
                    Text("Locks keyboard inputs immediately for the selected duration.")
                }
            } header: {
                Text("Keyboard Lock")
            }

            Section {
                LabeledContent {
                    Text("Hold Escape for 3 seconds")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                } label: {
                    Label("Primary unlock", systemImage: "lock.open")
                }

                LabeledContent {
                    Text("⌃U (Control + U)")
                        .font(.subheadline.monospaced())
                        .foregroundStyle(.secondary)
                } label: {
                    Label("Emergency chord", systemImage: "bolt.shield")
                }
            } header: {
                Text("Safety Unlock")
            } footer: {
                Text("Requires Accessibility permission to block keystrokes during cleaning.")
            }

            Section {
                LabeledContent {
                    Text("Clean Keyboard")
                        .font(.subheadline.monospaced())
                        .foregroundStyle(.secondary)
                } label: {
                    Text("Launcher command")
                    Text("Search in szcast to start keyboard cleaning.")
                }
            } header: {
                Text("Launcher Trigger")
            }
        }
        .formStyle(.grouped)
    }
}
