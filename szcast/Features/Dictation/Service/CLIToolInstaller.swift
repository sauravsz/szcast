import Foundation

enum CLIToolInstaller {
    static let commandName = "szcast-cli"

    static var embeddedBinaryURL: URL? {
        let helpers = Bundle.main.bundleURL.appendingPathComponent("Contents/Helpers/\(commandName)")
        if FileManager.default.isExecutableFile(atPath: helpers.path) { return helpers }
        let adjacent = Bundle.main.bundleURL.deletingLastPathComponent().appendingPathComponent(commandName)
        if FileManager.default.isExecutableFile(atPath: adjacent.path) { return adjacent }
        return nil
    }

    static var candidateInstallDestinations: [URL] {
        [
            URL(fileURLWithPath: "/usr/local/bin/\(commandName)"),
            FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".local/bin/\(commandName)")
        ]
    }

    static var installedURL: URL? {
        candidateInstallDestinations.first { FileManager.default.isExecutableFile(atPath: $0.path) }
    }

    @discardableResult
    static func install() throws -> URL {
        guard let source = embeddedBinaryURL else {
            throw CocoaError(.fileNoSuchFile)
        }
        let fm = FileManager.default
        var lastError: Error?
        for dest in candidateInstallDestinations {
            do {
                try fm.createDirectory(at: dest.deletingLastPathComponent(), withIntermediateDirectories: true)
                if fm.fileExists(atPath: dest.path) {
                    try fm.removeItem(at: dest)
                }
                try fm.createSymbolicLink(at: dest, withDestinationURL: source)
                return dest
            } catch {
                lastError = error
            }
        }
        throw lastError ?? CocoaError(.fileWriteNoPermission)
    }

    static func uninstall() {
        for dest in candidateInstallDestinations {
            try? FileManager.default.removeItem(at: dest)
        }
    }
}
