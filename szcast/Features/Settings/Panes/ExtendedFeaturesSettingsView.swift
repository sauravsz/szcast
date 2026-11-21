import SwiftUI

struct ExtendedFeaturesSettingsView: View {
    @Environment(AppSettings.self) private var settings
    @Environment(SettingsNavigationState.self) private var navigation
    @Environment(AppCore.self) private var core

    var body: some View {
        Form {
            Section {
                SettingsRow(
                    title: "Extended Features Hub",
                    subtitle: "Optional power tools and integrations. Disabled features are fully dormant and removed from the launcher."
                ) {
                    SettingsTabIcon(
                        systemImage: "sparkles.rectangle.stack",
                        tint: .accentColor,
                        size: Theme.Size.settingsRowIcon * 1.5
                    )
                }
            } header: {
                SettingsSectionHeader(.extendedFeatures)
            }

            Section("Available Integrations") {
                // 1. Apple Shortcuts
                featureRow(
                    title: "Apple Shortcuts",
                    subtitle: "Run Siri and Shortcuts app automations directly from the launcher.",
                    systemImage: "square.2.layers.3d",
                    isOn: Binding(
                        get: { settings.appleShortcutsEnabled },
                        set: {
                            settings.appleShortcutsEnabled = $0
                            core.appleShortcutCoordinator.refresh()
                        }
                    ),
                    targetTab: .appleShortcuts
                )

                // 2. Calendar & Meetings
                featureRow(
                    title: "Calendar & Meetings",
                    subtitle: "Menu bar countdown, schedule browser, and one-click meeting joining.",
                    systemImage: "calendar",
                    isOn: Binding(
                        get: { settings.calendarEnabled },
                        set: {
                            settings.calendarEnabled = $0
                            core.calendarCoordinator.applyEnabled()
                        }
                    ),
                    targetTab: .calendar
                )

                // 3. Clean Keyboard Mode
                featureRow(
                    title: "Clean Keyboard Mode",
                    subtitle: "Temporarily locks all keyboard inputs so keys can be safely wiped down.",
                    systemImage: "keyboard",
                    isOn: Binding(
                        get: { settings.cleanKeyboardEnabled },
                        set: {
                            settings.cleanKeyboardEnabled = $0
                            core.applyExtendedFeaturesPresence()
                        }
                    ),
                    targetTab: .cleanKeyboard
                )

                // 4. Display Tweaks & Gamma Control
                featureRow(
                    title: "Display Tweaks & Gamma Control",
                    subtitle: "Direct GPU transfer curves, 3-point calibration, and OLED contrast tuning.",
                    systemImage: "sun.max",
                    isOn: Binding(
                        get: { settings.displayTweaksEnabled },
                        set: {
                            settings.displayTweaksEnabled = $0
                            if $0 {
                                DisplayTweaksService.shared.applyPercent(
                                    displayID: settings.displayTweaksDisplayID,
                                    red: settings.displayTweaksRed,
                                    green: settings.displayTweaksGreen,
                                    blue: settings.displayTweaksBlue,
                                    blacks: settings.displayTweaksBlacks,
                                    shadows: settings.displayTweaksShadows,
                                    highlights: settings.displayTweaksHighlights,
                                    whites: settings.displayTweaksWhites,
                                    contrast: settings.displayTweaksContrast,
                                    brightness: settings.displayTweaksBrightness
                                )
                            } else {
                                DisplayTweaksService.shared.restoreGamma()
                            }
                        }
                    ),
                    targetTab: .displayTweaks
                )

                // 5. DuckDuckGo Email
                featureRow(
                    title: "DuckDuckGo Email",
                    subtitle: "Generate disposable private email forwarding aliases on demand.",
                    systemImage: "envelope.badge.shield.half.filled",
                    isOn: Binding(
                        get: { settings.duckDuckGoEmailEnabled },
                        set: {
                            settings.duckDuckGoEmailEnabled = $0
                            core.applyExtendedFeaturesPresence()
                        }
                    ),
                    targetTab: .duckDuckGoEmail
                )

                // 6. Ente Auth (2FA)
                featureRow(
                    title: "Ente Auth (2FA)",
                    subtitle: "Offline RFC 6238 TOTP authenticator with instant code generation.",
                    systemImage: "key.fill",
                    isOn: Binding(
                        get: { settings.enteAuthEnabled },
                        set: {
                            settings.enteAuthEnabled = $0
                            core.applyExtendedFeaturesPresence()
                        }
                    ),
                    targetTab: .enteAuth
                )

                // 7. KeePassXC Passwords
                featureRow(
                    title: "KeePassXC Passwords",
                    subtitle: "Offline password database search and autofill via KeePassXC CLI.",
                    systemImage: "lock.fill",
                    isOn: Binding(
                        get: { settings.keepassxcEnabled },
                        set: {
                            settings.keepassxcEnabled = $0
                            core.applyExtendedFeaturesPresence()
                        }
                    ),
                    targetTab: .keepassxc
                )

                // 8. System Stats
                featureRow(
                    title: "System Stats",
                    subtitle: "Real-time hardware monitoring suite for CPU, RAM, Disk, Battery, and Network with menu bar widgets.",
                    systemImage: "gauge.with.needle",
                    isOn: Binding(
                        get: { settings.statsEnabled },
                        set: {
                            settings.statsEnabled = $0
                            if $0 {
                                StatsMonitor.shared.start(interval: settings.statsRefreshInterval)
                            } else {
                                StatsMonitor.shared.stop()
                            }
                            StatsMenuBarManager.shared.syncWithSettings()
                            core.applyExtendedFeaturesPresence()
                        }
                    ),
                    targetTab: .stats
                )

                // 9. Text Transformer
                featureRow(
                    title: "Text Transformer",
                    subtitle: "Developer text processing tool with live casing, formatting, encoding, and metrics.",
                    systemImage: "text.word.spacing",
                    isOn: Binding(
                        get: { settings.textTransformerEnabled },
                        set: {
                            settings.textTransformerEnabled = $0
                            core.applyExtendedFeaturesPresence()
                        }
                    ),
                    targetTab: .textTransformer
                )
            }
        }
        .formStyle(.grouped)
        .settingsScrollTarget(.extendedFeatures)
    }

    @ViewBuilder
    private func featureRow(
        title: String,
        subtitle: String,
        systemImage: String,
        isOn: Binding<Bool>,
        targetTab: SettingsTab
    ) -> some View {
        HStack(spacing: Theme.Spacing.md) {
            SettingsTabIcon(
                systemImage: systemImage,
                tint: isOn.wrappedValue ? .accentColor : .secondary
            )
            VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
                Text(title)
                    .font(.body)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if isOn.wrappedValue {
                Button("Configure") {
                    navigation.select(targetTab)
                }
                .controlSize(.small)
            }
            Toggle("", isOn: isOn)
                .labelsHidden()
        }
        .padding(.vertical, Theme.Spacing.xxs)
    }
}
