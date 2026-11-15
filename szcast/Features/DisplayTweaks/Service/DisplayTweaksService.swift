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
        let blk = Float(blacks)
        let shd = Float(shadows)
        let hgh = Float(highlights)
        let wht = Float(whites)
        let cnt = Float(contrast)
        let brt = Float(brightness)

        for i in 0..<256 {
            let x = Float(i) / 255.0
            var y = x

            // Contrast (S-Curve)
            if cnt != 0.0 {
                let p = cnt > 0 ? max(0.15, 1.0 - cnt * 0.85) : 1.0 / max(0.15, 1.0 + cnt * 0.85)
                let t = 2.0 * y - 1.0
                let tp = copysign(pow(abs(t), p), t)
                y = (tp + 1.0) / 2.0
            }

            // Blacks adjustment (affects deep shadow floor, bottom 25%)
            if x < 0.25 {
                let wb = (1.0 - x / 0.25) * (1.0 - x / 0.25)
                y += blk * wb * 0.30
            }

            // Shadows adjustment (bell curve peaked at 25%)
            if x < 0.60 {
                let ws = sin(Float.pi * min(1.0, x / 0.60))
                y += shd * ws * 0.25
            }

            // Highlights adjustment (bell curve peaked at 75%)
            if x > 0.40 {
                let wh = sin(Float.pi * max(0.0, (x - 0.40) / 0.60))
                y += hgh * wh * 0.25
            }

            // Whites adjustment (affects peak white ceiling, top 25%)
            if x > 0.75 {
                let ww = ((x - 0.75) / 0.25) * ((x - 0.75) / 0.25)
                y += wht * ww * 0.30
            }

            // Linear brightness offset
            y += brt

            // Apply per-channel gain and clamp
            tableR[i] = max(0.0, min(1.0, y * rMul))
            tableG[i] = max(0.0, min(1.0, y * gMul))
            tableB[i] = max(0.0, min(1.0, y * bMul))
        }

        return (tableR, tableG, tableB)
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
