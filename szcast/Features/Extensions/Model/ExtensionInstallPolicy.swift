import Foundation

/// Where an extension came from, which decides whether szcast will install it at all.
///
/// The policy is **provenance**, not capability: a reviewed extension still runs with the same
/// reach as any other (see `docs/SECURITY-AUDIT.md`, H-1). What this buys is that hostile code has
/// to get past Raycast's review to arrive, instead of arriving as a pasted GitHub link.
enum ExtensionInstallPolicy {
    /// The store is the only source. Anything else is refused unless the user turns it on.
    static let storeOnlyKey = "extensionStoreOnlyInstalls"

    /// Defaults on, so absence means locked down rather than open.
    static func isStoreOnly(defaults: UserDefaults = .standard) -> Bool {
        defaults.object(forKey: storeOnlyKey) == nil || defaults.bool(forKey: storeOnlyKey)
    }

    /// Whether a source other than the store may be installed.
    static func allowsUnreviewedSources(defaults: UserDefaults = .standard) -> Bool {
        !isStoreOnly(defaults: defaults)
    }

    /// The hosts a store download may come from. The URL arrives in a remote response, so it is
    /// checked rather than trusted: otherwise "store only" would mean "whatever the API returns".
    static let trustedDownloadHosts: Set<String> = [
        "www.raycast.com",
        "raycast.com",
        "backend.raycast.com",
        "extensions.raycast-releases.com",
        "raycast-releases.com",
        "files.raycast.com",
        "assets.raycast.com"
    ]

    static func isTrustedDownloadURL(_ url: URL) -> Bool {
        guard url.scheme?.lowercased() == "https", let host = url.host?.lowercased() else {
            return false
        }
        if trustedDownloadHosts.contains(host) {
            return true
        }
        return host.hasSuffix(".raycast.com") || host.hasSuffix(".raycast-releases.com")
    }
}

/// Why an install was refused. Kept apart from `ExtensionCatalog.InstallError`, which is about the
/// contents of a folder rather than where it came from.
enum ExtensionInstallPolicyError: LocalizedError {
    case storeOnly
    case untrustedDownloadHost(String)

    var errorDescription: String? {
        switch self {
        case .storeOnly:
            return String(
                localized: """
                    szcast installs extensions from the Raycast store only. Turn that off in \
                    Settings › Extensions if you want to install one from a folder or a link.
                    """)
        case .untrustedDownloadHost(let host):
            return String(
                localized: """
                    The store pointed the download at \(host.isEmpty ? "an unnamed host" : host), \
                    which isn't Raycast. Nothing was installed.
                    """)
        }
    }
}
