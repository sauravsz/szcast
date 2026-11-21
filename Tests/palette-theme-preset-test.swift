import AppKit
import SwiftUI

@main
struct PaletteThemePresetTest {
    static func main() {
        print("Testing PaletteThemePreset...")

        assert(PaletteThemePreset.allCases.count == 5, "Expected 5 curated presets")

        for preset in PaletteThemePreset.allCases {
            assert(!preset.title.isEmpty, "Preset \(preset) title should not be empty")
            assert(!preset.subtitle.isEmpty, "Preset \(preset) subtitle should not be empty")

            let bg = preset.panelOpaqueBackground
            assert(bg.dark.alphaComponent == 1.0, "Dark panel background must be opaque")
            assert(bg.light.alphaComponent == 1.0, "Light panel background must be opaque")

            let scrim = preset.panelScrim
            assert(scrim.dark.alphaComponent > 0.0, "Dark scrim must have alpha")
            assert(scrim.light.alphaComponent > 0.0, "Light scrim must have alpha")

            assert(preset.selectionFill.dark > 0.0, "Selection fill dark must be positive")
            assert(preset.rowHoverFill.dark > 0.0, "Row hover fill dark must be positive")
            assert(preset.borderStroke.dark > 0.0, "Border stroke dark must be positive")
            assert(preset.separatorStroke.dark > 0.0, "Separator stroke dark must be positive")
            assert(preset.cardFill.dark > 0.0, "Card fill dark must be positive")
            assert(preset.controlSurface.dark > 0.0, "Control surface dark must be positive")
        }

        // Test dynamic switching
        Theme.activePreset = .oledBlack
        assert(Theme.activePreset == .oledBlack, "activePreset should be oledBlack")
        assert(Theme.activePreset.panelOpaqueBackground.dark == .srgbInk(0.0, alpha: 1.0), "oledBlack panelOpaqueBackground should be black")

        Theme.activePreset = .nordicSlate
        assert(Theme.activePreset == .nordicSlate, "activePreset should be nordicSlate")

        Theme.activePreset = .warmEspresso
        assert(Theme.activePreset == .warmEspresso, "activePreset should be warmEspresso")

        Theme.activePreset = .studioLight
        assert(Theme.activePreset == .studioLight, "activePreset should be studioLight")

        Theme.activePreset = .szcastDark
        assert(Theme.activePreset == .szcastDark, "activePreset should be szcastDark")

        print("PaletteThemePresetTest passed successfully.")
    }
}
