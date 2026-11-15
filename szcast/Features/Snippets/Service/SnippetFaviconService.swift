import AppKit
import Foundation

/// Caches and resolves custom icons and favicons for snippets.
enum SnippetFaviconService {
    /// Directory under Application Support where snippet favicons are saved.
    static var iconsDirectory: URL {
        AppPaths.applicationSupport().appending(path: "SnippetIcons", directoryHint: .isDirectory)
    }

    /// Standard local file path for a snippet's favicon on disk.
    static func iconPath(for hostOrIdentifier: String) -> String {
        let safeName = hostOrIdentifier
            .lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .joined(separator: "-")
        let filename = safeName.isEmpty ? "snippet-icon" : safeName
        return iconsDirectory.appending(path: "\(filename).png").path
    }

    /// Checks if a string represents a domain, URL, or website reference.
    static func extractHost(from value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        // If it starts with http:// or https://, parse as full URL
        if trimmed.lowercased().hasPrefix("http://") || trimmed.lowercased().hasPrefix("https://") {
            if let url = URL(string: trimmed), let host = url.host?.lowercased(), !host.isEmpty {
                return host
            }
        }

        // If it contains a dot and doesn't contain whitespace or SF Symbol formatting
        if trimmed.contains(".") && !trimmed.contains(" ") && !trimmed.contains("/") && !trimmed.contains(":") {
            let components = trimmed.components(separatedBy: ".")
            if components.count >= 2, let tld = components.last, tld.count >= 2 {
                // If it looks like an SF symbol with dot syntax like "doc.text", check whether system symbol exists
                if NSImage(systemSymbolName: trimmed, accessibilityDescription: nil) != nil {
                    // It is a valid system symbol, prefer symbol
                    return nil
                }
                return trimmed.lowercased()
            }
        }

        return nil
    }

    /// Resolves the EntryIcon for a snippet.
    static func resolveIcon(for snippet: Snippet) -> EntryIcon {
        guard let custom = snippet.icon?.trimmingCharacters(in: .whitespacesAndNewlines), !custom.isEmpty else {
            return .symbol("curlybraces")
        }

        // If it is a web domain or URL
        if let host = extractHost(from: custom) {
            let path = iconPath(for: host)
            if FileManager.default.fileExists(atPath: path) {
                return .artwork(path: path, extent: 24)
            }
            // Trigger asynchronous download in background
            Task {
                _ = await fetchFavicon(forHost: host)
            }
            return .symbol("globe")
        }

        // Check if an existing cached file exists at the given path directly
        if FileManager.default.fileExists(atPath: custom) {
            return .artwork(path: custom, extent: 24)
        }

        // Default to symbol
        return .symbol(custom)
    }

    /// Downloads and persists a favicon for the host, returning the local file path on success.
    @discardableResult
    static func fetchFavicon(forHost host: String) async -> String? {
        guard let pngData = await downloadFavicon(forHost: host) else { return nil }
        let directory = iconsDirectory
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let filePath = iconPath(for: host)
            let fileURL = URL(fileURLWithPath: filePath)
            try pngData.write(to: fileURL, options: .atomic)
            return filePath
        } catch {
            return nil
        }
    }

    private static func downloadFavicon(forHost host: String) async -> Data? {
        guard let encodedHost = host.addingPercentEncoding(withAllowedCharacters: .urlHostAllowed),
              !encodedHost.isEmpty else { return nil }

        let candidateURLs: [URL] = [
            URL(string: "https://www.google.com/s2/favicons?domain=\(encodedHost)&sz=128"),
            URL(string: "https://icons.duckduckgo.com/ip3/\(encodedHost).ico"),
            URL(string: "https://\(encodedHost)/favicon.ico")
        ].compactMap { $0 }

        for url in candidateURLs {
            var request = URLRequest(url: url)
            request.timeoutInterval = 5
            request.setValue(
                "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36",
                forHTTPHeaderField: "User-Agent"
            )

            guard let (data, response) = try? await URLSession.shared.data(for: request),
                  let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200,
                  data.count > 100 else {
                continue
            }

            if let converted = convertToPNG(data) {
                return converted
            }
        }
        return nil
    }

    private static func convertToPNG(_ rawData: Data) -> Data? {
        guard let image = NSImage(data: rawData) else { return nil }
        let pixelSize: CGFloat = 64
        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: Int(pixelSize),
            pixelsHigh: Int(pixelSize),
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ) else { return nil }

        rep.size = NSSize(width: pixelSize, height: pixelSize)
        guard let context = NSGraphicsContext(bitmapImageRep: rep) else { return nil }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        context.imageInterpolation = .high
        image.draw(in: NSRect(x: 0, y: 0, width: pixelSize, height: pixelSize))
        NSGraphicsContext.restoreGraphicsState()

        return rep.representation(using: .png, properties: [:])
    }
}
