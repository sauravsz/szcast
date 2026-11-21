import SwiftUI

struct TextTransformerSettingsView: View {
    @Environment(AppSettings.self) private var settings

    var body: some View {
        @Bindable var settings = settings
        Form {
            Section {
                Toggle(isOn: $settings.textTransformerEnabled) {
                    SettingsRowTitle(.textTransformerTextTransformer, "Enable Text Transformer")
                    Text("Interactive developer text processing tool with live casing, formatting, encoding, and metrics.")
                }
            } header: {
                SettingsSectionHeader(.textTransformerTextTransformer)
            }

            FeatureCommandsSection(owner: .textTransformer, anchor: .textTransformerCommands)

            Section {
                SettingsRow(
                    title: "Live Text Metrics",
                    subtitle: "Real-time count of characters, words, lines, and UTF-8 byte sizes for both input and output."
                ) {
                    Image(systemName: "gauge.with.needle")
                        .foregroundStyle(Color.accentColor)
                        .frame(width: SettingsListMetrics.iconSize)
                } trailing: {
                    Text("Always active")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Theme.Colors.controlSurface)
                        .clipShape(Capsule())
                }

                SettingsRow(
                    title: "28 Transformation Engines",
                    subtitle: "Casing (camelCase, snake_case), Lines (sort, dedupe), Encoding (Base64, URL, Hex), and Formatting (JSON, URLs)."
                ) {
                    Image(systemName: "wand.and.stars")
                        .foregroundStyle(Color.accentColor)
                        .frame(width: SettingsListMetrics.iconSize)
                } trailing: {
                    Text("Built-in")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Theme.Colors.controlSurface)
                        .clipShape(Capsule())
                }

                SettingsRow(
                    title: "Single-Key Workflow",
                    subtitle: "Return (↵) pastes into active application; Command+C copies output; Command+R reverts."
                ) {
                    Image(systemName: "keyboard")
                        .foregroundStyle(Color.accentColor)
                        .frame(width: SettingsListMetrics.iconSize)
                } trailing: {
                    Text("↵ / ⌘C / ⌘R")
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Theme.Colors.controlSurface)
                        .clipShape(Capsule())
                }
            } header: {
                Text("Features & Shortcuts")
            }
        }
        .formStyle(.grouped)
        .settingsScrollTarget(.textTransformer)
    }
}
