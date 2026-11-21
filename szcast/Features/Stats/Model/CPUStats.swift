import Foundation

struct CPUCoreUsage: Identifiable, Sendable {
    let id: Int
    let usagePercentage: Double
}

struct CPUStats: Sendable {
    let totalUsage: Double // 0.0 - 100.0 %
    let userPercentage: Double
    let systemPercentage: Double
    let idlePercentage: Double
    let physicalCores: Int
    let logicalCores: Int
    let coreBreakdown: [CPUCoreUsage]

    static let empty = CPUStats(
        totalUsage: 0,
        userPercentage: 0,
        systemPercentage: 0,
        idlePercentage: 100,
        physicalCores: 8,
        logicalCores: 8,
        coreBreakdown: []
    )
}
