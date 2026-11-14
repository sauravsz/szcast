import Foundation

/// Running pace and velocity converter: `5:00 min/km in km/h`, `13:24 min/mile in mph`, `10 km/h in min/km`, `5:00 min/km for 10 km`.
enum CalcPace {
    static func evaluate(query: String) -> CalcResult? {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let lower = trimmed.lowercased()
        guard lower.contains(":") || lower.contains("pace") || lower.contains(" for ") || lower.contains(" at ") || lower.contains(" * ") else {
            return nil
        }
        if let paceToSpeed = parsePaceToSpeed(trimmed) {
            return paceToSpeed
        }
        if let paceDistance = parsePaceAndDistance(trimmed) {
            return paceDistance
        }
        return nil
    }

    // MARK: - Pace to Speed (`5:00 min/km in km/h` or `13:24 min/mile in mph`)

    private static func parsePaceToSpeed(_ query: String) -> CalcResult? {
        // Look for connector: in, to, ->, →, as
        let parts = splitConnector(query)
        guard let left = parts?.left, let right = parts?.right else { return nil }

        guard let pace = parsePace(left) else { return nil }
        guard let targetSpeedUnit = parseSpeedUnit(right) else { return nil }

        // Convert pace (seconds per meter) to speed (meters per second)
        guard pace.secondsPerMeter > 0 else { return nil }
        let metersPerSecond = 1.0 / pace.secondsPerMeter

        let targetValue: Double
        let unitLabel: String
        switch targetSpeedUnit {
        case .kmh:
            targetValue = metersPerSecond * 3.6
            unitLabel = "km/h"
        case .mph:
            targetValue = metersPerSecond * 2.2369362920544
            unitLabel = "mph"
        case .mps:
            targetValue = metersPerSecond
            unitLabel = "m/s"
        }

        let formatted = formatNumber(targetValue)
        let display = "\(formatted) \(unitLabel)"

        return CalcResult(
            expression: query,
            sourceBadge: String(localized: "Pace"),
            targetBadge: String(localized: "Speed"),
            payload: .value(display: display, copyText: display),
            canChain: true
        )
    }

    // MARK: - Speed to Pace (`10 km/h in min/km` or `6 mph in min/mile`)

    private static func parseSpeedToPace(_ query: String) -> CalcResult? {
        let parts = splitConnector(query)
        guard let left = parts?.left, let right = parts?.right else { return nil }

        guard let speed = parseSpeed(left) else { return nil }
        guard let targetPaceUnit = parsePaceUnit(right) else { return nil }

        guard speed.metersPerSecond > 0 else { return nil }
        let secondsPerMeter = 1.0 / speed.metersPerSecond

        let totalSeconds: Double
        let unitSuffix: String
        switch targetPaceUnit {
        case .perKm:
            totalSeconds = secondsPerMeter * 1000.0
            unitSuffix = "min/km"
        case .perMile:
            totalSeconds = secondsPerMeter * 1609.344
            unitSuffix = "min/mi"
        }

        let paceDisplay = formatPace(seconds: totalSeconds)
        let display = "\(paceDisplay) \(unitSuffix)"

        return CalcResult(
            expression: query,
            sourceBadge: String(localized: "Speed"),
            targetBadge: String(localized: "Pace"),
            payload: .value(display: display, copyText: display),
            canChain: true
        )
    }

    // MARK: - Pace & Distance (`5:00 min/km for 10 km` or `10 km at 5:00 min/km`)

