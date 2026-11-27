import AppKit
import Carbon.HIToolbox

enum Paster {
    /// Stamped on szcast's own synthetic keystrokes so the snippet keyword tap can skip them.
    static let szcastEventTag: Int64 = 0x54494E59

    /// Covers the gap between `activate()` returning and the target app accepting a keystroke.
    private static let activationDelay: TimeInterval = 0.08

    /// Shorter: no activation to wait on, only the pasteboard write reaching the target's process.
    private static let directPostDelay: TimeInterval = 0.05

    /// Write the item and paste it into `previousApp`, activating it so ⌘V lands there.
    @MainActor @discardableResult
    static func paste(
        _ item: ClipboardItem, store: ClipboardStore, previousApp: NSRunningApplication?
    ) -> Bool {
        guard write(item, store: store) else { return false }
        store.promote(item)
        previousApp?.activate()
        DispatchQueue.main.asyncAfter(deadline: .now() + activationDelay) {
            postCommandV()
        }
        return true
    }

    /// Paste only the item's text, so a file arrives as its path and the receiver's style applies.
    @MainActor @discardableResult
    static func pastePlainText(
        _ item: ClipboardItem, store: ClipboardStore, previousApp: NSRunningApplication?
    ) -> Bool {
        guard let text = item.plainText else { return false }
        pasteString(text, previousApp: previousApp)
        store.promote(item)
        return true
    }

    /// Put the item on the pasteboard without pasting; the marker stops re-capture.
    @MainActor @discardableResult
    static func copy(_ item: ClipboardItem, store: ClipboardStore) -> Bool {
        guard write(item, store: store) else { return false }
        store.promote(item)
        return true
    }

    /// Put a string on the pasteboard unmarked, so it enters history like any other copy.
    /// Converts explicit Markdown spans to RTF unless `plainTextOnly` is requested (e.g. code/markdown editors).
    @MainActor @discardableResult
    static func copyPlainText(_ text: String, plainTextOnly: Bool = false) -> Bool {
        let pb = NSPasteboard.general
        pb.clearContents()
        var types: [NSPasteboard.PasteboardType] = [.string]
        let rtf = plainTextOnly ? nil : richTextData(for: text)
        if rtf != nil { types.append(.rtf) }
        pb.declareTypes(types, owner: nil)
        let success = pb.setString(text, forType: .string)
        if let rtf { pb.setData(rtf, forType: .rtf) }
        return success
    }

