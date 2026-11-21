import Foundation

struct RAMStats: Sendable {
    let usedBytes: UInt64
    let freeBytes: UInt64
    let activeBytes: UInt64
    let inactiveBytes: UInt64
    let wiredBytes: UInt64
    let compressedBytes: UInt64
    let totalBytes: UInt64
    let swapUsedBytes: UInt64
    let swapTotalBytes: UInt64

    var usagePercentage: Double {
        guard totalBytes > 0 else { return 0 }
        return Double(usedBytes) / Double(totalBytes) * 100.0
    }

    var usedGB: Double { Double(usedBytes) / 1_073_741_824.0 }
    var totalGB: Double { Double(totalBytes) / 1_073_741_824.0 }
    var freeGB: Double { Double(freeBytes) / 1_073_741_824.0 }

    static let empty = RAMStats(
        usedBytes: 0,
        freeBytes: 0,
        activeBytes: 0,
        inactiveBytes: 0,
        wiredBytes: 0,
        compressedBytes: 0,
        totalBytes: 17_179_869_184,
        swapUsedBytes: 0,
        swapTotalBytes: 0
    )
}
