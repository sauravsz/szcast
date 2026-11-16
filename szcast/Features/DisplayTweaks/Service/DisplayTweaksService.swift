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
    private var wakeObserver: Any?
    private var screenObserver: Any?
    private(set) var isApplied = false
    private var lastAppliedGammaSet: (data: GammaSetData, displayID: CGDirectDisplayID?)?

    init() {
        terminateObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.restoreGamma()
        }
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.reapplyIfActive()
        }
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.reapplyIfActive()
        }
    }

    func reapplyIfActive() {
        guard isApplied, let last = lastAppliedGammaSet else { return }
        applyGammaSet(last.data, displayID: last.displayID)
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
        lastAppliedGammaSet = nil
    }

    // MARK: - GammaSet Profile Support (.gammaset)

    struct GammaSetData: Equatable {
        var blackPointR: Double = 0.05
        var blackPointG: Double = 0.05
        var blackPointB: Double = 0.05
        var whitePointR: Double = 0.89
        var whitePointG: Double = 0.89
        var whitePointB: Double = 0.89
        var middlePointR: Double = 1.0
        var middlePointG: Double = 1.0
        var middlePointB: Double = 1.0
        var masterBlack: Double = 0.05
        var masterWhite: Double = 0.89
        var masterMiddle: Double = 1.0
        var gammaPointBlackR: Double = 0.0
        var gammaPointBlackG: Double = 0.0
        var gammaPointBlackB: Double = 0.0
        var gammaPointMiddleR: Double = 1.0
        var gammaPointMiddleG: Double = 1.0
        var gammaPointMiddleB: Double = 1.0
        var gammaPointWhiteR: Double = 1.0
        var gammaPointWhiteG: Double = 1.0
        var gammaPointWhiteB: Double = 1.0
        var blendingMode: Int = 1

        static func parse(from url: URL) -> GammaSetData? {
            guard let data = try? Data(contentsOf: url),
                  let plist = (try? PropertyListSerialization.propertyList(from: data, format: nil)) as? [String: Any]
            else { return nil }

            var res = GammaSetData()
            if let bp = plist["BlackPoint"] as? [String: Any] {
                res.blackPointR = (bp["Red"] as? NSNumber)?.doubleValue ?? 0.05
                res.blackPointG = (bp["Green"] as? NSNumber)?.doubleValue ?? 0.05
                res.blackPointB = (bp["Blue"] as? NSNumber)?.doubleValue ?? 0.05
            }
            if let wp = plist["WhitePoint"] as? [String: Any] {
                res.whitePointR = (wp["Red"] as? NSNumber)?.doubleValue ?? 0.89
                res.whitePointG = (wp["Green"] as? NSNumber)?.doubleValue ?? 0.89
                res.whitePointB = (wp["Blue"] as? NSNumber)?.doubleValue ?? 0.89
            }
            if let mp = plist["MiddlePoint"] as? [String: Any] {
                res.middlePointR = (mp["Red"] as? NSNumber)?.doubleValue ?? 1.0
                res.middlePointG = (mp["Green"] as? NSNumber)?.doubleValue ?? 1.0
                res.middlePointB = (mp["Blue"] as? NSNumber)?.doubleValue ?? 1.0
            }
            if let gpb = plist["v4-GammaPointBlack"] as? [String: Any] {
                res.gammaPointBlackR = (gpb["Red"] as? NSNumber)?.doubleValue ?? 0.0
                res.gammaPointBlackG = (gpb["Green"] as? NSNumber)?.doubleValue ?? 0.0
                res.gammaPointBlackB = (gpb["Blue"] as? NSNumber)?.doubleValue ?? 0.0
            }
            if let gpm = plist["v4-GammaPointMiddle"] as? [String: Any] {
                res.gammaPointMiddleR = (gpm["Red"] as? NSNumber)?.doubleValue ?? 1.0
                res.gammaPointMiddleG = (gpm["Green"] as? NSNumber)?.doubleValue ?? 1.0
                res.gammaPointMiddleB = (gpm["Blue"] as? NSNumber)?.doubleValue ?? 1.0
            }
            if let gpw = plist["v4-GammaPointWhite"] as? [String: Any] {
                res.gammaPointWhiteR = (gpw["Red"] as? NSNumber)?.doubleValue ?? 1.0
                res.gammaPointWhiteG = (gpw["Green"] as? NSNumber)?.doubleValue ?? 1.0
                res.gammaPointWhiteB = (gpw["Blue"] as? NSNumber)?.doubleValue ?? 1.0
            }
            if let mb = plist["v4-MasterBlack"] as? NSNumber { res.masterBlack = mb.doubleValue }
            if let mw = plist["v4-MasterWhite"] as? NSNumber { res.masterWhite = mw.doubleValue }
            if let mm = plist["v4-MasterMiddle"] as? NSNumber { res.masterMiddle = mm.doubleValue }
            if let bm = plist["BlendingMode"] as? NSNumber { res.blendingMode = bm.intValue }
            return res
        }
    }

    /// Calculate 256-entry transfer tables from a GammaSetData configuration.
    func calculateGammaSetTables(_ set: GammaSetData) -> (r: [Float], g: [Float], b: [Float]) {
        var tableR = [Float](repeating: 0, count: 256)
        var tableG = [Float](repeating: 0, count: 256)
        var tableB = [Float](repeating: 0, count: 256)

        let blackR = Float(max(0.0, min(1.0, set.blackPointR)))
        let blackG = Float(max(0.0, min(1.0, set.blackPointG)))
        let blackB = Float(max(0.0, min(1.0, set.blackPointB)))

        let whiteR = Float(max(0.0, min(1.0, set.whitePointR)))
        let whiteG = Float(max(0.0, min(1.0, set.whitePointG)))
        let whiteB = Float(max(0.0, min(1.0, set.whitePointB)))

        let middleR = Float(max(0.1, set.middlePointR))
        let middleG = Float(max(0.1, set.middlePointG))
        let middleB = Float(max(0.1, set.middlePointB))

        for i in 0..<256 {
            let x = Float(i) / 255.0
            let rNorm = middleR == 1.0 ? x : pow(x, middleR)
            let gNorm = middleG == 1.0 ? x : pow(x, middleG)
            let bNorm = middleB == 1.0 ? x : pow(x, middleB)

            tableR[i] = max(0.0, min(1.0, blackR + (whiteR - blackR) * rNorm))
            tableG[i] = max(0.0, min(1.0, blackG + (whiteG - blackG) * gNorm))
            tableB[i] = max(0.0, min(1.0, blackB + (whiteB - blackB) * bNorm))
        }

        return (tableR, tableG, tableB)
    }

    /// Apply an exact GammaSetData configuration to the hardware LUT.
    func applyGammaSet(_ set: GammaSetData, displayID: CGDirectDisplayID? = nil) {
        lastAppliedGammaSet = (set, displayID)
        let target = (displayID != nil && displayID != 0) ? displayID! : CGMainDisplayID()

        let blackR = Float(set.blackPointR)
        let blackG = Float(set.blackPointG)
        let blackB = Float(set.blackPointB)

        let whiteR = Float(set.whitePointR)
        let whiteG = Float(set.whitePointG)
        let whiteB = Float(set.whitePointB)

        let middleR = Float(set.middlePointR)
        let middleG = Float(set.middlePointG)
        let middleB = Float(set.middlePointB)

        let formulaErr = CGSetDisplayTransferByFormula(
            target,
            blackR, whiteR, middleR,
            blackG, whiteG, middleG,
            blackB, whiteB, middleB
        )

        if formulaErr == .success {
            isApplied = true
            return
        }

        let (tableR, tableG, tableB) = calculateGammaSetTables(set)
        var r = tableR
        var g = tableG
        var b = tableB
        let err = CGSetDisplayTransferByTable(target, 256, &r, &g, &b)
        if err == .success {
            isApplied = true
        } else {
            Self.logger.error("CGSetDisplayTransferByTable returned error: \(err.rawValue)")
        }
    }
}
