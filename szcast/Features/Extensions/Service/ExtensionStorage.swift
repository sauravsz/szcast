import CryptoKit
import Foundation

/// One JSON file per extension: small, read whole at launch and written rarely.
@MainActor
final class ExtensionStorage {
    private struct Store: Codable {
        var localStorage: [String: StoredValue] = [:]
        var caches: [String: [String: String]] = [:]
        var preferences: [String: StoredValue] = [:]
        /// A search-bar dropdown's `storeValue` pick — host UI state, so not `LocalStorage`.
        var accessoryValues: [String: String] = [:]
        /// Each command's `storeValue` form fields, as the JSON the runtime wrote.
        var formValues: [String: [String: String]] = [:]
        /// Only ever populated by a store written before tokens moved to the Keychain. Decoded so
        /// the migration can read it, then cleared, so credentials never stay on disk in the clear.
        var oauthTokens: [String: String] = [:]
        /// Provider names whose tokens live in the Keychain. Names only — never the tokens.
        var oauthProviders: [String] = []

        enum CodingKeys: String, CodingKey {
            case localStorage, caches, preferences, accessoryValues, formValues, oauthTokens
            case oauthProviders
        }

        init() {}

        /// Each section decodes on its own: one absent key must not take an extension's whole
        /// store — API keys included — down with it, since a failed decode resets the file.
        init(from decoder: Decoder) throws {
            let store = try decoder.container(keyedBy: CodingKeys.self)
            localStorage =
                try store.decodeIfPresent([String: StoredValue].self, forKey: .localStorage) ?? [:]
            caches =
                try store.decodeIfPresent([String: [String: String]].self, forKey: .caches) ?? [:]
            preferences =
                try store.decodeIfPresent([String: StoredValue].self, forKey: .preferences) ?? [:]
            accessoryValues =
                try store.decodeIfPresent([String: String].self, forKey: .accessoryValues) ?? [:]
            formValues =
                try store.decodeIfPresent([String: [String: String]].self, forKey: .formValues) ?? [:]
            oauthTokens =
                try store.decodeIfPresent([String: String].self, forKey: .oauthTokens) ?? [:]
            oauthProviders =
                try store.decodeIfPresent([String].self, forKey: .oauthProviders) ?? []
        }
    }

    /// `LocalStorage` accepts strings, numbers and booleans and must return them with their type.
    enum StoredValue: Codable, Sendable, Equatable {
        case string(String)
        case number(Double)
        case bool(Bool)

        var jsonValue: Any {
            switch self {
            case .string(let value): return value
            case .number(let value): return value
            case .bool(let value): return value
            }
        }

        init?(renderValue: RenderValue) {
            switch renderValue {
            case .string(let value): self = .string(value)
            case .number(let value): self = .number(value)
            case .bool(let value): self = .bool(value)
            default: return nil
            }
        }

        init(preference: ExtensionPreferenceValue) {
            switch preference {
            case .string(let value): self = .string(value)
            case .number(let value): self = .number(value)
            case .bool(let value): self = .bool(value)
            case .application(let path): self = .string(path)
            }
        }

        var preferenceValue: ExtensionPreferenceValue {
            switch self {
            case .string(let value): return .string(value)
            case .number(let value): return .number(value)
            case .bool(let value): return .bool(value)
            }
        }
    }

    private let directory: URL
    private var stores: [String: Store] = [:]
    /// Writes are coalesced, so a busy `Cache` doesn't hit the disk per key.
    private var dirty: Set<String> = []
    private var flushTask: Task<Void, Never>?

