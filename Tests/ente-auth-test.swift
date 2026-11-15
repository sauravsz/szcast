import Foundation
import CommonCrypto

@main
@MainActor
struct EnteAuthTests {
    static var failures = 0
    static var passes = 0

    static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        if condition() {
            passes += 1
        } else {
            failures += 1
            print("FAIL: \(message)")
        }
    }

    static func main() {
        testBase32Decoding()
        testRFC6238TestVectors()
        testOTPAuthURIParsing()
        testTokenFormatting()
        testAccountUsageRanking()

        print("EnteAuthTests: \(passes) passed, \(failures) failed")
        exit(failures == 0 ? 0 : 1)
    }

    static func testBase32Decoding() {
        // "Hello" in Base32 is "JBSWY3DP"
        let data = TOTPEngine.decodeBase32("JBSWY3DP")
        expect(data != nil, "Base32 decodes valid string")
        if let data {
            let str = String(data: data, encoding: .utf8)
            expect(str == "Hello", "Base32 decodes 'Hello' correctly")
        }

        // Test with whitespace and lowercase
        let data2 = TOTPEngine.decodeBase32("jbsw y3dp")
        expect(data2 == data, "Base32 handles lowercase and whitespace")

        // Test with padding
        let data3 = TOTPEngine.decodeBase32("JBSWY3DP======")
        expect(data3 == data, "Base32 handles '=' padding")

        // Invalid characters
        let invalid = TOTPEngine.decodeBase32("JBSWY89!")
        expect(invalid == nil, "Base32 rejects invalid characters")
    }

    static func testRFC6238TestVectors() {
        // RFC 6238 test secret: "12345678901234567890" (20 bytes)
        // Base32 representation: "GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQ"
        let secret = "GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQ"

        // Unix timestamps from RFC 6238 Table 1 (SHA1, 8 digits in RFC, but let's test 8 digits)
        let t1 = Date(timeIntervalSince1970: 59)
        let code1 = TOTPEngine.generateCode(secret: secret, timestamp: t1, period: 30, digits: 8, algorithm: .sha1)
        expect(code1 == "94287082", "RFC 6238 vector T=59s 8-digit SHA1 expected 94287082, got \(code1)")

        let t2 = Date(timeIntervalSince1970: 1111111109)
        let code2 = TOTPEngine.generateCode(secret: secret, timestamp: t2, period: 30, digits: 8, algorithm: .sha1)
        expect(code2 == "07081804", "RFC 6238 vector T=1111111109s 8-digit SHA1 expected 07081804, got \(code2)")

        let t3 = Date(timeIntervalSince1970: 1111111111)
        let code3 = TOTPEngine.generateCode(secret: secret, timestamp: t3, period: 30, digits: 8, algorithm: .sha1)
        expect(code3 == "14050471", "RFC 6238 vector T=1111111111s 8-digit SHA1 expected 14050471, got \(code3)")

        let t4 = Date(timeIntervalSince1970: 1234567890)
        let code4 = TOTPEngine.generateCode(secret: secret, timestamp: t4, period: 30, digits: 8, algorithm: .sha1)
        expect(code4 == "89005924", "RFC 6238 vector T=1234567890s 8-digit SHA1 expected 89005924, got \(code4)")

        let t5 = Date(timeIntervalSince1970: 2000000000)
        let code5 = TOTPEngine.generateCode(secret: secret, timestamp: t5, period: 30, digits: 8, algorithm: .sha1)
        expect(code5 == "69279037", "RFC 6238 vector T=2000000000s 8-digit SHA1 expected 69279037, got \(code5)")

        // Test 6-digit SHA1 at T=59s (last 6 digits: 287082)
        let code6dig = TOTPEngine.generateCode(secret: secret, timestamp: t1, period: 30, digits: 6, algorithm: .sha1)
        expect(code6dig == "287082", "RFC 6238 6-digit SHA1 expected 287082, got \(code6dig)")
    }

    static func testOTPAuthURIParsing() {
        // Standard URI
        let uri1 = "otpauth://totp/GitHub:alice@github.com?secret=JBSWY3DPEHPK3PXP&issuer=GitHub&algorithm=SHA1&digits=6&period=30"
        let acc1 = EnteAuthStore.parseOTPAuthURI(uri1)
        expect(acc1 != nil, "Parses standard otpauth URI")
        if let acc1 {
            expect(acc1.issuer == "GitHub", "Service parsed as GitHub")
            expect(acc1.username == "alice@github.com", "Account parsed as alice@github.com")
            expect(acc1.secret == "JBSWY3DPEHPK3PXP", "Secret matches")
            expect(acc1.algorithm == .sha1, "Algorithm is SHA1")
            expect(acc1.digits == 6, "Digits is 6")
            expect(acc1.period == 30, "Period is 30")
        }

        // URI with encoded characters and SHA256
        let uri2 = "otpauth://totp/AWS%20Cloud:admin?secret=GEZDGNBVGY3TQOJQ&algorithm=SHA256&digits=8&period=60"
        let acc2 = EnteAuthStore.parseOTPAuthURI(uri2)
        expect(acc2 != nil, "Parses URI with percent encoding")
        if let acc2 {
            expect(acc2.issuer == "AWS Cloud", "Service unescapes AWS Cloud")
            expect(acc2.username == "admin", "Account is admin")
            expect(acc2.algorithm == .sha256, "Algorithm is SHA256")
            expect(acc2.digits == 8, "Digits is 8")
            expect(acc2.period == 60, "Period is 60")
        }

        // Non-totp scheme rejected
        let invalid = "otpauth://hotp/alice?secret=JBSWY3DP&counter=1"
        let accInvalid = EnteAuthStore.parseOTPAuthURI(invalid)
        expect(accInvalid == nil, "Rejects non-TOTP URI")
    }

    static func testTokenFormatting() {
        let fmt6 = TOTPEngine.formatCode("123456")
        expect(fmt6 == "123 456", "Formats 6 digits as '123 456'")

        let fmt8 = TOTPEngine.formatCode("12345678")
        expect(fmt8 == "1234 5678", "Formats 8 digits as '1234 5678'")

        let raw = TOTPEngine.formatCode("123")
        expect(raw == "123", "Keeps short tokens as-is")
    }

    static func testAccountUsageRanking() {
        let acc1 = EnteAuthAccount(issuer: "Alpha", username: "a@a.com", secret: "JBSWY3DP", algorithm: .sha1, digits: 6, period: 30)
        var acc2 = EnteAuthAccount(issuer: "Beta", username: "b@b.com", secret: "JBSWY3DP", algorithm: .sha1, digits: 6, period: 30)

        // Give acc2 more usage count and recent timestamp
        acc2.useCount = 10
        acc2.lastUsedAt = Date()

        let list = [acc1, acc2].sorted { lhs, rhs in
            if lhs.useCount != rhs.useCount {
                return lhs.useCount > rhs.useCount
            }
            return lhs.issuer.localizedCaseInsensitiveCompare(rhs.issuer) == .orderedAscending
        }

        expect(list.first?.issuer == "Beta", "Higher usage rank appears first")
    }
}
