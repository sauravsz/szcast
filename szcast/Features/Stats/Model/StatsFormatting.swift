import Foundation

enum StatsFormatting {
    static func bytes(_ value: UInt64) -> String {
        let kb = 1024.0
        let mb = kb * 1024.0
        let gb = mb * 1024.0
        let tb = gb * 1024.0
        let d = Double(value)
        if d >= tb {
            return "\(trimmedDecimal(d / tb, maxFractionDigits: 2)) TB"
        }
        if d >= gb {
            return "\(trimmedDecimal(d / gb, maxFractionDigits: 2)) GB"
        }
        if d >= mb {
            return "\(trimmedDecimal(d / mb, maxFractionDigits: 1)) MB"
        }
        if d >= kb {
            return "\(trimmedDecimal(d / kb, maxFractionDigits: 0)) KB"
        }
        return "\(value) B"
    }

    static func speedParts(_ bytesPerSecond: Double) -> (value: String, unit: String) {
        let safe = max(0, bytesPerSecond)
        let kb = 1024.0
        let mb = kb * 1024.0
        let gb = mb * 1024.0
        if safe >= gb {
            return (trimmedDecimal(safe / gb, maxFractionDigits: 1), "GB/s")
        }
        if safe >= mb {
            return (trimmedDecimal(safe / mb, maxFractionDigits: 1), "MB/s")
        }
        return (String(Int((safe / kb).rounded())), "KB/s")
    }

    static func speed(_ bytesPerSecond: Double) -> String {
        let parts = speedParts(bytesPerSecond)
        return "\(parts.value) \(parts.unit)"
    }

    static func uptime(_ seconds: TimeInterval) -> String {
        let totalMinutes = max(0, Int(seconds / 60))
        let days = totalMinutes / 1440
        let hours = (totalMinutes % 1440) / 60
        let minutes = totalMinutes % 60
        var parts: [String] = []
        if days > 0 { parts.append(days == 1 ? "1 day" : "\(days) days") }
        if hours > 0 { parts.append(hours == 1 ? "1 hour" : "\(hours) hours") }
        if minutes > 0 || parts.isEmpty {
            parts.append(minutes == 1 ? "1 minute" : "\(minutes) minutes")
        }
        return parts.joined(separator: ", ")
    }

    static func durationMinutes(_ totalMinutes: Int) -> String {
        let clamped = max(0, totalMinutes)
        let hours = clamped / 60
        let minutes = clamped % 60
        if hours > 0 {
            return "\(hours)h \(minutes)m"
        }
        return "\(minutes)m"
    }

    static func flag(countryCode: String?) -> String? {
        guard let code = countryCode?.uppercased(), code.count == 2 else { return nil }
        var scalars = String.UnicodeScalarView()
        for scalar in code.unicodeScalars {
            guard scalar.value >= 65, scalar.value <= 90,
                  let regional = UnicodeScalar(127397 + scalar.value) else { return nil }
            scalars.append(regional)
        }
        return String(scalars)
    }

    private static func trimmedDecimal(_ value: Double, maxFractionDigits: Int) -> String {
        let formatted = String(format: "%.\(maxFractionDigits)f", value)
        guard formatted.contains(".") else { return formatted }
        var trimmed = formatted
        while trimmed.hasSuffix("0") { trimmed.removeLast() }
        if trimmed.hasSuffix(".") { trimmed.removeLast() }
        return trimmed
    }
}
