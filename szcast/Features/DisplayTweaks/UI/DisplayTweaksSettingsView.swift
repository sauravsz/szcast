import SwiftUI

struct DisplayTweaksSettingsView: View {
    @Environment(AppSettings.self) private var settings
    private let service = DisplayTweaksService.shared
    @State private var displays: [DisplayTweaksService.DisplayChoice] = []

    var body: some View {
        @Bindable var bSettings = settings

        let tables = service.calculateTransferTables(
            redGain: settings.displayTweaksRed,
            greenGain: settings.displayTweaksGreen,
            blueGain: settings.displayTweaksBlue,
            blacks: settings.displayTweaksBlacks,
            shadows: settings.displayTweaksShadows,
            highlights: settings.displayTweaksHighlights,
            whites: settings.displayTweaksWhites,
            contrast: settings.displayTweaksContrast,
            brightness: settings.displayTweaksBrightness
        )

        return Form {
            Section {
                Toggle(isOn: $bSettings.displayTweaksEnabled) {
                    SettingsFeatureToggleLabel(
                        anchor: .displayTweaksDisplayTweaks,
                        title: "Enable Display Tweaks",
                        subtitle: "Hardware GPU Look-Up Table adjustments for RGB curves and tonal balance."
                    )
                }
                .onChange(of: settings.displayTweaksEnabled) { _, enabled in
                    if enabled {
                        applyCurrentSettings()
                    } else {
                        service.restoreGamma()
                    }
                }

                if !displays.isEmpty {
                    Picker(selection: $bSettings.displayTweaksDisplayID) {
                        ForEach(displays) { display in
                            Text(display.name).tag(display.id)
                        }
                    } label: {
                        Text("Target display")
                        Text("Choose which screen to calibrate.")
                    }
                    .onChange(of: settings.displayTweaksDisplayID) { _, _ in
                        if settings.displayTweaksEnabled {
                            applyCurrentSettings()
                        }
                    }
                }
            } header: {
                Text("Display Tweaks")
            }

            if settings.displayTweaksEnabled {
                Section {
                    VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                        Text("Hardware Transfer Curve")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        GammaCurveCanvas(redTable: tables.r, greenTable: tables.g, blueTable: tables.b)
                    }
                    .padding(.vertical, Theme.Spacing.xs)

                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: Theme.Spacing.xs) {
                            ForEach(DisplayTweaksPreset.allCases) { preset in
                                Button {
                                    applyPreset(preset)
                                } label: {
                                    Text(preset.rawValue)
                                        .font(.caption)
                                }
                                .buttonStyle(.bordered)
                                .tint(settings.displayTweaksPreset == preset.rawValue ? Color.accentColor : .secondary)
                            }
                        }
                        .padding(.vertical, 2)
                    }
                } header: {
                    Text("Curve & Presets")
                }

                Section {
                    VStack(spacing: Theme.Spacing.md) {
                        tonalSlider(title: "Blacks", value: $bSettings.displayTweaksBlacks, range: -0.5...0.5, defaultValue: 0.0)
                        tonalSlider(title: "Shadows", value: $bSettings.displayTweaksShadows, range: -0.5...0.5, defaultValue: 0.0)
                        tonalSlider(title: "Highlights", value: $bSettings.displayTweaksHighlights, range: -0.5...0.5, defaultValue: 0.0)
                        tonalSlider(title: "Whites", value: $bSettings.displayTweaksWhites, range: -0.5...0.5, defaultValue: 0.0)
                    }
                    .padding(.vertical, Theme.Spacing.xs)
                } header: {
                    Text("Tonal Range (Blacks, Shadows, Highlights, Whites)")
                } footer: {
                    Text("Blacks lift deep shadow details. Whites compress peak glare for comfortable dark-room viewing.")
                }

                Section {
                    VStack(spacing: Theme.Spacing.md) {
                        gainSlider(title: "Red Channel", value: $bSettings.displayTweaksRed, color: .red)
                        gainSlider(title: "Green Channel", value: $bSettings.displayTweaksGreen, color: .green)
                        gainSlider(title: "Blue Channel", value: $bSettings.displayTweaksBlue, color: .blue)
                    }
                    .padding(.vertical, Theme.Spacing.xs)
                } header: {
                    Text("RGB Color Balance")
                }

