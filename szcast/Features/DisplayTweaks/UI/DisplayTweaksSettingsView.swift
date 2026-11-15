import SwiftUI

struct DisplayTweaksSettingsView: View {
    @Environment(AppSettings.self) private var settings
    private let service = DisplayTweaksService.shared
    @State private var displays: [DisplayTweaksService.DisplayChoice] = []

    var body: some View {
        @Bindable var bSettings = settings

        let tables = service.calculateTransferTablesPercent(
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

        return Form {
            Section {
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
                Text("Display Selection")
            }

            // MARK: - Lunar Pro Style Gamma Box
            Section {
                VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                    // Header row: Gamma title, subtitle, and action buttons
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Gamma")
                                .font(.system(size: 15, weight: .bold))
                            Text("Software Gamma tables alteration\nKeep this disabled when using f.lux")
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                        }

                        Spacer()

                        HStack(spacing: 8) {
                            Button {
                                bSettings.displayTweaksEnabled.toggle()
                                if settings.displayTweaksEnabled {
                                    applyCurrentSettings()
                                } else {
                                    service.restoreGamma()
                                }
                            } label: {
                                Text(settings.displayTweaksEnabled ? "Enabled" : "Disabled")
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundStyle(settings.displayTweaksEnabled ? Color.green : Color.secondary)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 4)
                                    .background(
                                        Capsule()
                                            .fill(settings.displayTweaksEnabled ? Color.green.opacity(0.15) : Color.primary.opacity(0.08))
                                    )
                            }
                            .buttonStyle(.plain)

                            Button {
                                resetToDefaults()
                            } label: {
                                Text("Reset")
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundStyle(Color.red)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 4)
                                    .background(
                                        Capsule()
                                            .fill(Color.red.opacity(0.15))
                                    )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.bottom, 4)

                    // Sliders 0 to 100 like Lunar Pro
                    VStack(spacing: 10) {
                        LunarPillSlider(
                            title: "Red",
                            value: $bSettings.displayTweaksRed,
                            range: 0...100,
                            fillColor: Color(red: 0.95, green: 0.28, blue: 0.25)
                        ) {
                            onSliderChanged()
                        }

                        LunarPillSlider(
                            title: "Green",
                            value: $bSettings.displayTweaksGreen,
                            range: 0...100,
                            fillColor: Color(red: 0.25, green: 0.82, blue: 0.35)
                        ) {
                            onSliderChanged()
                        }

                        LunarPillSlider(
                            title: "Blue",
                            value: $bSettings.displayTweaksBlue,
                            range: 0...100,
                            fillColor: Color(red: 0.18, green: 0.52, blue: 0.96)
                        ) {
                            onSliderChanged()
                        }

                        LunarPillSlider(
                            title: "Blacks",
                            value: $bSettings.displayTweaksBlacks,
                            range: 0...100,
                            fillColor: Color(white: 0.12),
                            textColor: Color.white,
                            borderColor: Color.white.opacity(0.4),
                            trackBgColor: Color.white.opacity(0.12)
                        ) {
                            onSliderChanged()
                        }

                        LunarPillSlider(
                            title: "Whites",
                            value: $bSettings.displayTweaksWhites,
                            range: 0...100,
                            fillColor: Color.white,
                            textColor: Color.black,
                            borderColor: Color.white,
                            trackBgColor: Color.white.opacity(0.20)
                        ) {
                            onSliderChanged()
                        }
                    }
                }
                .padding(.vertical, 4)
            } header: {
                Text("Hardware Gamma (0 to 100)")
            }

