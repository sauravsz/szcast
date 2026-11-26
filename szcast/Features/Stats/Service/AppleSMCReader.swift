import Foundation
import IOKit

/// Read-only IOKit `AppleSMC` client matching `exelban/stats` sensor decoding for battery power, adapter power, and thermal probes.
final class AppleSMCReader: @unchecked Sendable {
    static let shared = AppleSMCReader()

    private struct KeyData {
        // swiftlint:disable:next large_tuple
        typealias Bytes = (
            UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
            UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
            UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
            UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8
        )

        struct Vers {
            var major: CUnsignedChar = 0
            var minor: CUnsignedChar = 0
            var build: CUnsignedChar = 0
            var reserved: CUnsignedChar = 0
            var release: CUnsignedShort = 0
        }

        struct PLimitData {
            var version: UInt16 = 0
            var length: UInt16 = 0
            var cpuPLimit: UInt32 = 0
            var gpuPLimit: UInt32 = 0
            var memPLimit: UInt32 = 0
        }

        struct KeyInfo {
            var dataSize: UInt32 = 0
            var dataType: UInt32 = 0
            var dataAttributes: UInt8 = 0
        }

        var key: UInt32 = 0
        var vers = Vers()
        var pLimitData = PLimitData()
        var keyInfo = KeyInfo()
        var padding: UInt16 = 0
        var result: UInt8 = 0
        var status: UInt8 = 0
        var data8: UInt8 = 0
        var data32: UInt32 = 0
        var bytes: Bytes = (
            0, 0, 0, 0, 0, 0, 0, 0,
            0, 0, 0, 0, 0, 0, 0, 0,
            0, 0, 0, 0, 0, 0, 0, 0,
            0, 0, 0, 0, 0, 0, 0, 0
        )
    }

    private let lock = NSLock()
    private var connection: io_connect_t = 0
    private var keyInfoCache: [UInt32: KeyData.KeyInfo] = [:]

    private init() {
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(
            kIOMainPortDefault,
            IOServiceMatching("AppleSMC"),
            &iterator
        ) == kIOReturnSuccess else {
            return
        }
        defer { IOObjectRelease(iterator) }

        let device = IOIteratorNext(iterator)
        guard device != 0 else { return }
        defer { IOObjectRelease(device) }

        var conn: io_connect_t = 0
        if IOServiceOpen(device, mach_task_self_, 0, &conn) == kIOReturnSuccess {
            connection = conn
        }
    }

    deinit {
        if connection != 0 {
            IOServiceClose(connection)
            connection = 0
        }
    }

    func readDouble(_ key: String) -> Double? {
        guard key.utf8.count == 4 else { return nil }
        lock.lock()
        defer { lock.unlock() }

        guard connection != 0 else { return nil }

        let code = Self.fourCharCode(key)
        let info: KeyData.KeyInfo
        var cacheable = true
        if let cached = keyInfoCache[code] {
            info = cached
        } else {
            var input = KeyData()
            var output = KeyData()
            input.key = code
            input.data8 = 9 // kSMCGetKeyInfo
            guard call(selector: 2, input: &input, output: &output) == kIOReturnSuccess,
                  output.result == 0,
                  output.keyInfo.dataSize > 0 else {
                return nil
            }
            info = output.keyInfo
            cacheable = info.dataSize <= 32 && info.dataType != 0
        }

        var readInput = KeyData()
        var readOutput = KeyData()
        readInput.key = code
        readInput.keyInfo.dataSize = info.dataSize
        readInput.data8 = 5 // kSMCReadKey
        guard call(selector: 2, input: &readInput, output: &readOutput) == kIOReturnSuccess,
              readOutput.result == 0 else {
            keyInfoCache.removeValue(forKey: code)
            return nil
        }

        if cacheable {
            keyInfoCache[code] = info
        }

        let count = min(Int(info.dataSize), 32)
        guard count > 0 else { return nil }
        let bytes = withUnsafeBytes(of: readOutput.bytes) { Array($0.prefix(count)) }
        guard bytes.contains(where: { $0 != 0 }) else { return nil }

        return Self.decode(dataType: Self.fourCharString(info.dataType), bytes: bytes)
    }

    private func call(selector: UInt32, input: inout KeyData, output: inout KeyData) -> kern_return_t {
        let inSize = MemoryLayout<KeyData>.stride
        var outSize = MemoryLayout<KeyData>.stride
        return IOConnectCallStructMethod(connection, selector, &input, inSize, &output, &outSize)
    }

    private static func fourCharCode(_ key: String) -> UInt32 {
        key.utf8.reduce(0) { ($0 << 8) | UInt32($1) }
    }

    private static func fourCharString(_ code: UInt32) -> String {
        let scalars = [24, 16, 8, 0].compactMap { shift -> UnicodeScalar? in
            UnicodeScalar((code >> shift) & 0xFF)
        }
        return String(String.UnicodeScalarView(scalars))
    }

    private static func decode(dataType: String, bytes: [UInt8]) -> Double? {
        switch dataType {
        case "ui8 " where !bytes.isEmpty:
            return Double(bytes[0])
        case "ui16" where bytes.count >= 2:
            return Double((UInt16(bytes[0]) << 8) | UInt16(bytes[1]))
        case "ui32" where bytes.count >= 4:
            let val = (UInt32(bytes[0]) << 24) | (UInt32(bytes[1]) << 16)
                | (UInt32(bytes[2]) << 8) | UInt32(bytes[3])
            return Double(val)
        case "flt " where bytes.count >= 4:
            return bytes.withUnsafeBytes { Double($0.loadUnaligned(as: Float.self)) }
        case "fpe2" where bytes.count >= 2:
            return Double((Int(bytes[0]) << 6) + (Int(bytes[1]) >> 2))
        case "sp1e" where bytes.count >= 2:
            return signedFixed(bytes, divisor: 16384.0)
        case "sp3c" where bytes.count >= 2:
            return signedFixed(bytes, divisor: 4096.0)
        case "sp4b" where bytes.count >= 2:
            return signedFixed(bytes, divisor: 2048.0)
        case "sp5a" where bytes.count >= 2:
            return signedFixed(bytes, divisor: 1024.0)
        case "sp69" where bytes.count >= 2:
            return signedFixed(bytes, divisor: 512.0)
        case "sp78" where bytes.count >= 2:
            return signedFixed(bytes, divisor: 256.0)
        case "sp87" where bytes.count >= 2:
            return signedFixed(bytes, divisor: 128.0)
        case "sp96" where bytes.count >= 2:
            return signedFixed(bytes, divisor: 64.0)
        case "spa5" where bytes.count >= 2:
            return signedFixed(bytes, divisor: 32.0)
        case "spb4" where bytes.count >= 2:
            return signedFixed(bytes, divisor: 16.0)
        case "spf0" where bytes.count >= 2:
            return signedFixed(bytes, divisor: 1.0)
        default:
            return nil
        }
    }

    private static func signedFixed(_ bytes: [UInt8], divisor: Double) -> Double {
        let raw = Int16(bitPattern: (UInt16(bytes[0]) << 8) | UInt16(bytes[1]))
        return Double(raw) / divisor
    }
}
