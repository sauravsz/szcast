import CommonCrypto
import Foundation

enum TOTPEngine {
    struct TokenInfo: Sendable {
        let currentCode: String
        let currentFormatted: String
        let nextCode: String
        let nextFormatted: String
        let timeRemaining: Int
        let period: Int
        let progress: Double // 1.0 at start of period down to 0.0 at expiration
    }

    /// Base32 character set mapping table
    private static let base32Alphabet: [Character: UInt8] = {
        var map: [Character: UInt8] = [:]
        let chars = "ABCDEFGHIJKLMNOPQRSTUVWXYZ234567"
        for (idx, char) in chars.enumerated() {
            map[char] = UInt8(idx)
        }
        return map
    }()

    /// Decodes a RFC 4648 Base32 encoded string into raw key bytes.
    static func decodeBase32(_ string: String) -> Data? {
        let clean = string
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "-", with: "")
            .uppercased()

        guard !clean.isEmpty else { return nil }

        var buffer: UInt64 = 0
        var bitsLeft = 0
        var result = Data()

        for char in clean {
            if char == "=" { break } // Padding
            guard let val = base32Alphabet[char] else {
                return nil // Reject invalid characters
            }
            buffer = (buffer << 5) | UInt64(val)
            bitsLeft += 5

            if bitsLeft >= 8 {
                let byte = UInt8((buffer >> (bitsLeft - 8)) & 0xFF)
                result.append(byte)
                bitsLeft -= 8
            }
        }

        return result.isEmpty ? nil : result
    }

    /// Generates raw TOTP digits for a given timestamp.
    static func generateCode(
        secret: String,
        timestamp: Date = Date(),
        period: Int = 30,
        digits: Int = 6,
        algorithm: TOTPAlgorithm = .sha1
    ) -> String {
        guard let keyData = decodeBase32(secret) else {
            return String(repeating: "0", count: digits)
        }

        let p = period > 0 ? period : 30
        let d = digits > 0 ? digits : 6
        let timeInterval = UInt64(timestamp.timeIntervalSince1970)
        var counter = (timeInterval / UInt64(p)).bigEndian

        let (cchmacAlgorithm, digestLength): (CCHmacAlgorithm, Int) = {
            switch algorithm {
            case .sha1:
                return (CCHmacAlgorithm(kCCHmacAlgSHA1), Int(CC_SHA1_DIGEST_LENGTH))
            case .sha256:
                return (CCHmacAlgorithm(kCCHmacAlgSHA256), Int(CC_SHA256_DIGEST_LENGTH))
            case .sha512:
                return (CCHmacAlgorithm(kCCHmacAlgSHA512), Int(CC_SHA512_DIGEST_LENGTH))
            }
        }()

        var hash = [UInt8](repeating: 0, count: digestLength)
        keyData.withUnsafeBytes { keyBytes in
            withUnsafeBytes(of: &counter) { counterBytes in
                CCHmac(
                    cchmacAlgorithm,
                    keyBytes.baseAddress,
                    keyData.count,
                    counterBytes.baseAddress,
                    MemoryLayout<UInt64>.size,
                    &hash
                )
            }
        }

        let offset = Int(hash[digestLength - 1] & 0x0F)
        let truncated = (UInt32(hash[offset] & 0x7F) << 24)
            | (UInt32(hash[offset + 1]) << 16)
            | (UInt32(hash[offset + 2]) << 8)
            | UInt32(hash[offset + 3])

        var divisor: UInt32 = 1
        for _ in 0..<d {
            divisor *= 10
        }
        let pin = truncated % divisor
        return String(format: "%0*u", d, pin)
    }

    /// Formats TOTP string with a readability space gutter (e.g. "123 456").
    static func formatCode(_ code: String) -> String {
        if code.count == 6 {
            let mid = code.index(code.startIndex, offsetBy: 3)
            return "\(code[..<mid]) \(code[mid...])"
        } else if code.count == 8 {
            let mid = code.index(code.startIndex, offsetBy: 4)
            return "\(code[..<mid]) \(code[mid...])"
        } else if code.count == 7 {
            let mid = code.index(code.startIndex, offsetBy: 3)
            return "\(code[..<mid]) \(code[mid...])"
        }
        return code
    }

    /// Computes full token details including countdown time remaining and next code.
    static func tokenInfo(
        secret: String,
        timestamp: Date = Date(),
        period: Int = 30,
        digits: Int = 6,
        algorithm: TOTPAlgorithm = .sha1
    ) -> TokenInfo {
        let p = period > 0 ? period : 30
        let currentSeconds = timestamp.timeIntervalSince1970
        let elapsedInPeriod = currentSeconds.truncatingRemainder(dividingBy: Double(p))
        var remaining = Int(ceil(Double(p) - elapsedInPeriod))
        if remaining <= 0 { remaining = p }

        let current = generateCode(
            secret: secret,
            timestamp: timestamp,
            period: p,
            digits: digits,
            algorithm: algorithm
        )

        let nextDate = timestamp.addingTimeInterval(Double(remaining + 1))
        let next = generateCode(
            secret: secret,
            timestamp: nextDate,
            period: p,
            digits: digits,
            algorithm: algorithm
        )

        let progress = max(0.0, min(1.0, Double(remaining) / Double(p)))

        return TokenInfo(
            currentCode: current,
            currentFormatted: formatCode(current),
            nextCode: next,
            nextFormatted: formatCode(next),
            timeRemaining: remaining,
            period: p,
            progress: progress
        )
    }
}
