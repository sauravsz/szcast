import AppKit
@preconcurrency import ApplicationServices

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

    private static func context(_ text: String, range: NSRange) -> DictationTextFormatter.Context? {
        guard let selected = Range(range, in: text) else { return nil }
        return .init(
            before: text[..<selected.lowerBound],
            after: text[selected.upperBound...])
    }
}
