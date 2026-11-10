import Foundation

@main
struct ExtensionInstallPolicyTest {
    static func main() {
        var failures = 0
        func check(_ what: String, _ ok: @autoclosure () -> Bool) {
            print((ok() ? "PASS  " : "FAIL  ") + what)
            if !ok() { failures += 1 }
        }

        let suite = "ext-install-policy-test"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)

        // Absence must mean locked down, not open.
        check("unset means store-only", ExtensionInstallPolicy.isStoreOnly(defaults: defaults))
        check("unset refuses unreviewed sources",
              !ExtensionInstallPolicy.allowsUnreviewedSources(defaults: defaults))

        defaults.set(false, forKey: ExtensionInstallPolicy.storeOnlyKey)
        check("turning it off allows unreviewed sources",
              ExtensionInstallPolicy.allowsUnreviewedSources(defaults: defaults))
        check("and it is no longer store-only", !ExtensionInstallPolicy.isStoreOnly(defaults: defaults))

        defaults.set(true, forKey: ExtensionInstallPolicy.storeOnlyKey)
        check("turning it back on refuses them again",
              !ExtensionInstallPolicy.allowsUnreviewedSources(defaults: defaults))

        // The download URL arrives in a remote response, so the host decides.
        check("the raycast store host is trusted",
              ExtensionInstallPolicy.isTrustedDownloadURL(URL(string: "https://www.raycast.com/x.zip")!))
        check("the bare raycast host is trusted",
              ExtensionInstallPolicy.isTrustedDownloadURL(URL(string: "https://raycast.com/x.zip")!))
        check("an unrelated host is refused",
              !ExtensionInstallPolicy.isTrustedDownloadURL(URL(string: "https://evil.example/x.zip")!))
        check("a look-alike host is refused",
              !ExtensionInstallPolicy.isTrustedDownloadURL(URL(string: "https://raycast.com.evil.example/x.zip")!))
        check("plain http is refused",
              !ExtensionInstallPolicy.isTrustedDownloadURL(URL(string: "http://www.raycast.com/x.zip")!))
        check("a file URL is refused",
              !ExtensionInstallPolicy.isTrustedDownloadURL(URL(fileURLWithPath: "/tmp/x.zip")))

        defaults.removePersistentDomain(forName: suite)
        print(failures == 0 ? "PASSED" : "FAILED")
        exit(failures == 0 ? 0 : 1)
    }
}
