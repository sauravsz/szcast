import Foundation
import AppKit

@main
@MainActor
struct DuckDuckGoEmailTests {
    static var passes = 0
    static var failures = 0

    static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        if condition() {
            passes += 1
        } else {
            failures += 1
            print("FAIL: \(message)")
        }
    }

    static func main() async {
        await testTokenManagement()
        testDecoding()

        print("DuckDuckGoEmailTests: \(passes) passed, \(failures) failed")
        exit(failures == 0 ? 0 : 1)
    }

    static func testTokenManagement() async {
        let keychain = KeychainSecretStore(scope: "test.ddg.\(UUID().uuidString)")
        let service = DuckDuckGoEmailService(keychain: keychain)

        expect(!service.hasToken, "Initial service has no token")
        expect(service.token == nil, "Initial token is nil")

        service.token = "test_bearer_token_12345"
        expect(service.hasToken, "Service detects token")
        expect(service.token == "test_bearer_token_12345", "Token matches saved value")

        service.token = nil
        expect(!service.hasToken, "Token cleared")
        expect(service.token == nil, "Token is nil after clear")

        do {
            _ = try await service.generateAlias()
            expect(false, "Should have thrown missingToken error")
        } catch DuckDuckGoEmailService.ServiceError.missingToken {
            expect(true, "Threw expected missingToken error")
        } catch {
            expect(false, "Unexpected error: \(error)")
        }
    }

    static func testDecoding() {
        let json = """
        {"address": "duckie987"}
        """.data(using: .utf8)!
        guard let decoded = try? JSONDecoder().decode(DuckDuckGoEmailService.GenerateResponse.self, from: json) else {
            expect(false, "Failed to decode JSON")
            return
        }
        expect(decoded.address == "duckie987", "Decoded address matches")
        expect("\(decoded.address)@duck.com" == "duckie987@duck.com", "Full email formatted correctly")
    }
}