    private static let markdownLinkRegex = try? NSRegularExpression(pattern: #"\[[^\[\]\n]+\]\(https?://[^\s\)]+\)"#)
    private static let markdownBoldRegex = try? NSRegularExpression(pattern: #"\*\*\S(?:.*?\S)?\*\*"#)
    private static let markdownHeadingRegex = try? NSRegularExpression(pattern: #"(?m)^#{1,3}\s+[A-Za-z][^\n]*"#)

    /// True only when text contains balanced rich-text Markdown rather than literal code brackets/hashes (`[TODO]`, `#123`, `[[Wiki]]`, `2 * 3`).
    static func shouldConvertMarkdownToRTF(_ text: String) -> Bool {
        guard !text.isEmpty, !text.contains("```") else { return false }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        if let markdownBoldRegex, markdownBoldRegex.firstMatch(in: text, options: [], range: range) != nil {
            return true
        }
        if let markdownLinkRegex, markdownLinkRegex.firstMatch(in: text, options: [], range: range) != nil {
            return true
        }
        if let markdownHeadingRegex, markdownHeadingRegex.firstMatch(in: text, options: [], range: range) != nil {
            return true
        }
        return false
    }

    /// Converts explicit rich Markdown syntax to RTF data without mangling literal code/notes brackets or hashes.
    static func richTextData(for text: String) -> Data? {
        guard shouldConvertMarkdownToRTF(text) else {
            return nil
        }
        guard let attributed = try? NSAttributedString(
            markdown: text,
            options: AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        ) else { return nil }
        let range = NSRange(location: 0, length: attributed.length)
        guard range.length > 0 else { return nil }
        return try? attributed.data(
            from: range,
            documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf]
        )
    }

    /// Put a secret string on the pasteboard tagged with standard macOS concealed and transient markers.
    /// Clipboard managers (including szcast's own ClipboardManager) ignore concealed copies.
    @MainActor @discardableResult
    static func copyConcealedText(_ text: String) -> Bool {
        let pb = NSPasteboard.general
        pb.clearContents()
        let concealed = NSPasteboard.PasteboardType("org.nspasteboard.ConcealedType")
        let transient = NSPasteboard.PasteboardType("org.nspasteboard.TransientType")
        let autoGenerated = NSPasteboard.PasteboardType("org.nspasteboard.AutoGeneratedType")
        let peterMaurer = NSPasteboard.PasteboardType("de.petermaurer.TransientPasteboardType")
        let appleSensitive = NSPasteboard.PasteboardType("com.apple.is-sensitive")
        pb.declareTypes([.string, concealed, transient, autoGenerated, peterMaurer, appleSensitive, ClipboardManager.internalType], owner: nil)
        let success = pb.setString(text, forType: .string)
        pb.setData(Data(), forType: concealed)
        pb.setData(Data(), forType: transient)
        pb.setData(Data(), forType: autoGenerated)
        pb.setData(Data(), forType: peterMaurer)
        pb.setData(Data(), forType: appleSensitive)
        pb.setData(Data(), forType: ClipboardManager.internalType)
        return success
    }

    /// Calibrates clipboard restore delay by target app class so Electron/Chromium/Terminal renderers finish reading ⌘V.
    static func pasteboardRestoreDelay(for bundleID: String?) -> TimeInterval {
        let lower = (bundleID ?? "").lowercased()
        let slowConsumerMarkers = [
            "vscode", "obsidian", "todesktop", "slack", "discord", "teams",
            "chrome", "safari", "arc", "zen", "firefox", "brave", "edgemac",
            "notion", "linear", "iterm", "terminal", "ghostty", "warp", "alacritty",
            "electron", "cef", "webview", "thebrowser"
        ]
        if slowConsumerMarkers.contains(where: { lower.contains($0) }) {
            return 0.36
        }
        return 0.16
    }

    /// String counterpart of `paste`, marker-stamped so transient pastes do not enter clipboard managers.
    /// Optionally restores the user's prior pasteboard after the target consumes ⌘V and posts Return.
    @MainActor
    static func pasteString(
        _ text: String,
        previousApp: NSRunningApplication?,
        concealed: Bool = false,
        restorePasteboard: Bool = false,
        pressReturnAfter: Bool = false,
        plainTextOnly: Bool = false,
        completion: (@MainActor () -> Void)? = nil
    ) {
        let snapshot = restorePasteboard ? snapshotPasteboard() : nil
        let app = previousApp ?? NSWorkspace.shared.frontmostApplication
        writeString(text, concealed: concealed, transient: restorePasteboard, plainTextOnly: plainTextOnly)
        let writtenChangeCount = NSPasteboard.general.changeCount
        app?.activate()
        let delay = app == nil || app?.bundleIdentifier == Bundle.main.bundleIdentifier ? directPostDelay : 0.12
        let restoreDelay = max(
            pasteboardRestoreDelay(for: app?.bundleIdentifier),
            pressReturnAfter ? 0.24 : 0.0
        )
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            postCommandV(toPid: app?.processIdentifier)
            if pressReturnAfter {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.04) {
                    postReturn(toPid: app?.processIdentifier)
                }
            }
            if let completion {
                DispatchQueue.main.asyncAfter(deadline: .now() + (pressReturnAfter ? 0.08 : 0.04)) {
                    completion()
                }
            }
            if let snapshot {
                DispatchQueue.main.asyncAfter(deadline: .now() + restoreDelay) {
                    restorePasteboardIfUnchanged(snapshot, expectedChangeCount: writtenChangeCount)
                }
            }
        }
    }

    @MainActor
    private static func snapshotPasteboard() -> [[NSPasteboard.PasteboardType: Data]] {
        let pb = NSPasteboard.general
        guard let items = pb.pasteboardItems, !items.isEmpty else { return [] }
        return items.map { item in
            var dict: [NSPasteboard.PasteboardType: Data] = [:]
            for type in item.types {
                if let data = item.data(forType: type) {
                    dict[type] = data
                }
            }
            return dict
        }
    }

    @MainActor
    private static func restorePasteboardIfUnchanged(
        _ snapshot: [[NSPasteboard.PasteboardType: Data]],
        expectedChangeCount: Int
    ) {
        let pb = NSPasteboard.general
        guard pb.changeCount == expectedChangeCount else { return }
        pb.clearContents()
        guard !snapshot.isEmpty else { return }
        let items: [NSPasteboardItem] = snapshot.map { entry in
            let item = NSPasteboardItem()
            for (type, data) in entry {
                item.setData(data, forType: type)
            }
            item.setData(Data(), forType: ClipboardManager.internalType)
            return item
        }
        pb.writeObjects(items)
    }

