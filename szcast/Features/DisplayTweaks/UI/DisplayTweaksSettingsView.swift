import SwiftUI
import UniformTypeIdentifiers

enum GammaControlTab: String, CaseIterable, Identifiable {
    case black = "Black"
    case middle = "Middle"
    case white = "White"

    var id: String { rawValue }
}

struct DisplayTweaksSettingsView: View {
    @Environment(AppSettings.self) private var settings
    private let service = DisplayTweaksService.shared
    @State private var displays: [DisplayTweaksService.DisplayChoice] = []
    @State private var gammaTab: GammaControlTab = .black
    @State private var gammaSet = DisplayTweaksService.GammaSetData()

    var body: some View {
        @Bindable var bSettings = settings
        let tables = service.calculateGammaSetTables(gammaSet)

        return Form {
            Section {
                if !displays.isEmpty {
                    SettingsRow(
                        title: "Target display",
                        subtitle: "Choose which screen to calibrate."
                    ) {
                        Picker("", selection: $bSettings.displayTweaksDisplayID) {
                            ForEach(displays) { display in
                                Text(display.name).tag(display.id)
                            }
                        }
                        .labelsHidden()
                        .frame(width: 220)
                        .onChange(of: settings.displayTweaksDisplayID) { _, _ in
                            if settings.displayTweaksEnabled {
                                service.applyGammaSet(gammaSet, displayID: settings.displayTweaksDisplayID)
                            }
                        }
                    }
                }
            } header: {
                SettingsSectionHeader(.displayTweaksSelection)
            }

            // MARK: - Gamma Control Native 3-Point Inspector
            Section {
                VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                    SettingsRow(
                        title: "Software Gamma Tables",
                        subtitle: "Hardware Look-Up Table adjustments matching Gamma Control .gammaset profiles."
                    ) {
                        HStack(spacing: 8) {
                            Button(settings.displayTweaksEnabled ? "Enabled" : "Disabled") {
                                bSettings.displayTweaksEnabled.toggle()
                                if settings.displayTweaksEnabled {
                                    gammaSet.updateResolvedPoints()
                                    settings.displayTweaksGammaSet = gammaSet
                                    service.applyGammaSet(gammaSet, displayID: settings.displayTweaksDisplayID)
                                } else {
                                    service.restoreGamma()
                                }
                            }
                            .buttonStyle(.bordered)
                            .tint(settings.displayTweaksEnabled ? .green : .secondary)
                            .controlSize(.regular)

                            Button("Reset") {
                                resetToDefaults()
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.regular)

                            Button("Import .gammaset…") {
                                importGammaSetFile()
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.regular)
                        }
                    }
                    .padding(.vertical, 2)

                    // 3-Point Segmented Switcher (Black / Middle / White)
                    Picker("", selection: $gammaTab) {
                        ForEach(GammaControlTab.allCases) { tab in
                            Text(tab.rawValue).tag(tab)
                        }
                    }
                    .pickerStyle(.segmented)
                    .padding(.vertical, 2)

                    // Active Tab Sliders
                    VStack(spacing: 8) {
                        switch gammaTab {
                        case .black:
                            GammaControlSliderRow(
                                title: "Black Point Luminance",
                                value: $gammaSet.masterBlack,
                                range: 0.00...0.40
                            ) { onGammaSetChanged() }

                            GammaControlSliderRow(
                                title: "Red",
                                titleColor: Color(red: 0.95, green: 0.55, blue: 0.55),
                                value: $gammaSet.gammaPointBlackR,
                                range: 0.00...1.00
                            ) { onGammaSetChanged() }

                            GammaControlSliderRow(
                                title: "Green",
                                titleColor: Color(red: 0.55, green: 0.85, blue: 0.55),
                                value: $gammaSet.gammaPointBlackG,
                                range: 0.00...1.00
                            ) { onGammaSetChanged() }

                            GammaControlSliderRow(
                                title: "Blue",
                                titleColor: Color(red: 0.55, green: 0.65, blue: 0.95),
                                value: $gammaSet.gammaPointBlackB,
                                range: 0.00...1.00
                            ) { onGammaSetChanged() }

                        case .middle:
                            GammaControlSliderRow(
                                title: "Gray Balance",
                                value: $gammaSet.masterMiddle,
                                range: 0.50...2.00
                            ) { onGammaSetChanged() }

                            GammaControlSliderRow(
                                title: "Red",
                                titleColor: Color(red: 0.95, green: 0.55, blue: 0.55),
                                value: $gammaSet.gammaPointMiddleR,
                                range: 0.50...1.50
                            ) { onGammaSetChanged() }

                            GammaControlSliderRow(
                                title: "Green",
                                titleColor: Color(red: 0.55, green: 0.85, blue: 0.55),
                                value: $gammaSet.gammaPointMiddleG,
                                range: 0.50...1.50
                            ) { onGammaSetChanged() }

                            GammaControlSliderRow(
                                title: "Blue",
                                titleColor: Color(red: 0.55, green: 0.65, blue: 0.95),
                                value: $gammaSet.gammaPointMiddleB,
                                range: 0.50...1.50
                            ) { onGammaSetChanged() }

                        case .white:
                            GammaControlSliderRow(
                                title: "White Point Luminance",
                                value: $gammaSet.masterWhite,
                                range: 0.50...1.00
                            ) { onGammaSetChanged() }

                            GammaControlSliderRow(
                                title: "Red",
                                titleColor: Color(red: 0.95, green: 0.55, blue: 0.55),
                                value: $gammaSet.gammaPointWhiteR,
                                range: 0.50...1.50
                            ) { onGammaSetChanged() }

                            GammaControlSliderRow(
                                title: "Green",
                                titleColor: Color(red: 0.55, green: 0.85, blue: 0.55),
                                value: $gammaSet.gammaPointWhiteG,
                                range: 0.50...1.50
                            ) { onGammaSetChanged() }

                            GammaControlSliderRow(
                                title: "Blue",
                                titleColor: Color(red: 0.55, green: 0.65, blue: 0.95),
                                value: $gammaSet.gammaPointWhiteB,
                                range: 0.50...1.50
                            ) { onGammaSetChanged() }
                        }
                    }

                    // Reference Calibration Target Bar
                    GammaControlReferenceBar()
                }
                .padding(.vertical, 4)
            } header: {
                SettingsSectionHeader(.displayTweaksGamma)
            }

            // MARK: - Curve Preview & Presets
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
                SettingsSectionHeader(.displayTweaksCurve)
            }
        }
        .formStyle(.grouped)
        .settingsScrollTarget(.displayTweaks)
        .task {
            displays = service.enumerateDisplays()
            if settings.displayTweaksDisplayID == 0, let first = displays.first {
                settings.displayTweaksDisplayID = first.id
            }

            gammaSet = settings.displayTweaksGammaSet
            gammaSet.updateResolvedPoints()

            if settings.displayTweaksEnabled {
                service.applyGammaSet(gammaSet, displayID: settings.displayTweaksDisplayID)
            } else {
                service.restoreGamma()
            }
        }
    }

    private func onGammaSetChanged() {
        gammaSet.updateResolvedPoints()
        settings.displayTweaksPreset = "Custom"
        if !settings.displayTweaksEnabled {
            settings.displayTweaksEnabled = true
        }
        settings.displayTweaksGammaSet = gammaSet
        service.applyGammaSet(gammaSet, displayID: settings.displayTweaksDisplayID)
    }

    private func resetToDefaults() {
        gammaSet = DisplayTweaksService.GammaSetData.make(for: .neutral)
        settings.displayTweaksPreset = "Default"
        settings.displayTweaksEnabled = false
        settings.displayTweaksGammaSet = gammaSet
        service.restoreGamma()
    }

    private func applyPreset(_ preset: DisplayTweaksPreset) {
        if preset == .neutral {
            resetToDefaults()
            return
        }

        gammaSet = DisplayTweaksService.GammaSetData.make(for: preset)
        settings.displayTweaksPreset = preset.rawValue
        settings.displayTweaksEnabled = true
        settings.displayTweaksGammaSet = gammaSet
        service.applyGammaSet(gammaSet, displayID: settings.displayTweaksDisplayID)
    }

    private func importGammaSetFile() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [UTType(filenameExtension: "gammaset") ?? .data]
        panel.prompt = "Import"
        panel.message = "Choose a Gamma Control .gammaset file to import"

        if panel.runModal() == .OK, let url = panel.url {
            if let data = DisplayTweaksService.GammaSetData.parse(from: url) {
                gammaSet = data
                gammaSet.updateResolvedPoints()
                settings.displayTweaksPreset = "Gamma Control"
                settings.displayTweaksEnabled = true
                settings.displayTweaksGammaSet = gammaSet
                service.applyGammaSet(gammaSet, displayID: settings.displayTweaksDisplayID)
            }
        }
    }
}

