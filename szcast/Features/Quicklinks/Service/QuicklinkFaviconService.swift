import AppKit
import Foundation

/// Fetches, converts, and caches website favicons for quicklinks.
public enum QuicklinkFaviconService {
    /// Directory under Application Support where quicklink favicons are saved.
    public static var iconsDirectory: URL {
        AppPaths.applicationSupport().appending(path: "QuicklinkIcons", directoryHint: .isDirectory)
    }

    /// Standard local file path for a quicklink's favicon on disk.
    public static func iconPath(for id: UUID) -> String {
        iconsDirectory.appending(path: "\(id.uuidString.lowercased()).png").path
    }

    /// Extracts a valid website hostname from a quicklink destination, stripping dynamic arguments.
    public static func extractHost(from link: String) -> String? {
        var cleaned = link.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return nil }

        // Strip dynamic template placeholders like {argument} or {clipboard}
        if let regex = try? NSRegularExpression(pattern: "\\{[^}]*\\}") {
            cleaned = regex.stringByReplacingMatches(
                in: cleaned,
                range: NSRange(cleaned.startIndex..., in: cleaned),
                withTemplate: ""
            )
        }
        cleaned = cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return nil }

        guard case .web(let url)? = QuicklinkDestination.detect(cleaned) else {
            return nil
        }
        guard let host = url.host?.lowercased(), !host.isEmpty else {
            return nil
        }

        if let colon = host.firstIndex(of: ":") {
            return String(host[..<colon])
        }
        return host
    }

    /// Downloads and persists a favicon for the destination link, returning the local file path on success.
    @discardableResult
    public static func fetchFavicon(for link: String, quicklinkID: UUID) async -> String? {
        guard let host = extractHost(from: link) else { return nil }
        guard let pngData = await downloadFavicon(forHost: host) else { return nil }

        let directory = iconsDirectory
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let filePath = iconPath(for: quicklinkID)
            let fileURL = URL(fileURLWithPath: filePath)
            try pngData.write(to: fileURL, options: .atomic)
            return filePath
        } catch {
            return nil
        }
    }

    /// Removes any cached favicon file for a deleted quicklink.
    public static func removeIcon(for id: UUID) {
        let path = iconPath(for: id)
        guard FileManager.default.fileExists(atPath: path) else { return }
        try? FileManager.default.removeItem(atPath: path)
    }

    /// Duplicates an existing cached favicon when duplicating a quicklink.
    @discardableResult
    public static func copyIcon(from sourceID: UUID, to destinationID: UUID) -> String? {
        let sourcePath = iconPath(for: sourceID)
        guard FileManager.default.fileExists(atPath: sourcePath) else { return nil }
        let destPath = iconPath(for: destinationID)
        let destURL = URL(fileURLWithPath: destPath)
        let sourceURL = URL(fileURLWithPath: sourcePath)

        let directory = iconsDirectory
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try? FileManager.default.removeItem(at: destURL)
        do {
            try FileManager.default.copyItem(at: sourceURL, to: destURL)
            return destPath
        } catch {
            return nil
        }
    }

    // MARK: - Network Fetching

    private static func downloadFavicon(forHost host: String) async -> Data? {
        guard let encodedHost = host.addingPercentEncoding(withAllowedCharacters: .urlHostAllowed),
              !encodedHost.isEmpty else { return nil }

        let candidateURLs: [URL] = [
            URL(string: "https://www.google.com/s2/favicons?domain=\(encodedHost)&sz=128"),
            URL(string: "https://icons.duckduckgo.com/ip3/\(encodedHost).ico"),
            URL(string: "https://\(encodedHost)/favicon.ico")
        ].compactMap { $0 }

        for url in candidateURLs {
            if let data = await fetchImageData(from: url),
                let image = NSImage(data: data),
                image.isValid,
                image.size.width > 0,
                image.size.height > 0
            {
                if let png = pngRepresentation(from: image) {
                    return png
                }
            }
        }
        return nil
    }

    private static func fetchImageData(from url: URL) async -> Data? {
        var request = URLRequest(url: url)
        request.timeoutInterval = 6
        request.setValue(
            "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Safari/605.1.15",
            forHTTPHeaderField: "User-Agent"
        )

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200, !data.isEmpty else {
                return nil
            }
            return data
        } catch {
            return nil
        }
    }

    private static func pngRepresentation(from image: NSImage) -> Data? {
        guard let tiff = image.tiffRepresentation,
            let bitmap = NSBitmapImageRep(data: tiff)
        else {
            return nil
        }
        return bitmap.representation(using: .png, properties: [:])
    }
}
