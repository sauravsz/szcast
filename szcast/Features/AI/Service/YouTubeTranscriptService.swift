import AppKit
import Foundation

/// Service to detect YouTube video URLs from selection, clipboard or active browser tab,
/// extract timed text captions, and prepare formatted transcripts for AI summarization.
@MainActor
final class YouTubeTranscriptService {
    static let shared = YouTubeTranscriptService()

    private init() {}

    struct VideoInfo: Sendable {
        let videoID: String
        let title: String
        let transcript: String
    }

    /// Tries to resolve a YouTube video URL from:
    /// 1. Selected text
    /// 2. System clipboard
    /// 3. Frontmost browser tab (Safari, Chrome, Brave, Arc, Edge)
    func resolveYouTubeURL(selection: String?) -> String? {
        // 1. Check selection
        if let selection = selection?.trimmingCharacters(in: .whitespacesAndNewlines),
           let id = extractVideoID(from: selection) {
            return "https://www.youtube.com/watch?v=\(id)"
        }

        // 2. Check clipboard
        if let clip = NSPasteboard.general.string(forType: .string)?.trimmingCharacters(in: .whitespacesAndNewlines),
           let id = extractVideoID(from: clip) {
            return "https://www.youtube.com/watch?v=\(id)"
        }

        // 3. Check frontmost browser
        if let browserURL = frontmostBrowserURL(),
           let id = extractVideoID(from: browserURL) {
            return "https://www.youtube.com/watch?v=\(id)"
        }

        return nil
    }

    /// Extracts 11-character YouTube video ID from arbitrary text / URL.
    func extractVideoID(from text: String) -> String? {
        let pattern = #"(?:youtube\.com\/(?:[^\/]+\/.+\/|(?:v|e(?:mbed)?|shorts|live)\/|.*[?&]v=)|youtu\.be\/)([^"&?\/\s]{11})"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else { return nil }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = regex.firstMatch(in: text, options: [], range: range),
              let idRange = Range(match.range(at: 1), in: text) else { return nil }
        return String(text[idRange])
    }

