import Foundation

struct SystemProcessInfo: Identifiable, Sendable {
    let id: Int32 // pid
    let name: String
    let cpuPercentage: Double
    let memoryBytes: UInt64

    var memoryMB: Double {
        Double(memoryBytes) / 1_048_576.0
    }
}
