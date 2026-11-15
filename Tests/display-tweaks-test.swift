import Foundation
import CoreGraphics
import AppKit

@main
@MainActor
struct DisplayTweaksTests {
    static var failures = 0
    static var passes = 0

    static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        if condition() {
            passes += 1
        } else {
            failures += 1
            print("FAIL: \(message)")
        }
    }

    static func main() {
        testPresets()
        testNeutralLinearRamp()
        testGainAdjustments()
        testTonalAdjustmentsAndClamping()
        testExtremeValuesClamp()

        print("DisplayTweaksTests: \(passes) passed, \(failures) failed")
        exit(failures == 0 ? 0 : 1)
    }

    static func testPresets() {
        let presets = DisplayTweaksPreset.allCases
        expect(presets.count == 7, "7 presets defined")

        for preset in presets {
            expect(!preset.id.isEmpty, "preset id is non-empty")
            expect(!preset.summary.isEmpty, "preset summary is non-empty")
        }

        let neutral = DisplayTweaksPreset.neutral.values
        expect(neutral.red == 1.0 && neutral.green == 1.0 && neutral.blue == 1.0, "neutral has unit gain")
        expect(neutral.blacks == 0.0 && neutral.shadows == 0.0 && neutral.highlights == 0.0, "neutral has zero tonal offsets")
        expect(neutral.whites == 0.0 && neutral.contrast == 0.0 && neutral.brightness == 0.0, "neutral has zero curve adjustments")

        let nightWarm = DisplayTweaksPreset.nightWarm.values
        expect(nightWarm.red > nightWarm.blue, "night warm reduces blue relative to red")
    }

    static func testNeutralLinearRamp() {
        let service = DisplayTweaksService()
        let (r, g, b) = service.calculateTransferTables()

        expect(r.count == 256, "red table has 256 entries")
        expect(g.count == 256, "green table has 256 entries")
        expect(b.count == 256, "blue table has 256 entries")

        expect(abs(r[0] - 0.0) < 0.001, "table starts at 0.0")
        expect(abs(r[255] - 1.0) < 0.001, "table ends at 1.0")

        var isLinear = true
        for i in 0..<256 {
            let expected = Float(i) / 255.0
            if abs(r[i] - expected) > 0.001 || abs(g[i] - expected) > 0.001 || abs(b[i] - expected) > 0.001 {
                isLinear = false
                break
            }
        }
        expect(isLinear, "neutral curve is exact linear ramp")
    }

    static func testGainAdjustments() {
        let service = DisplayTweaksService()
        let (r, g, b) = service.calculateTransferTables(redGain: 1.2, greenGain: 1.0, blueGain: 0.8)

        expect(r[128] > g[128], "red gain scales red above green")
        expect(b[128] < g[128], "blue reduction scales blue below green")
    }

    static func testTonalAdjustmentsAndClamping() {
        let service = DisplayTweaksService()
        let neutral = service.calculateTransferTables()
        let shadowLifted = service.calculateTransferTables(shadows: 0.4)

        // Shadow adjustment should lift values around index 64 (0.25)
        expect(shadowLifted.r[64] > neutral.r[64], "shadows lift lower-mid values")

        let blackLifted = service.calculateTransferTables(blacks: 0.3)
        expect(blackLifted.r[0] > 0.0, "blacks adjustment lifts the black floor")
    }

    static func testExtremeValuesClamp() {
        let service = DisplayTweaksService()
        let extreme = service.calculateTransferTables(
            redGain: 2.5,
            greenGain: 2.5,
            blueGain: 2.5,
            blacks: 1.0,
            shadows: 1.0,
            highlights: 1.0,
            whites: 1.0,
            contrast: 1.0,
            brightness: 1.0
        )

        var allClamped = true
        for i in 0..<256 {
            if extreme.r[i] < 0.0 || extreme.r[i] > 1.0 ||
               extreme.g[i] < 0.0 || extreme.g[i] > 1.0 ||
               extreme.b[i] < 0.0 || extreme.b[i] > 1.0 {
                allClamped = false
                break
            }
        }
        expect(allClamped, "all transfer table entries strictly clamped to [0.0, 1.0]")
    }
}
