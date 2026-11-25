import Foundation

struct CPUCoreUsage: Identifiable, Sendable {
    let id: Int
    let usagePercentage: Double
    let isEfficiency: Bool

    init(id: Int, usagePercentage: Double, isEfficiency: Bool = false) {
        self.id = id
        self.usagePercentage = usagePercentage
        self.isEfficiency = isEfficiency
    }
}

struct CPUStats: Sendable {
    let totalUsage: Double
    let userPercentage: Double
    let systemPercentage: Double
    let idlePercentage: Double
    let physicalCores: Int
    let logicalCores: Int
    let efficiencyUsage: Double?
    let performanceUsage: Double?
    let uptimeSeconds: TimeInterval
    let loadAverage1m: Double
    let loadAverage5m: Double
    let loadAverage15m: Double
    let allCoresFrequencyMHz: Int?
    let efficiencyFrequencyMHz: Int?
    let performanceFrequencyMHz: Int?
    let coreBreakdown: [CPUCoreUsage]

    static let empty = CPUStats(
        totalUsage: 0,
        userPercentage: 0,
        systemPercentage: 0,
        idlePercentage: 100,
        physicalCores: 8,
        logicalCores: 8,
        efficiencyUsage: nil,
        performanceUsage: nil,
        uptimeSeconds: 0,
        loadAverage1m: 0,
        loadAverage5m: 0,
        loadAverage15m: 0,
        allCoresFrequencyMHz: nil,
        efficiencyFrequencyMHz: nil,
        performanceFrequencyMHz: nil,
        coreBreakdown: []
    )
}
