import AppKit
import Foundation
import OSLog

@MainActor
final class DuckDuckGoEmailService: Observable {
    private static let logger = Logger(subsystem: "com.sauravsz.szcast", category: "DuckDuckGoEmail")
    private static let accountKey = "token"

    private let keychain: KeychainSecretStore

    init(keychain: KeychainSecretStore = .duckDuckGoToken) {
        self.keychain = keychain
    }

    var token: String? {
        get {
            try? keychain.secret(for: Self.accountKey)
        }
        set {
            if let newValue = newValue?.trimmingCharacters(in: .whitespacesAndNewlines), !newValue.isEmpty {
                try? keychain.setSecret(newValue, for: Self.accountKey)
            } else {
                try? keychain.removeSecret(for: Self.accountKey)
            }
        }
    }

    var hasToken: Bool {
        (try? keychain.hasSecret(for: Self.accountKey)) ?? false
    }

    enum ServiceError: LocalizedError {
        case missingToken
        case invalidResponse
        case httpError(Int, String)
        case decodingError

        var errorDescription: String? {
            switch self {
            case .missingToken:
                return String(localized: "DuckDuckGo Email token is not configured. Please enter your Bearer token.")
            case .invalidResponse:
                return String(localized: "Invalid response from DuckDuckGo Email API.")
            case .httpError(let code, let msg):
                return String(localized: "DuckDuckGo API error (\(code)): \(msg)")
            case .decodingError:
                return String(localized: "Failed to parse DuckDuckGo address response.")
            }
        }
    }

    struct GenerateResponse: Decodable {
        let address: String
    }

    /// Calls DuckDuckGo Email API to create a new private alias.
    func generateAlias(customToken: String? = nil) async throws -> String {
        guard let activeToken = customToken ?? token, !activeToken.isEmpty else {
            throw ServiceError.missingToken
        }

        guard let url = URL(string: "https://quack.duckduckgo.com/api/email/addresses") else {
            throw ServiceError.invalidResponse
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(activeToken)", forHTTPHeaderField: "Authorization")
        request.setValue(
            "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36",
            forHTTPHeaderField: "User-Agent"
        )
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw ServiceError.invalidResponse
        }

        guard httpResponse.statusCode == 200 else {
            let errorBody = String(data: data, encoding: .utf8) ?? "Unknown HTTP error"
            throw ServiceError.httpError(httpResponse.statusCode, errorBody)
        }

        guard let decoded = try? JSONDecoder().decode(GenerateResponse.self, from: data) else {
            throw ServiceError.decodingError
        }

        let fullEmail = "\(decoded.address)@duck.com"
        Self.logger.info("Successfully generated new DuckDuckGo alias")
        return fullEmail
    }

    /// Generates a new alias, copies it to clipboard, and returns confirmation.
    @discardableResult
    func generateAndCopy() async -> (success: Bool, email: String?, message: String) {
        do {
            let email = try await generateAlias()
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(email, forType: .string)
            return (true, email, String(localized: "Copied \(email) to clipboard"))
        } catch {
            return (false, nil, error.localizedDescription)
        }
    }
}
