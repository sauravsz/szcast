import Foundation

struct SystemProcessInfo: Identifiable, Sendable {
    let id: Int32
    let name: String
    let executablePath: String?
    let cpuPercentage: Double
    let memoryBytes: UInt64

    init(
        id: Int32,
        name: String,
        executablePath: String? = nil,
        cpuPercentage: Double,
        memoryBytes: UInt64
    ) {
        self.id = id
        self.name = name
        self.executablePath = executablePath
        self.cpuPercentage = cpuPercentage
        self.memoryBytes = memoryBytes
    }

    var memoryMB: Double {
        Double(memoryBytes) / 1_048_576.0
    }
}
