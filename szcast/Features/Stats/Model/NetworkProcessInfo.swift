import Foundation

struct NetworkProcessInfo: Identifiable, Sendable {
    let id: Int32
    let name: String
    let executablePath: String?
    let downloadBytesPerSecond: Double
    let uploadBytesPerSecond: Double
}
