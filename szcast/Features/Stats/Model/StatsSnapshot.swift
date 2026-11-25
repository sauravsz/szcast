import Foundation

struct StatsSnapshot: Sendable {
    let timestamp: Date
    let cpu: CPUStats
    let ram: RAMStats
    let disk: DiskStats
    let battery: BatteryStats
    let network: NetworkStats
    let topProcessesByCPU: [SystemProcessInfo]
    let topProcessesByRAM: [SystemProcessInfo]
    let topProcessesByNetwork: [NetworkProcessInfo]

    static let empty = StatsSnapshot(
        timestamp: Date(),
        cpu: .empty,
        ram: .empty,
        disk: .empty,
        battery: .empty,
        network: .empty,
        topProcessesByCPU: [],
        topProcessesByRAM: [],
        topProcessesByNetwork: []
    )
}
