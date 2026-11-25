import Foundation

struct NetworkStats: Sendable {
    let interfaceName: String
    let interfaceDisplayName: String
    let isInterfaceUp: Bool
    let localIP: String
    let macAddress: String
    let wifiSSID: String?
    let needsLocationPermissionForSSID: Bool
    let isInternetUp: Bool
    let latencyMs: Double?
    let jitterMs: Double?
    let publicIPv4: String?
    let publicCountryCode: String?
    let downloadBytesPerSecond: Double
    let uploadBytesPerSecond: Double
    let totalDownloadBytes: UInt64
    let totalUploadBytes: UInt64
    let connectivityHistory: [Bool]

    static let empty = NetworkStats(
        interfaceName: "en0",
        interfaceDisplayName: "Wi-Fi (en0)",
        isInterfaceUp: false,
        localIP: "127.0.0.1",
        macAddress: "",
        wifiSSID: nil,
        needsLocationPermissionForSSID: false,
        isInternetUp: false,
        latencyMs: nil,
        jitterMs: nil,
        publicIPv4: nil,
        publicCountryCode: nil,
        downloadBytesPerSecond: 0,
        uploadBytesPerSecond: 0,
        totalDownloadBytes: 0,
        totalUploadBytes: 0,
        connectivityHistory: []
    )
}
