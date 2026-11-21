import AppKit
import CoreGraphics
import Foundation
import Vision

/// Native macOS system tools callable by models in Agentic Mode.
final class AgenticToolService: Sendable {
    static let shared = AgenticToolService()

    private init() {}

    /// The list of native system tools available for agentic turns.
    var tools: [AITool] {
        [
            AITool(
                name: "read_active_window",
                description: "Inspects the currently active macOS application and frontmost window, returning the application name, bundle identifier, window title, and visible/selected text if accessible.",
                parameters: JSONValue([
                    "type": "object",
                    "properties": [:] as [String: Any],
                ]),
                origin: "System",
                title: String(localized: "Active Window")
            ),
            AITool(
                name: "read_screen_ocr",
                description: "Captures a screenshot of the main display and runs Apple Vision neural OCR to recognize and extract all text currently displayed on screen.",
                parameters: JSONValue([
                    "type": "object",
                    "properties": [:] as [String: Any],
                ]),
                origin: "System",
                title: String(localized: "Screen OCR")
            ),
            AITool(
                name: "read_clipboard",
                description: "Reads the current text or URL stored in the macOS system clipboard.",
                parameters: JSONValue([
                    "type": "object",
                    "properties": [:] as [String: Any],
                ]),
                origin: "System",
                title: String(localized: "Clipboard")
            ),
            AITool(
                name: "fetch_webpage",
                description: "Fetches a webpage via HTTP/HTTPS and converts its HTML contents into clean readable markdown/text.",
                parameters: JSONValue([
                    "type": "object",
                    "properties": [
                        "url": [
                            "type": "string",
                            "description": "The full HTTP or HTTPS URL to fetch",
                        ]
                    ],
                    "required": ["url"],
                ]),
                origin: "System",
                title: String(localized: "Webpage Reader")
            ),
            AITool(
                name: "search_chat_history",
                description: "Searches past chat sessions and messages stored locally in szcast for matching keywords or topics.",
                parameters: JSONValue([
                    "type": "object",
                    "properties": [
                        "query": [
                            "type": "string",
                            "description": "The search terms to query in chat history",
                        ]
                    ],
                    "required": ["query"],
                ]),
                origin: "System",
                title: String(localized: "Chat History")
            ),
            AITool(
                name: "search_files",
                description: "Searches local files on macOS by file name using the system Spotlight index.",
                parameters: JSONValue([
                    "type": "object",
                    "properties": [
                        "query": [
                            "type": "string",
                            "description": "The file name or pattern to search for",
                        ]
                    ],
                    "required": ["query"],
                ]),
                origin: "System",
                title: String(localized: "Search Files")
            ),
        ]
    }

    /// Checks if a tool call targets one of our native system tools.
    func isAgenticTool(_ name: String) -> Bool {
        tools.contains { $0.name == name }
    }

    /// Executes the tool call safely and returns an `AIToolResult`.
    func invoke(_ call: AIToolCall, historyStore: ChatHistoryStore?) async -> AIToolResult {
        switch call.name {
        case "read_active_window":
            return await readActiveWindow(callID: call.id)
        case "read_screen_ocr":
            return await readScreenOCR(callID: call.id)
        case "read_clipboard":
            return await readClipboard(callID: call.id)
        case "fetch_webpage":
            return await fetchWebpage(call: call)
        case "search_chat_history":
            return await searchChatHistory(call: call, historyStore: historyStore)
        case "search_files":
            return await searchFiles(call: call)
        default:
            return .failure(call.id, String(localized: "Unknown tool \(call.name)"))
        }
    }

    // MARK: - Tool Implementations

    @MainActor
    private func readActiveWindow(callID: String) async -> AIToolResult {
        guard let frontApp = NSWorkspace.shared.frontmostApplication else {
            return .failure(callID, "No active application found.")
        }
        let appName = frontApp.localizedName ?? "Unknown App"
        let bundleID = frontApp.bundleIdentifier ?? "Unknown Bundle ID"
        let pid = frontApp.processIdentifier

        // Find active window title from CoreGraphics window list
        var windowTitle = "Unknown Window"
        if let windowList = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] {
            for info in windowList {
                if let ownerPID = info[kCGWindowOwnerPID as String] as? pid_t, ownerPID == pid {
                    if let title = info[kCGWindowName as String] as? String, !title.isEmpty {
                        windowTitle = title
                        break
                    }
                }
            }
        }

        // Attempt to read selected or focused text via Accessibility
        var visibleTextSnippet = ""
        let appElement = AXUIElementCreateApplication(pid)
        var focusedElementValue: AnyObject?
        if AXUIElementCopyAttributeValue(appElement, kAXFocusedUIElementAttribute as CFString, &focusedElementValue) == .success,
           let focusedElement = focusedElementValue {
            var selectedTextValue: AnyObject?
            let axElement = focusedElement as! AXUIElement
            if AXUIElementCopyAttributeValue(axElement, kAXSelectedTextAttribute as CFString, &selectedTextValue) == .success,
               let selStr = selectedTextValue as? String, !selStr.isEmpty {
                visibleTextSnippet = "\nSelected Text:\n\(selStr.prefix(2000))"
            } else {
                var textValue: AnyObject?
                if AXUIElementCopyAttributeValue(axElement, kAXValueAttribute as CFString, &textValue) == .success,
                   let fullStr = textValue as? String, !fullStr.isEmpty {
                    visibleTextSnippet = "\nFocused Element Text:\n\(fullStr.prefix(2000))"
                }
            }
        }