                Section {
                    VStack(spacing: Theme.Spacing.md) {
                        tonalSlider(title: "Contrast", value: $bSettings.displayTweaksContrast, range: -0.5...0.5, defaultValue: 0.0)
                        tonalSlider(title: "Brightness", value: $bSettings.displayTweaksBrightness, range: -0.3...0.3, defaultValue: 0.0)
                    }
                    .padding(.vertical, Theme.Spacing.xs)

                    HStack(spacing: Theme.Spacing.md) {
                        Button("Reset All Sliders") {
                            applyPreset(.neutral)
                        }
                        .buttonStyle(.bordered)

                        Button("Restore Stock ColorSync") {
                            settings.displayTweaksEnabled = false
                            service.restoreGamma()
                        }
                        .buttonStyle(.bordered)
                    }
                } header: {
                    Text("Master Contrast & Brightness")
                }
            }
        }
        .task {
            displays = service.enumerateDisplays()
            if settings.displayTweaksDisplayID == 0, let first = displays.first {
                settings.displayTweaksDisplayID = first.id
            }
            if settings.displayTweaksEnabled {
                applyCurrentSettings()
            }
        }
    }

    private func tonalSlider(title: String, value: Binding<Double>, range: ClosedRange<Double>, defaultValue: Double) -> some View {
        HStack(spacing: Theme.Spacing.md) {
            Text(title)
                .frame(width: 80, alignment: .leading)
                .font(.system(size: 13, weight: .medium))

            Slider(value: value, in: range) {
                Text(title)
            }
            .onChange(of: value.wrappedValue) { _, _ in
                settings.displayTweaksPreset = "Custom"
                if settings.displayTweaksEnabled {
                    applyCurrentSettings()
                }
            }

            Text(String(format: "%+.0f%%", value.wrappedValue * 100))
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.secondary)
                .frame(width: 48, alignment: .trailing)

            Button {
                value.wrappedValue = defaultValue
                settings.displayTweaksPreset = "Custom"
                if settings.displayTweaksEnabled {
                    applyCurrentSettings()
                }
            } label: {
                Image(systemName: "arrow.counterclockwise")
                    .font(.system(size: 10))
            }
            .buttonStyle(.borderless)
            .help("Reset \(title) to default")
        }
    }

    private func gainSlider(title: String, value: Binding<Double>, color: Color) -> some View {
        HStack(spacing: Theme.Spacing.md) {
            HStack(spacing: 4) {
                Circle().fill(color).frame(width: 8, height: 8)
                Text(title)
            }
            .frame(width: 110, alignment: .leading)
            .font(.system(size: 13, weight: .medium))

            Slider(value: value, in: 0.5...1.5) {
                Text(title)
            }
            .tint(color)
            .onChange(of: value.wrappedValue) { _, _ in
                settings.displayTweaksPreset = "Custom"
                if settings.displayTweaksEnabled {
                    applyCurrentSettings()
                }
            }

            Text(String(format: "%.0f%%", value.wrappedValue * 100))
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.secondary)
                .frame(width: 48, alignment: .trailing)

            Button {
                value.wrappedValue = 1.0
                settings.displayTweaksPreset = "Custom"
                if settings.displayTweaksEnabled {
                    applyCurrentSettings()
                }
            } label: {
                Image(systemName: "arrow.counterclockwise")
                    .font(.system(size: 10))
            }
            .buttonStyle(.borderless)
            .help("Reset \(title) to 100%")
        }
    }

    private func applyPreset(_ preset: DisplayTweaksPreset) {
        settings.displayTweaksPreset = preset.rawValue
        let v = preset.values
        settings.displayTweaksRed = v.red
        settings.displayTweaksGreen = v.green
        settings.displayTweaksBlue = v.blue
        settings.displayTweaksBlacks = v.blacks
        settings.displayTweaksShadows = v.shadows
        settings.displayTweaksHighlights = v.highlights
        settings.displayTweaksWhites = v.whites
        settings.displayTweaksContrast = v.contrast
        settings.displayTweaksBrightness = v.brightness

        if settings.displayTweaksEnabled {
            applyCurrentSettings()
        }
    }

    private func applyCurrentSettings() {
        service.apply(
            displayID: settings.displayTweaksDisplayID,
            redGain: settings.displayTweaksRed,
            greenGain: settings.displayTweaksGreen,
            blueGain: settings.displayTweaksBlue,
            blacks: settings.displayTweaksBlacks,
            shadows: settings.displayTweaksShadows,
            highlights: settings.displayTweaksHighlights,
            whites: settings.displayTweaksWhites,
            contrast: settings.displayTweaksContrast,
            brightness: settings.displayTweaksBrightness
        )
    }
}
