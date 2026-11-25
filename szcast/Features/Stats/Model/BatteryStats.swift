import Foundation

struct BatteryStats: Sendable {
    let hasBattery: Bool
    let percentage: Int
    let isCharging: Bool
    let isACConnected: Bool
    let timeRemainingMinutes: Int?
    let cycleCount: Int?
    let health: String
    let healthPercentage: Int?
    let currentCapacityMAh: Int?
    let maxCapacityMAh: Int?
    let designCapacityMAh: Int?
    let voltageMillivolts: Int?
    let amperageMilliamps: Int?
    let powerWatts: Double?
    let adapterWatts: Int?
    let temperature: Double?

    static let empty = BatteryStats(
        hasBattery: false,
        percentage: 100,
        isCharging: false,
        isACConnected: true,
        timeRemainingMinutes: nil,
        cycleCount: nil,
        health: "Normal",
        healthPercentage: nil,
        currentCapacityMAh: nil,
        maxCapacityMAh: nil,
        designCapacityMAh: nil,
        voltageMillivolts: nil,
        amperageMilliamps: nil,
        powerWatts: nil,
        adapterWatts: nil,
        temperature: nil
    )
}
