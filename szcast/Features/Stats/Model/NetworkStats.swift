import Foundation

struct NetworkStats: Sendable {
    let interfaceName: String
    let localIP: String
    let downloadBytesPerSecond: Double
    let uploadBytesPerSecond: Double
    let totalDownloadBytes: UInt64
    let totalUploadBytes: UInt64

    static let empty = NetworkStats(
        interfaceName: "en0",
        localIP: "127.0.0.1",
        downloadBytesPerSecond: 0,
        uploadBytesPerSecond: 0,
        totalDownloadBytes: 0,
        totalUploadBytes: 0
    )
}
