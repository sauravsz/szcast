import Foundation

struct DiskVolume: Identifiable, Sendable {
    var id: String { mountPath }
    let name: String
    let mountPath: String
    let fileSystemType: String?
    let isRemovable: Bool
    let totalBytes: Int64
    let freeBytes: Int64
    let usedBytes: Int64

    var usagePercentage: Double {
        guard totalBytes > 0 else { return 0 }
        return Double(usedBytes) / Double(totalBytes) * 100.0
    }

    var freeGB: Double { Double(freeBytes) / 1_073_741_824.0 }
    var totalGB: Double { Double(totalBytes) / 1_073_741_824.0 }
    var usedGB: Double { Double(usedBytes) / 1_073_741_824.0 }
}

struct DiskStats: Sendable {
    let volumes: [DiskVolume]
    let readBytesPerSecond: Double
    let writeBytesPerSecond: Double
    let totalReadBytes: UInt64
    let totalWriteBytes: UInt64

    var rootVolume: DiskVolume? {
        volumes.first(where: { $0.mountPath == "/" }) ?? volumes.first
    }

    static let empty = DiskStats(
        volumes: [],
        readBytesPerSecond: 0,
        writeBytesPerSecond: 0,
        totalReadBytes: 0,
        totalWriteBytes: 0
    )
}