    @MainActor
    static func postReturn(toPid pid: pid_t? = nil) {
        guard Permissions.ensureAccessibility() else { return }
        let source = CGEventSource(stateID: .combinedSessionState)
        guard let down = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_Return), keyDown: true),
              let up = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_Return), keyDown: false)
        else { return }
        down.setIntegerValueField(.eventSourceUserData, value: szcastEventTag)
        up.setIntegerValueField(.eventSourceUserData, value: szcastEventTag)
        if let pid {
            down.postToPid(pid)
            Thread.sleep(forTimeInterval: 0.015)
            up.postToPid(pid)
        } else {
            down.post(tap: .cgAnnotatedSessionEventTap)
            Thread.sleep(forTimeInterval: 0.015)
            up.post(tap: .cgAnnotatedSessionEventTap)
        }
    }

    @MainActor
    static func pasteFile(_ url: URL, previousApp: NSRunningApplication?) {
        PasteboardFiles.write(url, to: .general)
        previousApp?.activate()
        DispatchQueue.main.asyncAfter(deadline: .now() + activationDelay) {
            postCommandV()
        }
    }

    @MainActor
    static func copyString(_ text: String) {
        writeString(text)
    }

    /// String counterpart of `pasteInPlace`; the palette stays frontmost.
    @MainActor
    static func pasteStringInPlace(_ text: String, into app: NSRunningApplication?) {
        writeString(text)
        guard let pid = app?.processIdentifier else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + directPostDelay) {
            postCommandV(toPid: pid)
        }
    }

    @MainActor
    private static func writeString(
        _ text: String,
        concealed: Bool = false,
        transient: Bool = false,
        plainTextOnly: Bool = false
    ) {
        let pb = NSPasteboard.general
        pb.clearContents()
        let transientType = NSPasteboard.PasteboardType("org.nspasteboard.TransientType")
        let autoGenerated = NSPasteboard.PasteboardType("org.nspasteboard.AutoGeneratedType")
        if concealed {
            let concealedType = NSPasteboard.PasteboardType("org.nspasteboard.ConcealedType")
            let peterMaurer = NSPasteboard.PasteboardType("de.petermaurer.TransientPasteboardType")
            let appleSensitive = NSPasteboard.PasteboardType("com.apple.is-sensitive")
            pb.declareTypes([.string, concealedType, transientType, autoGenerated, peterMaurer, appleSensitive, ClipboardManager.internalType], owner: nil)
            pb.setString(text, forType: .string)
            pb.setData(Data(), forType: concealedType)
            pb.setData(Data(), forType: transientType)
            pb.setData(Data(), forType: autoGenerated)
            pb.setData(Data(), forType: peterMaurer)
            pb.setData(Data(), forType: appleSensitive)
            pb.setData(Data(), forType: ClipboardManager.internalType)
        } else {
            let rtf = plainTextOnly ? nil : richTextData(for: text)
            var types: [NSPasteboard.PasteboardType] = [.string, ClipboardManager.internalType]
            if rtf != nil { types.append(.rtf) }
            if transient {
                types.append(transientType)
                types.append(autoGenerated)
            }
            pb.declareTypes(types, owner: nil)
            pb.setString(text, forType: .string)
            if let rtf { pb.setData(rtf, forType: .rtf) }
            pb.setData(Data(), forType: ClipboardManager.internalType)
            if transient {
                pb.setData(Data(), forType: transientType)
                pb.setData(Data(), forType: autoGenerated)
            }
        }
    }

    /// Paste into `app` without activating or promoting, so the palette and its rows hold still.
    @MainActor @discardableResult
    static func pasteInPlace(
        _ item: ClipboardItem, store: ClipboardStore, into app: NSRunningApplication?
    ) -> Bool {
        guard write(item, store: store) else { return false }
        if let pid = app?.processIdentifier {
            DispatchQueue.main.asyncAfter(deadline: .now() + directPostDelay) {
                postCommandV(toPid: pid)
            }
        }
        return true
    }

    /// Whether anything was written; a vanished item leaves the pasteboard untouched.
    @MainActor @discardableResult
    static func write(
        _ item: ClipboardItem, store: ClipboardStore, to pb: NSPasteboard = .general
    ) -> Bool {
        switch item.kind {
        case .text:
            guard let text = item.text else { return false }
            pb.clearContents()
            pb.declareTypes([.string, ClipboardManager.internalType], owner: nil)
            pb.setString(text, forType: .string)
        case .image:
            guard let url = store.imageURL(for: item),
                let data = try? Data(contentsOf: url, options: .mappedIfSafe)
            else {
                return false
            }
            pb.clearContents()
            pb.declareTypes([.png, .fileURL, ClipboardManager.internalType], owner: nil)
            pb.setData(data, forType: .png)
            // A text-only receiver ignores image data but pastes a file URL as its path.
            pb.setData(url.dataRepresentation, forType: .fileURL)
        case .file:
            guard let url = store.fileURL(for: item),
                FileManager.default.fileExists(atPath: url.path)
            else { return false }
            pb.clearContents()
            pb.declareTypes([.fileURL, .string, ClipboardManager.internalType], owner: nil)
            pb.setData(url.dataRepresentation, forType: .fileURL)
            // Both types: a file-taking app receives the file, a text field receives the path.
            pb.setString(url.path, forType: .string)
        }
        pb.setData(Data(), forType: ClipboardManager.internalType)
        return true
    }

    /// Resolves the physical virtual key code for a ⌘-shortcut character on the active input source (Dvorak, Colemak, AZERTY, etc.).
    @MainActor
    static func commandVirtualKeyCode(for targetCharacter: Character, fallback: CGKeyCode) -> CGKeyCode {
        guard let source = TISCopyCurrentASCIICapableKeyboardLayoutInputSource()?.takeRetainedValue(),
              let rawPtr = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData)
        else { return fallback }

        let layoutData = unsafeBitCast(rawPtr, to: CFData.self)
        let keyLayout = unsafeBitCast(CFDataGetBytePtr(layoutData), to: UnsafePointer<UCKeyboardLayout>.self)
        let wanted = String(targetCharacter).lowercased()

        return withExtendedLifetime(source) {
            for mod in [UInt32(cmdKey >> 8), UInt32(0)] {
                for keyCode in 0..<54 {
                    var deadKeyState: UInt32 = 0
                    var length = 0
                    var chars = [UniChar](repeating: 0, count: 4)
                    let status = UCKeyTranslate(
                        keyLayout,
                        UInt16(keyCode),
                        UInt16(kUCKeyActionDisplay),
                        mod,
                        UInt32(LMGetKbdType()),
                        OptionBits(kUCKeyTranslateNoDeadKeysBit),
                        &deadKeyState,
                        chars.count,
                        &length,
                        &chars
                    )
                    if status == noErr, length > 0 {
                        let translated = String(utf16CodeUnits: chars, count: length).lowercased()
                        if translated == wanted {
                            return CGKeyCode(keyCode)
                        }
                    }
                }
            }
            return fallback
        }
    }

    @MainActor
    static func postCommandV(toPid pid: pid_t? = nil) {
        postCommand(key: commandVirtualKeyCode(for: "v", fallback: CGKeyCode(kVK_ANSI_V)), toPid: pid)
    }

    /// Synthesize ⌘C, for reading a selection an app will not surface over Accessibility.
    @MainActor
    static func postCommandC(toPid pid: pid_t? = nil) {
        postCommand(key: commandVirtualKeyCode(for: "c", fallback: CGKeyCode(kVK_ANSI_C)), toPid: pid)
    }

    /// Synthesizes any layout-agnostic ⌘+<character> command shortcut (e.g. ⌘Z, ⌘A, ⌘T).
    @MainActor
    static func postCommandCharacter(_ character: Character, fallback: CGKeyCode, toPid pid: pid_t? = nil) {
        postCommand(key: commandVirtualKeyCode(for: character, fallback: fallback), toPid: pid)
    }

    @MainActor
    private static func postCommand(key: CGKeyCode, toPid pid: pid_t?) {
        guard Permissions.ensureAccessibility() else { return }
        let source = CGEventSource(stateID: .combinedSessionState)

        guard let down = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: true),
            let up = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: false)
        else { return }

        down.flags = .maskCommand
        up.flags = .maskCommand
        down.setIntegerValueField(.eventSourceUserData, value: szcastEventTag)
        up.setIntegerValueField(.eventSourceUserData, value: szcastEventTag)

        if let pid {
            down.postToPid(pid)
            Thread.sleep(forTimeInterval: 0.02)
            up.postToPid(pid)
        } else {
            down.post(tap: .cgAnnotatedSessionEventTap)
            Thread.sleep(forTimeInterval: 0.02)
            up.post(tap: .cgAnnotatedSessionEventTap)
        }
    }
}