    private static func parsePaceAndDistance(_ query: String) -> CalcResult? {
        let lower = query.lowercased()
        // Split by " for ", " * ", " at ", " in "
        let splitWords = [" for ", " * ", " at "]
        for word in splitWords {
            if let range = lower.range(of: word) {
                let leftStr = String(query[..<range.lowerBound]).trimmingCharacters(in: .whitespaces)
                let rightStr = String(query[range.upperBound...]).trimmingCharacters(in: .whitespaces)

                if let pace = parsePace(leftStr), let dist = parseDistance(rightStr) {
                    let durationSeconds = pace.secondsPerMeter * dist.meters
                    let timeText = formatDuration(seconds: durationSeconds)
                    return CalcResult(
                        expression: query,
                        sourceBadge: String(localized: "Pace"),
                        targetBadge: String(localized: "Duration"),
                        payload: .value(display: timeText, copyText: timeText),
                        canChain: true
                    )
                }
                if let dist = parseDistance(leftStr), let pace = parsePace(rightStr) {
                    let durationSeconds = pace.secondsPerMeter * dist.meters
                    let timeText = formatDuration(seconds: durationSeconds)
                    return CalcResult(
                        expression: query,
                        sourceBadge: String(localized: "Distance"),
                        targetBadge: String(localized: "Duration"),
                        payload: .value(display: timeText, copyText: timeText),
                        canChain: true
                    )
                }
            }
        }
        return nil
    }

    // MARK: - Parsing Helpers

    private struct ParsedPace {
        let secondsPerMeter: Double
    }

    private struct ParsedSpeed {
        let metersPerSecond: Double
    }

    private struct ParsedDistance {
        let meters: Double
    }

    private enum SpeedUnit {
        case kmh, mph, mps
    }

    private enum PaceUnit {
        case perKm, perMile
    }

    private static func splitConnector(_ query: String) -> (left: String, right: String)? {
        let lower = query.lowercased()
        let connectors = [" in ", " to ", " -> ", " → ", " as "]
        for conn in connectors {
            if let range = lower.range(of: conn, options: .backwards) {
                let left = String(query[..<range.lowerBound]).trimmingCharacters(in: .whitespaces)
                let right = String(query[range.upperBound...]).trimmingCharacters(in: .whitespaces)
                if !left.isEmpty && !right.isEmpty {
                    return (left, right)
                }
            }
        }
        return nil
    }

    private static func parsePace(_ input: String) -> ParsedPace? {
        var str = input.trimmingCharacters(in: .whitespaces).lowercased()
        if str.hasPrefix("pace ") { str = String(str.dropFirst(5)).trimmingCharacters(in: .whitespaces) }
        if str.hasSuffix(" pace") { str = String(str.dropLast(5)).trimmingCharacters(in: .whitespaces) }

        // Find pace unit: min/km, /km, min/mi, min/mile, /mi, /mile
        let unit: PaceUnit
        if str.contains("min/km") || str.contains("/km") || str.contains("per km") {
            unit = .perKm
        } else if str.contains("min/mi") || str.contains("min/mile") || str.contains("/mi") || str.contains("/mile") || str.contains("per mile") || str.contains("per mi") {
            unit = .perMile
        } else {
            return nil
        }

        // Clean out unit text from string to leave time representation
        for unitStr in ["min/km", "min/mile", "min/mi", "/km", "/mile", "/mi", "per km", "per mile", "per mi"] {
            if let r = str.range(of: unitStr) {
                str.removeSubrange(r)
                break
            }
        }
        str = str.trimmingCharacters(in: .whitespaces)

        // Parse time: "5:00", "13:24", "5.5", "5"
        guard let totalMinutes = parseMinutes(str) else { return nil }
        guard totalMinutes > 0 else { return nil }

        let totalSeconds = totalMinutes * 60.0
        let meters: Double = unit == .perKm ? 1000.0 : 1609.344
        return ParsedPace(secondsPerMeter: totalSeconds / meters)
    }

    private static func parseSpeed(_ input: String) -> ParsedSpeed? {
        let str = input.trimmingCharacters(in: .whitespaces).lowercased()
        let speedUnits: [(String, Double)] = [
            ("km/h", 1.0 / 3.6),
            ("kmh", 1.0 / 3.6),
            ("kph", 1.0 / 3.6),
            ("mph", 0.44704),
            ("mi/h", 0.44704),
            ("m/s", 1.0),
            ("mps", 1.0)
        ]

        for (unitStr, factor) in speedUnits {
            if str.hasSuffix(unitStr) {
                let numStr = String(str.dropLast(unitStr.count)).trimmingCharacters(in: .whitespaces)
                if let val = Double(numStr), val > 0 {
                    return ParsedSpeed(metersPerSecond: val * factor)
                }
            }
        }
        return nil
    }

