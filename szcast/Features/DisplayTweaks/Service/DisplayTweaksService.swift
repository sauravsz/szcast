import AppKit
import CoreGraphics
import Foundation
import OSLog

@MainActor
final class DisplayTweaksService {
    static let shared = DisplayTweaksService()
    private static let logger = Logger(subsystem: "com.sauravsz.szcast", category: "DisplayTweaks")

    struct DisplayChoice: Identifiable, Hashable {
        let id: CGDirectDisplayID
        let name: String
        let isMain: Bool
    }

    private var terminateObserver: Any?
    private(set) var isApplied = false

    init() {
        terminateObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.restoreGamma()
        }
    }

    /// List all currently connected displays.
    func enumerateDisplays() -> [DisplayChoice] {
        var out: [DisplayChoice] = []
        for screen in NSScreen.screens {
            guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else {
                continue
            }
            let displayID = CGDirectDisplayID(number.uint32Value)
            let isMain = displayID == CGMainDisplayID()
            let name = screen.localizedName.isEmpty ? (isMain ? "Main Display" : "External Display \(displayID)") : screen.localizedName
            out.append(DisplayChoice(id: displayID, name: name, isMain: isMain))
        }
        if out.isEmpty {
            out.append(DisplayChoice(id: CGMainDisplayID(), name: "Main Display", isMain: true))
        }
        return out
    }

    /// Calculate 256-entry RGB transfer tables from 0..100 percentage settings.
    func calculateTransferTablesPercent(
        red: Double = 50.0,
        green: Double = 50.0,
        blue: Double = 50.0,
        blacks: Double = 0.0,
        shadows: Double = 50.0,
        highlights: Double = 50.0,
        whites: Double = 100.0,
        contrast: Double = 50.0,
        brightness: Double = 50.0
    ) -> (r: [Float], g: [Float], b: [Float]) {
        var tableR = [Float](repeating: 0, count: 256)
        var tableG = [Float](repeating: 0, count: 256)
        var tableB = [Float](repeating: 0, count: 256)

        let rMul = Float(red / 50.0)
        let gMul = Float(green / 50.0)
        let bMul = Float(blue / 50.0)

        // Exact Gamma Control Black Point & White Point Luminance mapping
        // 0..100 maps to 0.00..0.40 for blacks (default 0% = 0.00, Gamma Control 5% = 0.05)
        // 0..100 maps to 0.50..1.00 for whites (default 100% = 1.00, Gamma Control 89% = 0.89)
        let blackFloor = Float(max(0.0, min(0.40, blacks / 100.0)))
        let whiteCeiling = Float(max(0.50, min(1.0, whites / 100.0)))

        let cnt = Float((contrast - 50.0) / 50.0)
        let brt = Float((brightness - 50.0) / 50.0 * 0.20)

        for i in 0..<256 {
            let x = Float(i) / 255.0
            var y = x

            // Contrast adjustment (S-curve around midpoint 0.5)
            if cnt != 0.0 {
                let p = cnt > 0 ? max(0.20, 1.0 - cnt * 0.70) : 1.0 / max(0.20, 1.0 + abs(cnt) * 0.70)
                let t = 2.0 * y - 1.0
                let tp = copysign(pow(abs(t), p), t)
                y = (tp + 1.0) / 2.0
            }

            // Brightness linear shift
            if brt != 0.0 {
                y += brt
            }
            y = max(0.0, min(1.0, y))

            // Direct Black Point & White Point Luminance scaling:
            // y_final = blackFloor + (whiteCeiling - blackFloor) * y
            let yScaled = blackFloor + (whiteCeiling - blackFloor) * y

            // Per-channel color gain and strict clamping to 0.0..1.0
            tableR[i] = max(0.0, min(1.0, yScaled * rMul))
            tableG[i] = max(0.0, min(1.0, yScaled * gMul))
            tableB[i] = max(0.0, min(1.0, yScaled * bMul))
        }

        return (tableR, tableG, tableB)
    }

    /// Calculate 256-entry RGB transfer tables from settings parameters.
    func calculateTransferTables(
        redGain: Double = 1.0,
        greenGain: Double = 1.0,
        blueGain: Double = 1.0,
        blacks: Double = 0.0,
        shadows: Double = 0.0,
        highlights: Double = 0.0,
        whites: Double = 0.0,
        contrast: Double = 0.0,
        brightness: Double = 0.0
    ) -> (r: [Float], g: [Float], b: [Float]) {
        var tableR = [Float](repeating: 0, count: 256)
        var tableG = [Float](repeating: 0, count: 256)
        var tableB = [Float](repeating: 0, count: 256)

        let rMul = Float(redGain)
        let gMul = Float(greenGain)
        let bMul = Float(blueGain)
        let blackFloor = Float(max(0.0, min(0.40, blacks)))
        let whiteCeiling = Float(max(0.50, min(1.0, whites > 0.0 ? whites : (1.0 + whites))))
        let cnt = Float(contrast)
        let brt = Float(brightness)

        for i in 0..<256 {
            let x = Float(i) / 255.0
            var y = x

            // Contrast (S-Curve)
            if cnt != 0.0 {
                let p = cnt > 0 ? max(0.20, 1.0 - cnt * 0.70) : 1.0 / max(0.20, 1.0 + abs(cnt) * 0.70)
                let t = 2.0 * y - 1.0
                let tp = copysign(pow(abs(t), p), t)
                y = (tp + 1.0) / 2.0
            }

            if brt != 0.0 {
                y += brt
            }
            y = max(0.0, min(1.0, y))

            let yScaled = blackFloor + (whiteCeiling - blackFloor) * y

            tableR[i] = max(0.0, min(1.0, yScaled * rMul))
            tableG[i] = max(0.0, min(1.0, yScaled * gMul))
            tableB[i] = max(0.0, min(1.0, yScaled * bMul))
        }

        return (tableR, tableG, tableB)
    }

    /// Apply calculated gamma curves from 0..100 percentage parameters to targeted display.
    func applyPercent(
        displayID: CGDirectDisplayID? = nil,
        red: Double = 50.0,
        green: Double = 50.0,
        blue: Double = 50.0,
        blacks: Double = 0.0,
        shadows: Double = 50.0,
        highlights: Double = 50.0,
        whites: Double = 100.0,
        contrast: Double = 50.0,
        brightness: Double = 50.0
    ) {
        let (r, g, b) = calculateTransferTablesPercent(
            red: red,
            green: green,
            blue: blue,
            blacks: blacks,
            shadows: shadows,
            highlights: highlights,
            whites: whites,
            contrast: contrast,
            brightness: brightness
        )
        let target = (displayID != nil && displayID != 0) ? displayID! : CGMainDisplayID()
        var redTable = r
        var greenTable = g
        var blueTable = b

        let err = CGSetDisplayTransferByTable(target, 256, &redTable, &greenTable, &blueTable)
        if err == .success {
            isApplied = true
        } else {
            Self.logger.error("CGSetDisplayTransferByTable returned error: \(err.rawValue)")
        }
    }

    /// Apply calculated gamma curves to the targeted display hardware LUT.
    func apply(
        displayID: CGDirectDisplayID? = nil,
        redGain: Double,
        greenGain: Double,
        blueGain: Double,
        blacks: Double,
        shadows: Double,
        highlights: Double,
        whites: Double,
        contrast: Double,
        brightness: Double
    ) {
        let target = (displayID != nil && displayID != 0) ? displayID! : CGMainDisplayID()
        let (r, g, b) = calculateTransferTables(
            redGain: redGain,
            greenGain: greenGain,
            blueGain: blueGain,
            blacks: blacks,
            shadows: shadows,
            highlights: highlights,
            whites: whites,
            contrast: contrast,
            brightness: brightness
        )

        var redTable = r
        var greenTable = g
        var blueTable = b

        let err = CGSetDisplayTransferByTable(target, 256, &redTable, &greenTable, &blueTable)
        if err == .success {
            isApplied = true
        } else {
            Self.logger.error("CGSetDisplayTransferByTable returned error: \(err.rawValue)")
        }
    }

    /// Restore standard macOS ColorSync gamma settings.
    func restoreGamma() {
        CGDisplayRestoreColorSyncSettings()
        isApplied = false
    }
}
