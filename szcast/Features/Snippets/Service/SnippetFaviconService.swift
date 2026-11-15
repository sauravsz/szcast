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
        let clean = hostOrIdentifier.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        if clean == "chatgpt" || clean == "openai" || clean.contains("chatgpt.com") || clean == "gpt" {
            return chatGPTIconPath
        }
        let safeName = hostOrIdentifier
            .lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .joined(separator: "-")
        let filename = safeName.isEmpty ? "snippet-icon" : safeName
        return iconsDirectory.appending(path: "\(filename).png").path
    }

    /// Standard path for ChatGPT snippet icon.
    static var chatGPTIconPath: String {
        iconsDirectory.appending(path: "chatgpt.png").path
    }

    /// Checks if a snippet is related to ChatGPT
    static func isChatGPT(snippet: Snippet) -> Bool {
        let custom = (snippet.icon ?? "").lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        if custom == "chatgpt" || custom == "openai" || custom.contains("chatgpt.com") || custom == "gpt" {
            return true
        }
        let name = snippet.name.lowercased()
        let keyword = (snippet.keyword ?? "").lowercased()
        let folder = (snippet.folder ?? "").lowercased()
        if name.contains("chatgpt") || name.hasPrefix("gpt") || name.contains("openai") {
            return true
        }
        if keyword.contains("chatgpt") || keyword == "gpt" {
            return true
        }
        if folder.contains("chatgpt") || folder == "gpt" {
            return true
        }
        return false
    }

    /// Ensures the high-contrast, dual-mode compatible ChatGPT icon exists and returns its EntryIcon.
    static func ensureChatGPTArtworkIcon() -> EntryIcon {
        let path = chatGPTIconPath
        if !FileManager.default.fileExists(atPath: path) {
            if let data = generateChatGPTIconPNG() {
                try? FileManager.default.createDirectory(at: iconsDirectory, withIntermediateDirectories: true)
                try? data.write(to: URL(fileURLWithPath: path), options: .atomic)
            }
        }
        if FileManager.default.fileExists(atPath: path) {
            return .artwork(path: path, extent: 24)
        }
        return .symbol("BrandChatGPT")
    }

    /// Generates a pixel-perfect, crisp ChatGPT squircle icon (256x256) with #10A37F emerald background and white rosette.
    static func generateChatGPTIconPNG() -> Data? {
        ChatGPTIconProvider.generatePNGData()
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
        // 1. If snippet explicitly provides a custom icon
        if let custom = snippet.icon?.trimmingCharacters(in: .whitespacesAndNewlines), !custom.isEmpty {
            let lower = custom.lowercased()
            if lower == "chatgpt" || lower == "openai" || lower.contains("chatgpt.com") || lower == "gpt" {
                return ensureChatGPTArtworkIcon()
            }

            // If it is a web domain or URL
            if let host = extractHost(from: custom) {
                if host.contains("chatgpt") || host.contains("openai") {
                    return ensureChatGPTArtworkIcon()
                }
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

        // 2. Default resolution: use proper high-contrast ChatGPT icon for all ChatGPT snippets
        if isChatGPT(snippet: snippet) {
            return ensureChatGPTArtworkIcon()
        }

        return .symbol("curlybraces")
    }

    /// Downloads and persists a favicon for the host, returning the local file path on success.
    @discardableResult
    static func fetchFavicon(forHost host: String) async -> String? {
        if host.contains("chatgpt") || host.contains("openai") {
            _ = ensureChatGPTArtworkIcon()
            return chatGPTIconPath
        }
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