// MARK: - Gamma Control Slider Row

struct GammaControlSliderRow: View {
    let title: String
    var titleColor: Color = .primary
    @Binding var value: Double
    var range: ClosedRange<Double>
    var onChanged: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(titleColor)
                .frame(width: 170, alignment: .leading)

            Slider(value: $value, in: range, step: 0.01)
                .onChange(of: value) { _, _ in onChanged() }

            Text(String(format: "%.2f", value))
                .font(.system(size: 13, design: .monospaced))
                .foregroundColor(.primary)
                .frame(width: 44, alignment: .trailing)
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(Color(nsColor: .controlBackgroundColor))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .stroke(Color.secondary.opacity(0.3), lineWidth: 0.5)
                )
        }
        .padding(.vertical, 1)
    }
}

// MARK: - Gamma Control Calibration Bar

struct GammaControlReferenceBar: View {
    var body: some View {
        VStack(spacing: 5) {
            // 5-box checker pattern (Gray, Red, Green, Blue, White)
            HStack(spacing: 6) {
                CheckeredBox(color: Color(white: 0.5))
                CheckeredBox(color: Color.red)
                CheckeredBox(color: Color.green)
                CheckeredBox(color: Color.blue)
                CheckeredBox(color: Color.white)
            }
            .frame(height: 34)

            // Grayscale gradient ramp
            LinearGradient(
                colors: [.black, .white],
                startPoint: .leading,
                endPoint: .trailing
            )
            .frame(height: 10)
            .cornerRadius(2)
            .overlay(
                RoundedRectangle(cornerRadius: 2)
                    .stroke(Color.secondary.opacity(0.4), lineWidth: 0.5)
            )

            // RGB color gradient ramp
            LinearGradient(
                stops: [
                    .init(color: .black, location: 0.0),
                    .init(color: .red, location: 0.33),
                    .init(color: .green, location: 0.66),
                    .init(color: .blue, location: 1.0)
                ],
                startPoint: .leading,
                endPoint: .trailing
            )
            .frame(height: 10)
            .cornerRadius(2)
            .overlay(
                RoundedRectangle(cornerRadius: 2)
                    .stroke(Color.secondary.opacity(0.4), lineWidth: 0.5)
            )
        }
        .padding(.vertical, 4)
    }
}

struct CheckeredBox: View {
    let color: Color
    var body: some View {
        ZStack {
            Rectangle()
                .fill(Color.black.opacity(0.4))
            GeometryReader { geo in
                let w = geo.size.width / 2
                let h = geo.size.height / 2
                Path { p in
                    p.addRect(CGRect(x: 0, y: 0, width: w, height: h))
                    p.addRect(CGRect(x: w, y: h, width: w, height: h))
                }
                .fill(color)
            }
        }
        .overlay(
            RoundedRectangle(cornerRadius: 2)
                .stroke(Color.secondary.opacity(0.4), lineWidth: 0.5)
        )
    }
}