        let content = """
        Application: \(appName)
        Bundle ID: \(bundleID)
        Window Title: \(windowTitle)\(visibleTextSnippet)
        """
        return AIToolResult(callID: callID, content: content, isError: false)
    }

    private func readScreenOCR(callID: String) async -> AIToolResult {
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("szcast_ocr_\(UUID().uuidString).png")
        defer { try? FileManager.default.removeItem(at: tempURL) }

        let success = await Task.detached {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
            process.arguments = ["-x", tempURL.path]
            do {
                try process.run()
                process.waitUntilExit()
                return process.terminationStatus == 0
            } catch {
                return false
            }
        }.value

        guard success,
              let image = NSImage(contentsOf: tempURL),
              let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil)
        else {
            return .failure(callID, "Unable to capture screen display image.")
        }

        do {
            guard let result = try await ScreenCaptureService.processImage(cgImage, mode: .textOCR) else {
                return AIToolResult(callID: callID, content: "No readable text detected on screen.", isError: false)
            }
            return AIToolResult(callID: callID, content: result.rawText, isError: false)
        } catch {
            return .failure(callID, "OCR processing error: \(error.localizedDescription)")
        }
    }

    @MainActor
    private func readClipboard(callID: String) -> AIToolResult {
        if let string = NSPasteboard.general.string(forType: .string), !string.isEmpty {
            return AIToolResult(callID: callID, content: string, isError: false)
        }
        return AIToolResult(callID: callID, content: "Clipboard is empty or contains non-text content.", isError: false)
    }

    private func fetchWebpage(call: AIToolCall) async -> AIToolResult {
        guard let data = call.arguments.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let urlString = json["url"] as? String,
              let url = URL(string: urlString),
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https"
        else {
            return .failure(call.id, "Invalid URL argument.")
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Safari/605.1.15", forHTTPHeaderField: "User-Agent")

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
                return .failure(call.id, "HTTP request failed with status code \((response as? HTTPURLResponse)?.statusCode ?? 0)")
            }
            guard let html = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .ascii) else {
                return .failure(call.id, "Unable to decode webpage response as text.")
            }
            let stripped = Self.cleanHTML(html)
            let capped = String(stripped.prefix(16_384))
            return AIToolResult(callID: call.id, content: capped, isError: false)
        } catch {
            return .failure(call.id, "Failed to fetch webpage: \(error.localizedDescription)")
        }
    }

    @MainActor
    private func searchChatHistory(call: AIToolCall, historyStore: ChatHistoryStore?) -> AIToolResult {
        guard let historyStore else {
            return .failure(call.id, "Chat history store is unavailable.")
        }
        guard let data = call.arguments.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let query = json["query"] as? String, !query.isEmpty
        else {
            return .failure(call.id, "Missing search query argument.")
        }

        let matches = historyStore.search(query)
        if matches.isEmpty {
            return AIToolResult(callID: call.id, content: "No past chat conversations found matching '\(query)'.", isError: false)
        }

        let formatted = matches.prefix(5).map { conv in
            """
            - Title: \(conv.title)
              Date: \(conv.updatedAt.formatted(date: .abbreviated, time: .shortened))
              Preview: \(conv.preview)
            """
        }.joined(separator: "\n\n")

        return AIToolResult(callID: call.id, content: formatted, isError: false)
    }

    private func searchFiles(call: AIToolCall) async -> AIToolResult {
        guard let data = call.arguments.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let query = json["query"] as? String, !query.isEmpty
        else {
            return .failure(call.id, "Missing search query argument.")
        }

        return await Task.detached {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/mdfind")
            process.arguments = ["-name", query]

            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = Pipe()

            do {
                try process.run()
                process.waitUntilExit()

                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                guard let output = String(data: data, encoding: .utf8) else {
                    return AIToolResult(callID: call.id, content: "No files found.", isError: false)
                }

                let lines = output.components(separatedBy: .newlines)
                    .map { $0.trimmingCharacters(in: .whitespaces) }
                    .filter { !$0.isEmpty }

                if lines.isEmpty {
                    return AIToolResult(callID: call.id, content: "No files found matching '\(query)'.", isError: false)
                }

                let top = lines.prefix(15).joined(separator: "\n")
                return AIToolResult(callID: call.id, content: "Found files:\n\(top)", isError: false)
            } catch {
                return AIToolResult.failure(call.id, "File search failed: \(error.localizedDescription)")
            }
        }.value
    }

    // MARK: - HTML Cleaner

    private static func cleanHTML(_ html: String) -> String {
        var text = html
        // Remove script and style tags and contents
        text = text.replacingOccurrences(of: "(?is)<script.*?</script>", with: "", options: .regularExpression)
        text = text.replacingOccurrences(of: "(?is)<style.*?</style>", with: "", options: .regularExpression)
        text = text.replacingOccurrences(of: "(?is)<!--.*?-->", with: "", options: .regularExpression)

        // Convert common block elements to newlines
        text = text.replacingOccurrences(of: "(?i)<br\\s*/?>", with: "\n", options: .regularExpression)
        text = text.replacingOccurrences(of: "(?i)</?(p|div|tr|li|h[1-6])[^>]*>", with: "\n", options: .regularExpression)

        // Strip remaining HTML tags
        text = text.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)

        // Decode common HTML entities
        let entities = [
            "&nbsp;": " ", "&amp;": "&", "&lt;": "<", "&gt;": ">",
            "&quot;": "\"", "&#39;": "'", "&apos;": "'",
        ]
        for (entity, replacement) in entities {
            text = text.replacingOccurrences(of: entity, with: replacement)
        }

        // Collapse multiple blank lines
        text = text.replacingOccurrences(of: "\n{3,}", with: "\n\n", options: .regularExpression)
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
