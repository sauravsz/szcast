import AppKit
@preconcurrency import ApplicationServices
import Carbon.HIToolbox

@MainActor
enum DictationInsertionContext {
    static func read(in target: InjectionTarget?) -> DictationTextFormatter.Context? {
        if let editor = target?.ownEditor {
            return context(editor.string, range: editor.selectedRange())
        }
        guard let app = target?.externalApp else { return nil }
        guard let element = AccessibilityText.focusedElement(in: app) else { return nil }
        var value: CFTypeRef?
        var selected: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXValueAttribute as CFString, &value) == .success,
            let text = value as? String,
            AXUIElementCopyAttributeValue(
                element, kAXSelectedTextRangeAttribute as CFString, &selected) == .success,
            let selected, CFGetTypeID(selected) == AXValueGetTypeID()
        else { return nil }
        var range = CFRange()
        guard AXValueGetValue(unsafeDowncast(selected, to: AXValue.self), .cfRange, &range)
        else { return nil }
        return context(text, range: NSRange(location: range.location, length: range.length))
    }

    /// Reads currently selected text in the focused element or editor for Command Mode rewrite.
    static func readSelectedText(in target: InjectionTarget?) -> String? {
        if let editor = target?.ownEditor {
            let range = editor.selectedRange()
            guard range.length > 0, let str = Range(range, in: editor.string) else { return nil }
            let sel = String(editor.string[str]).trimmingCharacters(in: .whitespacesAndNewlines)
            return sel.isEmpty ? nil : sel
        }
        guard let app = target?.externalApp else { return nil }
        guard let element = AccessibilityText.focusedElement(in: app) else { return nil }

        // 1. Direct selected text attribute
        var selectedVal: CFTypeRef?
        if AXUIElementCopyAttributeValue(element, kAXSelectedTextAttribute as CFString, &selectedVal) == .success,
           let text = selectedVal as? String {
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty { return trimmed }
        }

        // 2. Selection range within value attribute
        var value: CFTypeRef?
        var selected: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXValueAttribute as CFString, &value) == .success,
            let text = value as? String,
            AXUIElementCopyAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, &selected) == .success,
            let selected, CFGetTypeID(selected) == AXValueGetTypeID()
        else { return nil }
        var range = CFRange()
        guard AXValueGetValue(unsafeDowncast(selected, to: AXValue.self), .cfRange, &range), range.length > 0,
            let subrange = Range(NSRange(location: range.location, length: range.length), in: text)
        else { return nil }
        let trimmed = String(text[subrange]).trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    /// Safely reads non-sensitive full field text from an app or internal editor for post-dictation auto-learn diffing.
    static func readFieldText(in target: InjectionTarget?) -> String? {
        if let editor = target?.ownEditor {
            return editor.string
        }
        guard let app = target?.externalApp,
              let element = AccessibilityText.focusedElement(in: app) else { return nil }
        var subroleVal: CFTypeRef?
        if AXUIElementCopyAttributeValue(element, kAXSubroleAttribute as CFString, &subroleVal) == .success,
           let subrole = subroleVal as? String, subrole == kAXSecureTextFieldSubrole {
            return nil
        }
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXValueAttribute as CFString, &value) == .success,
              let text = value as? String else { return nil }
        return text
    }

    /// Safely reads focused window title and document/URL string while strictly redacting credential/2FA apps.
    static func readWindowMetadata(for app: NSRunningApplication?) -> (windowTitle: String?, documentURL: String?) {
        guard let app else { return (nil, nil) }
        let bundle = (app.bundleIdentifier ?? "").lowercased()
        if bundle.contains("keepass") || bundle.contains("ente") || bundle.contains("1password")
            || bundle.contains("bitwarden") || bundle.contains("keychain") {
            return (nil, nil)
        }
        let appElement = AXUIElementCreateApplication(app.processIdentifier)
        var winRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(appElement, kAXFocusedWindowAttribute as CFString, &winRef) == .success,
              let winRef, CFGetTypeID(winRef) == AXUIElementGetTypeID()
        else { return (nil, nil) }
        let winEl = unsafeDowncast(winRef, to: AXUIElement.self)

        var titleRef: CFTypeRef?
        let windowTitle: String? = (AXUIElementCopyAttributeValue(winEl, kAXTitleAttribute as CFString, &titleRef) == .success)
            ? (titleRef as? String)
            : nil

        var docRef: CFTypeRef?
        var documentURL: String?
        if AXUIElementCopyAttributeValue(winEl, kAXDocumentAttribute as CFString, &docRef) == .success,
           let doc = docRef as? String, !doc.isEmpty {
            documentURL = doc
        } else {
            var urlRef: CFTypeRef?
            if AXUIElementCopyAttributeValue(winEl, "AXURL" as CFString, &urlRef) == .success {
                if let url = urlRef as? URL {
                    documentURL = url.absoluteString
                } else if let str = urlRef as? String, !str.isEmpty {
                    documentURL = str
                }
            }
        }
        return (windowTitle, documentURL)
    }

    /// Electron, Chromium, WebViews, terminals, and code editors reliably accept `⌘V` rather than `AXSelectedTextAttribute`.
    static func isEventOnlyTarget(_ bundleID: String?) -> Bool {
        let lower = (bundleID ?? "").lowercased()
        let markers = [
            "vscode", "obsidian", "todesktop", "slack", "discord", "teams",
            "chrome", "safari", "arc", "zen", "firefox", "brave", "edgemac",
            "notion", "linear", "iterm", "terminal", "ghostty", "warp", "alacritty",
            "electron", "cef", "webview", "thebrowser", "xcode"
        ]
        return markers.contains { lower.contains($0) }
    }

    /// Returns true when macOS Secure Event Input (password fields, sudo prompts, 1Password/Bitwarden prompts) is active.
    static var isSecureInputActive: Bool {
        IsSecureEventInputEnabled()
    }

    /// Direct Accessibility insertion via `kAXSelectedTextAttribute` with readback verification (< 3 ms, zero clipboard mutation).
    /// Returns `true` only when the target app confirmed the exact text replacement; otherwise falls back cleanly to `⌘V`.
    static func tryDirectAccessibilityInsert(
        _ text: String,
        cursorOffsetFromEnd: Int? = nil,
        into app: NSRunningApplication?,
        autoLearnBaseline: inout String?
    ) -> Bool {
        guard let app,
              app.isActive,
              !app.isTerminated,
              !IsSecureEventInputEnabled(),
              app.bundleIdentifier != Bundle.main.bundleIdentifier,
              !isEventOnlyTarget(app.bundleIdentifier),
              let element = AccessibilityText.focusedElement(in: app)
        else { return false }

        // Never directly inject into password fields or web marker ranges.
        var subroleVal: CFTypeRef?
        if AXUIElementCopyAttributeValue(element, kAXSubroleAttribute as CFString, &subroleVal) == .success,
           let subrole = subroleVal as? String, subrole == kAXSecureTextFieldSubrole {
            return false
        }
        var markerRef: CFTypeRef?
        if AXUIElementCopyAttributeValue(element, kAXSelectedTextMarkerRangeAttribute as CFString, &markerRef) == .success,
           let markerRef, CFGetTypeID(markerRef) == AXTextMarkerRangeGetTypeID() {
            return false
        }

        var selectedSettable = DarwinBoolean(false)
        var rangeSettable = DarwinBoolean(false)
        guard AXUIElementIsAttributeSettable(element, kAXSelectedTextAttribute as CFString, &selectedSettable) == .success,
              selectedSettable.boolValue,
              AXUIElementIsAttributeSettable(element, kAXSelectedTextRangeAttribute as CFString, &rangeSettable) == .success,
              rangeSettable.boolValue
        else { return false }

        var origValRef: CFTypeRef?
        var origRangeRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXValueAttribute as CFString, &origValRef) == .success,
              let originalValue = origValRef as? String,
              AXUIElementCopyAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, &origRangeRef) == .success,
              let origRangeRef, CFGetTypeID(origRangeRef) == AXValueGetTypeID()
        else { return false }

        var originalRange = CFRange()
        guard AXValueGetValue(unsafeDowncast(origRangeRef, to: AXValue.self), .cfRange, &originalRange),
              let swiftRange = Range(NSRange(location: originalRange.location, length: originalRange.length), in: originalValue)
        else { return false }

        autoLearnBaseline = originalValue

        var expected = originalValue
        expected.replaceSubrange(swiftRange, with: text)

        let setterStatus = AXUIElementSetAttributeValue(element, kAXSelectedTextAttribute as CFString, text as CFString)
        guard setterStatus != .cannotComplete, setterStatus != .invalidUIElement else { return false }

        var observedRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXValueAttribute as CFString, &observedRef) == .success,
              let observed = observedRef as? String,
              observed == expected
        else {
            var restoreRange = originalRange
            if let restoreVal = AXValueCreate(.cfRange, &restoreRange) {
                _ = AXUIElementSetAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, restoreVal)
            }
            return false
        }

        let tailTrim = min(max(cursorOffsetFromEnd ?? 0, 0), text.count)
        let utf16Advance = text[..<text.index(text.endIndex, offsetBy: -tailTrim)].utf16.count
        var finalRange = CFRange(location: originalRange.location + utf16Advance, length: 0)
        if let finalVal = AXValueCreate(.cfRange, &finalRange) {
            _ = AXUIElementSetAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, finalVal)
        }
        return true
    }

    /// Reads the screen-space Cocoa rectangle of the focused text caret (`AXBoundsForRange`) when available.
    static func focusedCaretRect(in app: NSRunningApplication?) -> CGRect? {
        guard let app,
              let element = AccessibilityText.focusedElement(in: app)
        else { return nil }
        var selectedRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, &selectedRef) == .success,
              let selectedRef, CFGetTypeID(selectedRef) == AXValueGetTypeID()
        else { return nil }
        var cfRange = CFRange()
        guard AXValueGetValue(unsafeDowncast(selectedRef, to: AXValue.self), .cfRange, &cfRange) else { return nil }
        var probeRange = CFRange(location: cfRange.location, length: 0)
        guard let probeVal = AXValueCreate(.cfRange, &probeRange) else { return nil }

        var boundsRef: CFTypeRef?
        guard AXUIElementCopyParameterizedAttributeValue(
            element,
            kAXBoundsForRangeParameterizedAttribute as CFString,
            probeVal,
            &boundsRef
        ) == .success,
              let boundsRef, CFGetTypeID(boundsRef) == AXValueGetTypeID()
        else { return nil }
        var quartzRect = CGRect.zero
        guard AXValueGetValue(unsafeDowncast(boundsRef, to: AXValue.self), .cgRect, &quartzRect),
              quartzRect.height > 0
        else { return nil }
        let primaryHeight = NSScreen.screens.first?.frame.height ?? NSScreen.main?.frame.height ?? 1080
        return cocoaRect(fromQuartzAXRect: quartzRect, primaryScreenHeight: primaryHeight)
    }

    /// Converts top-left Quartz Accessibility bounds into bottom-left AppKit screen coordinates.
    static func cocoaRect(fromQuartzAXRect axRect: CGRect, primaryScreenHeight: CGFloat) -> CGRect {
        CGRect(
            x: axRect.origin.x,
            y: primaryScreenHeight - axRect.origin.y - axRect.height,
            width: axRect.width,
            height: axRect.height
        )
    }

    private static func context(_ text: String, range: NSRange) -> DictationTextFormatter.Context? {
        guard let selected = Range(range, in: text) else { return nil }
        return .init(
            before: text[..<selected.lowerBound],
            after: text[selected.upperBound...])
    }
}