            // MARK: - Brightness & Contrast (FaceLight Style)
            Section {
                VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Brightness & Contrast")
                            .font(.system(size: 13, weight: .semibold))
                        Text("Hardware Look-Up Table offsets for brightness and dynamic range.")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                    .padding(.bottom, 2)

                    VStack(spacing: 10) {
                        LunarPillSlider(
                            title: "Brightness",
                            value: $bSettings.displayTweaksBrightness,
                            range: 0...100,
                            fillColor: Color(red: 0.96, green: 0.80, blue: 0.58),
                            textColor: Color.black,
                            iconName: "sun.max.fill"
                        ) {
                            onSliderChanged()
                        }

                        LunarPillSlider(
                            title: "Contrast",
                            value: $bSettings.displayTweaksContrast,
                            range: 0...100,
                            fillColor: Color(red: 0.96, green: 0.80, blue: 0.58),
                            textColor: Color.black,
                            iconName: "circle.righthalf.filled"
                        ) {
                            onSliderChanged()
                        }
                    }
                }
                .padding(.vertical, 4)
            } header: {
                Text("Display Range (0 to 100)")
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
                Text("Transfer Curve & Presets")
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

    private func onSliderChanged() {
        settings.displayTweaksPreset = "Custom"
        if !settings.displayTweaksEnabled {
            settings.displayTweaksEnabled = true
        }
        applyCurrentSettings()
    }

    private func resetToDefaults() {
        settings.displayTweaksRed = 50.0
        settings.displayTweaksGreen = 50.0
        settings.displayTweaksBlue = 50.0
        settings.displayTweaksBlacks = 0.0
        settings.displayTweaksWhites = 100.0
        settings.displayTweaksContrast = 50.0
        settings.displayTweaksBrightness = 50.0
        settings.displayTweaksShadows = 50.0
        settings.displayTweaksHighlights = 50.0
        settings.displayTweaksPreset = "Default"
        if settings.displayTweaksEnabled {
            applyCurrentSettings()
        }
    }

    private func applyPreset(_ preset: DisplayTweaksPreset) {
        settings.displayTweaksPreset = preset.rawValue
        let v = preset.percentValues
        settings.displayTweaksRed = v.red
        settings.displayTweaksGreen = v.green
        settings.displayTweaksBlue = v.blue
        settings.displayTweaksBlacks = v.blacks
        settings.displayTweaksShadows = v.shadows
        settings.displayTweaksHighlights = v.highlights
        settings.displayTweaksWhites = v.whites
        settings.displayTweaksContrast = v.contrast
        settings.displayTweaksBrightness = v.brightness

        if !settings.displayTweaksEnabled {
            settings.displayTweaksEnabled = true
        }
        applyCurrentSettings()
    }

    private func applyCurrentSettings() {
        service.applyPercent(
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
    }
}

// MARK: - Lunar Pro Style Pill Slider (0..100)

struct LunarPillSlider: View {
    let title: String
    @Binding var value: Double
    var range: ClosedRange<Double> = 0...100
    let fillColor: Color
    var textColor: Color = .white
    var borderColor: Color? = nil
    var trackBgColor: Color? = nil
    var iconName: String? = nil
    var onChanged: (() -> Void)? = nil

    private static let thumbWidth: CGFloat = 38
    private static let trackHeight: CGFloat = 22

    var body: some View {
        HStack(spacing: 12) {
            Text(title)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.primary)
                .frame(width: 80, alignment: .leading)

            GeometryReader { geo in
                let totalWidth = geo.size.width
                let clamped = min(max(value, range.lowerBound), range.upperBound)
                let pct = CGFloat((clamped - range.lowerBound) / (range.upperBound - range.lowerBound))
                let availableTravel = max(0, totalWidth - Self.thumbWidth)
                let thumbX = availableTravel * pct
                let fillWidth = max(Self.thumbWidth, thumbX + Self.thumbWidth)

                ZStack(alignment: .leading) {
                    // Track background (muted tinted tone)
                    Capsule()
                        .fill(trackBgColor ?? fillColor.opacity(0.24))
                        .overlay(
                            Capsule().stroke(trackBgColor?.opacity(0.5) ?? fillColor.opacity(0.35), lineWidth: 0.75)
                        )

                    // Filled progress bar up to thumb
                    Capsule()
                        .fill(fillColor.opacity(0.70))
                        .frame(width: fillWidth)

                    // Optional leading icon inside track
                    if let icon = iconName {
                        Image(systemName: icon)
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(textColor.opacity(0.9))
                            .padding(.leading, 8)
                    }

                    // Sliding Pill Thumb with Current Value (matching Lunar exactly)
                    Capsule()
                        .fill(fillColor)
                        .overlay(
                            Capsule().stroke(borderColor ?? Color.white.opacity(0.25), lineWidth: 1)
                        )
                        .overlay(
                            Text("\(Int(clamped.rounded()))")
                                .font(.system(size: 10, weight: .heavy, design: .rounded))
                                .foregroundStyle(textColor)
                        )
                        .shadow(color: Color.black.opacity(0.25), radius: 2, x: 0, y: 1)
                        .frame(width: Self.thumbWidth, height: Self.trackHeight)
                        .offset(x: thumbX)
                }
                .frame(height: Self.trackHeight)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { gesture in
                            let fraction = min(max(gesture.location.x / totalWidth, 0.0), 1.0)
                            let newValue = range.lowerBound + Double(fraction) * (range.upperBound - range.lowerBound)
                            value = newValue.rounded()
                            onChanged?()
                        }
                )
            }
            .frame(height: Self.trackHeight)
        }
    }
}