    /// Fetches YouTube page HTML, extracts title and caption track, and parses timed text XML.
    func fetchTranscript(videoID: String) async throws -> VideoInfo {
        let pageURL = URL(string: "https://www.youtube.com/watch?v=\(videoID)")!
        var request = URLRequest(url: pageURL)
        request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Safari/605.1.15", forHTTPHeaderField: "User-Agent")
        request.setValue("en-US,en;q=0.9", forHTTPHeaderField: "Accept-Language")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode),
              let html = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .ascii) else {
            throw YouTubeError.networkFailed
        }

        // Extract title
        let title = extractTitle(from: html) ?? "YouTube Video (\(videoID))"

        // Extract caption track URL
        guard let captionTrackURL = extractCaptionTrackURL(from: html) else {
            throw YouTubeError.noCaptionsAvailable
        }

        // Fetch captions XML
        var capReq = URLRequest(url: captionTrackURL)
        capReq.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7)", forHTTPHeaderField: "User-Agent")
        let (capData, capResp) = try await URLSession.shared.data(for: capReq)
        guard let capHttp = capResp as? HTTPURLResponse, (200...299).contains(capHttp.statusCode),
              let capXML = String(data: capData, encoding: .utf8) else {
            throw YouTubeError.captionsUnreadable
        }

        let parsedTranscript = parseCaptionsXML(capXML)
        guard !parsedTranscript.isEmpty else {
            throw YouTubeError.noCaptionsAvailable
        }

        return VideoInfo(videoID: videoID, title: title, transcript: parsedTranscript)
    }

    // MARK: - Browser URL Detection

    private func frontmostBrowserURL() -> String? {
        guard let frontApp = NSWorkspace.shared.frontmostApplication else { return nil }
        let name = frontApp.localizedName ?? ""

        var scriptSource: String?
        if name == "Safari" {
            scriptSource = "tell application \"Safari\" to if (count of documents) > 0 then return URL of front document"
        } else if name == "Google Chrome" {
            scriptSource = "tell application \"Google Chrome\" to if (count of windows) > 0 then return URL of active tab of front window"
        } else if name == "Brave Browser" {
            scriptSource = "tell application \"Brave Browser\" to if (count of windows) > 0 then return URL of active tab of front window"
        } else if name == "Arc" {
            scriptSource = "tell application \"Arc\" to if (count of windows) > 0 then return URL of active tab of front window"
        } else if name == "Microsoft Edge" {
            scriptSource = "tell application \"Microsoft Edge\" to if (count of windows) > 0 then return URL of active tab of front window"
        }

        guard let script = scriptSource,
              let appleScript = NSAppleScript(source: script) else { return nil }

        var error: NSDictionary?
        let descriptor = appleScript.executeAndReturnError(&error)
        guard error == nil else { return nil }
        return descriptor.stringValue
    }

    // MARK: - Parsing Helpers

    private func extractTitle(from html: String) -> String? {
        let pattern = #"<title>(.*?)(?: - YouTube)?<\/title>"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
              let match = regex.firstMatch(in: html, range: NSRange(html.startIndex..<html.endIndex, in: html)),
              let range = Range(match.range(at: 1), in: html) else { return nil }
        var title = String(html[range])
        title = title.replacingOccurrences(of: " - YouTube", with: "")
        return decodeHTMLEntities(title).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func extractCaptionTrackURL(from html: String) -> URL? {
        // Look for captionTracks":[{...}]
        let pattern = #""captionTracks":\s*\[\s*\{(.*?)\}\s*\]"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .dotMatchesLineSeparators),
              let match = regex.firstMatch(in: html, range: NSRange(html.startIndex..<html.endIndex, in: html)),
              let range = Range(match.range(at: 1), in: html) else { return nil }

        let block = String(html[range])

        // Look for "baseUrl":"..."
        let urlPattern = #""baseUrl":\s*"([^"]+)""#
        guard let urlRegex = try? NSRegularExpression(pattern: urlPattern, options: []),
              let urlMatch = urlRegex.firstMatch(in: block, range: NSRange(block.startIndex..<block.endIndex, in: block)),
              let urlRange = Range(urlMatch.range(at: 1), in: block) else { return nil }

        var rawURL = String(block[urlRange])
        rawURL = rawURL.replacingOccurrences(of: "\\u0026", with: "&")
        return URL(string: rawURL)
    }

    private func parseCaptionsXML(_ xml: String) -> String {
        let pattern = #"<text start="(\d+(?:\.\d+)?)"[^>]*>(.*?)<\/text>"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .dotMatchesLineSeparators) else { return "" }

        var results: [String] = []
        var lastBucketSecond = -60

        let nsString = xml as NSString
        let matches = regex.matches(in: xml, options: [], range: NSRange(location: 0, length: nsString.length))

        for match in matches {
            guard match.numberOfRanges >= 3 else { continue }
            let startSecStr = nsString.substring(with: match.range(at: 1))
            let rawText = nsString.substring(with: match.range(at: 2))

            let startSeconds = Int(Double(startSecStr) ?? 0)
            let cleanText = decodeHTMLEntities(rawText)
                .replacingOccurrences(of: "\n", with: " ")
                .trimmingCharacters(in: .whitespacesAndNewlines)

            guard !cleanText.isEmpty else { continue }

            // Group into 30-second timestamped chunks
            if startSeconds - lastBucketSecond >= 30 {
                let minutes = startSeconds / 60
                let seconds = startSeconds % 60
                let timestamp = String(format: "[%02d:%02d]", minutes, seconds)
                results.append("\n\(timestamp) \(cleanText)")
                lastBucketSecond = startSeconds
            } else {
                if let last = results.last {
                    results[results.count - 1] = last + " " + cleanText
                } else {
                    results.append(cleanText)
                }
            }
        }

        return results.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func decodeHTMLEntities(_ text: String) -> String {
        var str = text
        let entities = [
            "&amp;": "&", "&quot;": "\"", "&#39;": "'", "&apos;": "'",
            "&lt;": "<", "&gt;": ">", "&nbsp;": " ",
        ]
        for (k, v) in entities {
            str = str.replacingOccurrences(of: k, with: v)
        }
        return str
    }

    enum YouTubeError: LocalizedError {
        case networkFailed
        case noCaptionsAvailable
        case captionsUnreadable

        var errorDescription: String? {
            switch self {
            case .networkFailed: return "Could not connect to YouTube."
            case .noCaptionsAvailable: return "This YouTube video has no captions or transcript available."
            case .captionsUnreadable: return "Unable to parse YouTube transcript format."
            }
        }
    }
}
