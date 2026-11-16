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
                                    updateResolvedPoints()
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

            let defaultGammaPath = "/Users/sz/Downloads/Untitled.gammaset"
            if FileManager.default.fileExists(atPath: defaultGammaPath),
               let parsed = DisplayTweaksService.GammaSetData.parse(from: URL(fileURLWithPath: defaultGammaPath)) {
                gammaSet = parsed
            }
            updateResolvedPoints()

            if settings.displayTweaksEnabled {
                service.applyGammaSet(gammaSet, displayID: settings.displayTweaksDisplayID)
            } else {
                service.restoreGamma()
            }
        }
    }

    private func updateResolvedPoints() {
        gammaSet.blackPointR = max(0.0, min(1.0, gammaSet.masterBlack + gammaSet.gammaPointBlackR))
        gammaSet.blackPointG = max(0.0, min(1.0, gammaSet.masterBlack + gammaSet.gammaPointBlackG))
        gammaSet.blackPointB = max(0.0, min(1.0, gammaSet.masterBlack + gammaSet.gammaPointBlackB))

        gammaSet.middlePointR = max(0.1, gammaSet.masterMiddle * gammaSet.gammaPointMiddleR)
        gammaSet.middlePointG = max(0.1, gammaSet.masterMiddle * gammaSet.gammaPointMiddleG)
        gammaSet.middlePointB = max(0.1, gammaSet.masterMiddle * gammaSet.gammaPointMiddleB)

        gammaSet.whitePointR = max(0.0, min(1.0, gammaSet.masterWhite * gammaSet.gammaPointWhiteR))
        gammaSet.whitePointG = max(0.0, min(1.0, gammaSet.masterWhite * gammaSet.gammaPointWhiteG))
        gammaSet.whitePointB = max(0.0, min(1.0, gammaSet.masterWhite * gammaSet.gammaPointWhiteB))
    }

    private func onGammaSetChanged() {
        updateResolvedPoints()
        settings.displayTweaksPreset = "Custom"
        if !settings.displayTweaksEnabled {
            settings.displayTweaksEnabled = true
        }
        service.applyGammaSet(gammaSet, displayID: settings.displayTweaksDisplayID)
    }

    private func resetToDefaults() {
        gammaSet = DisplayTweaksService.GammaSetData(
            blackPointR: 0.0, blackPointG: 0.0, blackPointB: 0.0,
            whitePointR: 1.0, whitePointG: 1.0, whitePointB: 1.0,
            middlePointR: 1.0, middlePointG: 1.0, middlePointB: 1.0,
            masterBlack: 0.0, masterWhite: 1.0, masterMiddle: 1.0,
            gammaPointBlackR: 0.0, gammaPointBlackG: 0.0, gammaPointBlackB: 0.0,
            gammaPointMiddleR: 1.0, gammaPointMiddleG: 1.0, gammaPointMiddleB: 1.0,
            gammaPointWhiteR: 1.0, gammaPointWhiteG: 1.0, gammaPointWhiteB: 1.0
        )
        updateResolvedPoints()
        settings.displayTweaksPreset = "Default"
        settings.displayTweaksEnabled = false
        service.restoreGamma()
    }

    private func applyPreset(_ preset: DisplayTweaksPreset) {
        settings.displayTweaksPreset = preset.rawValue

        if preset == .neutral {
            resetToDefaults()
            return
        }

        if preset == .gammaControl {
            let defaultGammaPath = "/Users/sz/Downloads/Untitled.gammaset"
            if FileManager.default.fileExists(atPath: defaultGammaPath),
               let parsed = DisplayTweaksService.GammaSetData.parse(from: URL(fileURLWithPath: defaultGammaPath)) {
                gammaSet = parsed
            } else {
                gammaSet = DisplayTweaksService.GammaSetData(
                    blackPointR: 0.05, blackPointG: 0.05, blackPointB: 0.05,
                    whitePointR: 0.89, whitePointG: 0.89, whitePointB: 0.89,
                    middlePointR: 1.0, middlePointG: 1.0, middlePointB: 1.0,
                    masterBlack: 0.05, masterWhite: 0.89, masterMiddle: 1.0,
                    gammaPointBlackR: 0.0, gammaPointBlackG: 0.0, gammaPointBlackB: 0.0,
                    gammaPointMiddleR: 1.0, gammaPointMiddleG: 1.0, gammaPointMiddleB: 1.0,
                    gammaPointWhiteR: 1.0, gammaPointWhiteG: 1.0, gammaPointWhiteB: 1.0
                )
            }
        } else {
            let v = preset.values
            gammaSet = DisplayTweaksService.GammaSetData(
                blackPointR: max(0.0, v.blacks),
                blackPointG: max(0.0, v.blacks),
                blackPointB: max(0.0, v.blacks),
                whitePointR: v.whites > 0 ? v.whites : (1.0 + v.whites),
                whitePointG: v.whites > 0 ? v.whites : (1.0 + v.whites),
                whitePointB: v.whites > 0 ? v.whites : (1.0 + v.whites),
                middlePointR: v.contrast != 0 ? (1.0 - v.contrast * 0.3) : 1.0,
                middlePointG: v.contrast != 0 ? (1.0 - v.contrast * 0.3) : 1.0,
                middlePointB: v.contrast != 0 ? (1.0 - v.contrast * 0.3) : 1.0,
                masterBlack: max(0.0, v.blacks),
                masterWhite: v.whites > 0 ? v.whites : (1.0 + v.whites),
                masterMiddle: 1.0,
                gammaPointBlackR: 0.0, gammaPointBlackG: 0.0, gammaPointBlackB: 0.0,
                gammaPointMiddleR: v.red, gammaPointMiddleG: v.green, gammaPointMiddleB: v.blue,
                gammaPointWhiteR: 1.0, gammaPointWhiteG: 1.0, gammaPointWhiteB: 1.0
            )
        }

        updateResolvedPoints()
        settings.displayTweaksEnabled = true
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
                updateResolvedPoints()
                settings.displayTweaksPreset = "Gamma Control"
                settings.displayTweaksEnabled = true
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