    private static func parseSpeedUnit(_ input: String) -> SpeedUnit? {
        let lower = input.trimmingCharacters(in: .whitespaces).lowercased()
        switch lower {
        case "km/h", "kmh", "kph", "km/hr": return .kmh
        case "mph", "mi/h", "mi/hr", "miles per hour": return .mph
        case "m/s", "mps", "meters per second": return .mps
        default: return nil
        }
    }

    private static func parsePaceUnit(_ input: String) -> PaceUnit? {
        let lower = input.trimmingCharacters(in: .whitespaces).lowercased()
        switch lower {
        case "min/km", "minkm", "min per km", "/km": return .perKm
        case "min/mi", "min/mile", "minmi", "min per mile", "min per mi", "/mi", "/mile": return .perMile
        default: return nil
        }
    }

    private static func parseDistance(_ input: String) -> ParsedDistance? {
        let lower = input.trimmingCharacters(in: .whitespaces).lowercased()
        if lower == "marathon" { return ParsedDistance(meters: 42195) }
        if lower == "half marathon" { return ParsedDistance(meters: 21097.5) }
        if lower == "5k" { return ParsedDistance(meters: 5000) }
        if lower == "10k" { return ParsedDistance(meters: 10000) }

        let units: [(String, Double)] = [
            ("km", 1000.0),
            ("kilometer", 1000.0),
            ("kilometers", 1000.0),
            ("kilometre", 1000.0),
            ("kilometres", 1000.0),
            ("miles", 1609.344),
            ("mile", 1609.344),
            ("mi", 1609.344),
            ("m", 1.0),
            ("meters", 1.0),
            ("meter", 1.0),
            ("metres", 1.0),
            ("metre", 1.0)
        ]

        for (unitStr, factor) in units {
            if lower.hasSuffix(unitStr) {
                let numStr = String(lower.dropLast(unitStr.count)).trimmingCharacters(in: .whitespaces)
                if let val = Double(numStr), val > 0 {
                    return ParsedDistance(meters: val * factor)
                }
            }
        }
        return nil
    }

    private static func parseMinutes(_ text: String) -> Double? {
        if text.contains(":") {
            let parts = text.split(separator: ":")
            if parts.count == 2, let m = Double(parts[0]), let s = Double(parts[1]) {
                return m + (s / 60.0)
            }
        }
        if let val = Double(text) {
            return val
        }
        return nil
    }

    private static func formatPace(seconds: Double) -> String {
        let totalSec = Int(seconds.rounded())
        let m = totalSec / 60
        let s = totalSec % 60
        return String(format: "%d:%02d", m, s)
    }

    private static func formatDuration(seconds: Double) -> String {
        let totalSec = Int(seconds.rounded())
        let hrs = totalSec / 3600
        let mins = (totalSec % 3600) / 60
        let secs = totalSec % 60

        var parts: [String] = []
        if hrs > 0 { parts.append("\(hrs) hr") }
        if mins > 0 { parts.append("\(mins) min") }
        if secs > 0 && hrs == 0 { parts.append("\(secs) s") }
        if parts.isEmpty { return "0 s" }
        return parts.joined(separator: " ")
    }

    private static func formatNumber(_ value: Double) -> String {
        let rounded = (value * 100).rounded() / 100
        if rounded.truncatingRemainder(dividingBy: 1) == 0 {
            return String(format: "%.0f", rounded)
        }
        var str = String(format: "%.2f", rounded)
        while str.hasSuffix("0") && str.contains(".") {
            str.removeLast()
        }
        if str.hasSuffix(".") { str.removeLast() }
        return str
    }
}
