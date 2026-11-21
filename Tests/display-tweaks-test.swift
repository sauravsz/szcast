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
        testGammaSetParsing()
        testGammaSetCodableAndPresets()

        print("DisplayTweaksTests: \(passes) passed, \(failures) failed")
        exit(failures == 0 ? 0 : 1)
    }

    static func testGammaSetCodableAndPresets() {
        let gc = DisplayTweaksService.GammaSetData.make(for: .gammaControl)
        expect(abs(gc.masterBlack - 0.05) < 0.001, "gc masterBlack is 0.05")
        expect(abs(gc.masterWhite - 0.89) < 0.001, "gc masterWhite is 0.89")
        expect(abs(gc.blackPointR - 0.05) < 0.001, "gc blackPointR is 0.05")
        expect(abs(gc.whitePointR - 0.89) < 0.001, "gc whitePointR is 0.89")

        let neutral = DisplayTweaksService.GammaSetData.make(for: .neutral)
        expect(abs(neutral.masterBlack - 0.0) < 0.001, "neutral masterBlack is 0.0")
        expect(abs(neutral.masterWhite - 1.0) < 0.001, "neutral masterWhite is 1.0")

        guard let encoded = try? JSONEncoder().encode(gc),
              let decoded = try? JSONDecoder().decode(DisplayTweaksService.GammaSetData.self, from: encoded) else {
            expect(false, "GammaSetData failed to encode or decode JSON")
            return
        }
        expect(decoded == gc, "round-trip JSON encoding preserves GammaSetData")

        var custom = DisplayTweaksService.GammaSetData()
        custom.masterBlack = 0.12
        custom.masterWhite = 0.85
        custom.updateResolvedPoints()
        expect(abs(custom.blackPointR - 0.12) < 0.001, "updateResolvedPoints resolves masterBlack")
        expect(abs(custom.whitePointR - 0.85) < 0.001, "updateResolvedPoints resolves masterWhite")
    }

    static func testGammaSetParsing() {
        let testPath = "/Users/sz/Downloads/Untitled.gammaset"
        if FileManager.default.fileExists(atPath: testPath) {
            let data = DisplayTweaksService.GammaSetData.parse(from: URL(fileURLWithPath: testPath))
            expect(data != nil, "parses Untitled.gammaset plist")
            expect(abs((data?.masterBlack ?? 0) - 0.05) < 0.001, "master black is 0.05")
            expect(abs((data?.masterWhite ?? 0) - 0.89) < 0.001, "master white is 0.89")
            expect(abs((data?.masterMiddle ?? 0) - 1.0) < 0.001, "master middle is 1.0")
        }
    }

    static func testPresets() {
        let presets = DisplayTweaksPreset.allCases
        expect(presets.count == 8, "8 presets defined")

        for preset in presets {
            expect(!preset.id.isEmpty, "preset id is non-empty")
            expect(!preset.summary.isEmpty, "preset summary is non-empty")
        }

        let neutral = DisplayTweaksPreset.neutral.values
        expect(neutral.red == 1.0 && neutral.green == 1.0 && neutral.blue == 1.0, "neutral has unit gain")
        expect(neutral.blacks == 0.0 && neutral.shadows == 0.0 && neutral.highlights == 0.0, "neutral has zero tonal offsets")
        expect(neutral.whites == 0.0 && neutral.contrast == 0.0 && neutral.brightness == 0.0, "neutral has zero curve adjustments")

        let gammaControl = DisplayTweaksPreset.gammaControl.values
        expect(gammaControl.blacks == 0.05, "gamma control has 0.05 black point")
        expect(gammaControl.whites == 0.89, "gamma control has 0.89 white point")

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
        let contrastAdjusted = service.calculateTransferTables(contrast: 0.3)

        // S-curve contrast lifts upper half and compresses lower half
        expect(contrastAdjusted.r[200] > neutral.r[200], "contrast lifts high values")
        expect(contrastAdjusted.r[50] < neutral.r[50], "contrast deepens shadow values")

        let blackLifted = service.calculateTransferTables(blacks: 0.05)
        expect(blackLifted.r[0] > 0.0, "blacks adjustment lifts the black floor")

        let whiteCompressed = service.calculateTransferTablesPercent(whites: 89.0)
        expect(whiteCompressed.r[255] < 1.0, "whites percentage compression lowers the peak ceiling")
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