    init(directory: URL) {
        self.directory = directory
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    // MARK: - LocalStorage

    func localStorageValue(extension name: String, key: String) -> StoredValue? {
        store(for: name).localStorage[key]
    }

    func allLocalStorage(extension name: String) -> [String: StoredValue] {
        store(for: name).localStorage
    }

    func setLocalStorage(extension name: String, key: String, value: StoredValue) {
        mutate(name) { $0.localStorage[key] = value }
    }

    func removeLocalStorage(extension name: String, key: String) {
        mutate(name) { $0.localStorage.removeValue(forKey: key) }
    }

    func clearLocalStorage(extension name: String) {
        mutate(name) { $0.localStorage.removeAll() }
    }

    // MARK: - Search-bar dropdowns

    func accessoryValue(extension name: String, key: String) -> String? {
        store(for: name).accessoryValues[key]
    }

    func setAccessoryValue(extension name: String, key: String, value: String) {
        mutate(name) { $0.accessoryValues[key] = value }
    }

    // MARK: - Form fields

    func formValues(extension name: String, command: String) -> [String: String] {
        store(for: name).formValues[command] ?? [:]
    }

    func setFormValues(extension name: String, command: String, values: [String: String]) {
        mutate(name) { $0.formValues[command, default: [:]].merge(values) { $1 } }
    }

    // MARK: - Cache

    func caches(extension name: String) -> [String: [String: String]] {
        store(for: name).caches
    }

    /// `nil` removes the key; a `nil` key clears the namespace.
    func setCache(extension name: String, namespace: String, key: String?, value: String?) {
        mutate(name) { store in
            guard let key else {
                store.caches[namespace] = [:]
                return
            }
            var bucket = store.caches[namespace] ?? [:]
            if let value { bucket[key] = value } else { bucket.removeValue(forKey: key) }
            store.caches[namespace] = bucket
        }
    }

    func clearCache(extension name: String, namespace: String) {
        mutate(name) { $0.caches[namespace] = [:] }
    }

    // MARK: - OAuth tokens

    /// Keychain-backed: a third-party refresh token is a credential, so it does not belong in the
    /// plaintext store the rest of this file keeps.
    func oauthTokens(extension name: String, provider: String) -> String? {
        migrateTokensIfNeeded(extension: name)
        return try? KeychainSecretStore.extensionOAuthTokens.secret(
            for: Self.tokenAccount(extension: name, provider: provider))
    }

    /// `nil` signs the provider out.
    func setOAuthTokens(extension name: String, provider: String, tokens: String?) {
        let account = Self.tokenAccount(extension: name, provider: provider)
        guard let tokens else {
            try? KeychainSecretStore.extensionOAuthTokens.removeSecret(for: account)
            mutate(name) { store in
                store.oauthProviders.removeAll { $0 == provider }
            }
            return
        }
        try? KeychainSecretStore.extensionOAuthTokens.setSecret(tokens, for: account)
        // The names only, never the values: uninstalling needs to know what to delete.
        mutate(name) { store in
            if !store.oauthProviders.contains(provider) { store.oauthProviders.append(provider) }
        }
    }

    /// A stable account for an extension/provider pair; the Keychain keys on a UUID.
    private static func tokenAccount(extension name: String, provider: String) -> UUID {
        // Deterministic across launches and channels, so the same pair always finds its token.
        let input = Data("\(ExtensionCatalog.safeName(name))\u{1F}\(provider)".utf8)
        var digest = Array(SHA256.hash(data: input))
        // Version 8 (custom) with the RFC 4122 variant, so it reads as a real UUID.
        digest[6] = (digest[6] & 0x0F) | 0x80
        digest[8] = (digest[8] & 0x3F) | 0x80
        return UUID(uuid: (
            digest[0], digest[1], digest[2], digest[3], digest[4], digest[5], digest[6], digest[7],
            digest[8], digest[9], digest[10], digest[11], digest[12], digest[13], digest[14],
            digest[15]
        ))
    }

    /// Moves any tokens a pre-Keychain store left on disk, then drops them from the file.
    private func migrateTokensIfNeeded(extension name: String) {
        var current = store(for: name)
        guard !current.oauthTokens.isEmpty else { return }
        for (provider, tokens) in current.oauthTokens {
            try? KeychainSecretStore.extensionOAuthTokens.setSecret(
                tokens, for: Self.tokenAccount(extension: name, provider: provider))
        }
        current.oauthTokens = [:]
        stores[name] = current
        dirty.insert(name)
        scheduleFlush()
    }

    // MARK: - Preferences

    func preference(extension name: String, key: String) -> ExtensionPreferenceValue? {
        store(for: name).preferences[key]?.preferenceValue
    }

    func setPreference(extension name: String, key: String, value: ExtensionPreferenceValue?) {
        mutate(name) { store in
            if let value {
                store.preferences[key] = StoredValue(preference: value)
            } else {
                store.preferences.removeValue(forKey: key)
            }
        }
    }

    /// Manifest defaults overlaid with the user's — what `getPreferenceValues()` sees.
    func resolvedPreferences(
        extension name: String, schemas: [ExtensionPreferenceSchema]
    ) -> [String: ExtensionPreferenceValue] {
        var resolved: [String: ExtensionPreferenceValue] = [:]
        for schema in schemas {
            resolved[schema.name] = schema.runtimeValue(preference(extension: name, key: schema.name))
        }
        return resolved
    }

    /// A command with an unset required preference must not run.
    func missingRequiredPreferences(
        extension name: String, schemas: [ExtensionPreferenceSchema]
    ) -> [ExtensionPreferenceSchema] {
        schemas.filter { schema in
            guard schema.required else { return false }
            let value = preference(extension: name, key: schema.name) ?? schema.effectiveDefault
            if case .string(let text) = value { return text.isEmpty }
            return false
        }
    }

    func removeAll(extension name: String) {
        // Tokens live in the Keychain now, so dropping the file is no longer enough.
        for provider in store(for: name).oauthProviders {
            try? KeychainSecretStore.extensionOAuthTokens.removeSecret(
                for: Self.tokenAccount(extension: name, provider: provider))
        }
        stores.removeValue(forKey: name)
        try? FileManager.default.removeItem(at: fileURL(for: name))
    }

    // MARK: - Persistence

    private func store(for name: String) -> Store {
        if let existing = stores[name] { return existing }
        let loaded =
            (try? Data(contentsOf: fileURL(for: name)))
            .flatMap { try? JSONDecoder().decode(Store.self, from: $0) } ?? Store()
        stores[name] = loaded
        return loaded
    }

    private func mutate(_ name: String, _ body: (inout Store) -> Void) {
        var current = store(for: name)
        body(&current)
        stores[name] = current
        dirty.insert(name)
        scheduleFlush()
    }

    private func scheduleFlush() {
        guard flushTask == nil else { return }
        flushTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(250))
            self?.flush()
        }
    }

    func flush() {
        flushTask?.cancel()
        flushTask = nil
        let pending = dirty
        dirty.removeAll()
        for name in pending {
            guard let store = stores[name], let data = try? JSONEncoder().encode(store) else { continue }
            try? data.write(to: fileURL(for: name), options: .atomic)
        }
    }

    private func fileURL(for name: String) -> URL {
        directory.appendingPathComponent("\(ExtensionCatalog.safeName(name)).json")
    }
}
