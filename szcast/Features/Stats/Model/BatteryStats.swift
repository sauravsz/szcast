import Foundation

struct BatteryStats: Sendable {
    let hasBattery: Bool
    let percentage: Int // 0 - 100
    let isCharging: Bool
    let isACConnected: Bool
    let timeRemainingMinutes: Int? // nil if calculating or on AC
    let cycleCount: Int?
    let health: String // e.g. "Normal", "Good"
    let temperature: Double?

    static let empty = BatteryStats(
        hasBattery: false,
        percentage: 100,
        isCharging: false,
        isACConnected: true,
        timeRemainingMinutes: nil,
        cycleCount: nil,
        health: "Normal",
        temperature: nil
    )
}
