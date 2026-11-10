import Foundation
import Security

struct KeychainSecretStore: Sendable {
    enum StoreError: Error {
        case invalidEncoding
        case keychain(OSStatus)
    }

    private let service: String
    /// Set only for scopes that hold model credentials: macOS then requires the user's presence.
    private let requiresUserPresence: Bool

    /// Every scope the app stores under, named here so the whole keychain surface is one list.
    /// Model credentials ask for presence, so a background process cannot read them silently.
    static let aiAPIKeys = KeychainSecretStore(scope: "ai-api-keys", requiresUserPresence: true)
    static let aiRequestHeaders = KeychainSecretStore(scope: "ai-request-headers")
    static let mcpSecrets = KeychainSecretStore(scope: "mcp-secrets")
    static let installedAIEnvironment = KeychainSecretStore(scope: "installed-ai-environment")
    /// Third-party OAuth tokens, one JSON item per extension/provider pair.
    static let extensionOAuthTokens = KeychainSecretStore(scope: "extension-oauth-tokens")

    init(
        scope: String, requiresUserPresence: Bool = false,
        bundleIdentifier: String? = Bundle.main.bundleIdentifier
    ) {
        service = "\(bundleIdentifier ?? "com.sauravsz.szcast").\(scope)"
        self.requiresUserPresence = requiresUserPresence
    }

    func secret(for account: UUID) throws -> String? {
        var result: CFTypeRef?
        let status = SecItemCopyMatching(
            query(for: account, returningData: true) as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else { throw StoreError.keychain(status) }
        guard let data = result as? Data, let secret = String(data: data, encoding: .utf8) else {
            throw StoreError.invalidEncoding
        }
        return secret
    }

    /// Presence check without `kSecReturn*`, so no secret bytes are materialized.
    func hasSecret(for account: UUID) throws -> Bool {
        let status = SecItemCopyMatching(
            query(for: account, returningData: false) as CFDictionary, nil)
        if status == errSecItemNotFound { return false }
        guard status == errSecSuccess else { throw StoreError.keychain(status) }
        return true
    }

    func setSecret(_ secret: String, for account: UUID) throws {
        guard let data = secret.data(using: .utf8) else { throw StoreError.invalidEncoding }
        let lookup = query(for: account, returningData: false)
        let update = [kSecValueData as String: data]
        let status = SecItemUpdate(lookup as CFDictionary, update as CFDictionary)
        if status == errSecItemNotFound {
            var addition = lookup
            addition[kSecValueData as String] = data
            // Without this the item inherits the legacy default, readable whenever the file is
            // unlocked; after-first-unlock is the strongest class a background helper can use.
            if requiresUserPresence,
                let access = SecAccessControlCreateWithFlags(
                    nil, kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
                    .userPresence, nil)
            {
                addition[kSecAttrAccessControl as String] = access
            } else {
                addition[kSecAttrAccessible as String] =
                    kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            }
            let addStatus = SecItemAdd(addition as CFDictionary, nil)
            guard addStatus == errSecSuccess else { throw StoreError.keychain(addStatus) }
        } else if status != errSecSuccess {
            throw StoreError.keychain(status)
        }
    }

    func removeSecret(for account: UUID) throws {
        let status = SecItemDelete(query(for: account, returningData: false) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw StoreError.keychain(status)
        }
    }

    /// Deletes every item in this scope. An uninstalled extension leaves no credentials behind.
    func removeAllSecrets() throws {
        let status = SecItemDelete([kSecClass as String: kSecClassGenericPassword,
                                    kSecAttrService as String: service] as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw StoreError.keychain(status)
        }
    }

    /// One JSON item per account. A failed read throws, and so does a garbled item: reporting
    /// "no values" would turn corruption into silent credential loss.
    func values(for account: UUID) throws -> [String: String] {
        guard let stored = try secret(for: account) else { return [:] }
        guard let data = stored.data(using: .utf8),
            let decoded = try? JSONDecoder().decode([String: String].self, from: data)
        else { throw StoreError.invalidEncoding }
        return decoded
    }

    func setValues(_ values: [String: String], for account: UUID) throws {
        guard !values.isEmpty else { return try removeSecret(for: account) }
        guard let encoded = String(bytes: try JSONEncoder().encode(values), encoding: .utf8) else {
            throw StoreError.invalidEncoding
        }
        try setSecret(encoded, for: account)
    }

    private func query(for account: UUID, returningData: Bool) -> [String: Any] {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account.uuidString
        ]
        if returningData {
            query[kSecReturnData as String] = true
            query[kSecMatchLimit as String] = kSecMatchLimitOne
        }
        return query
    }
}
