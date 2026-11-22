import AppKit
import SwiftUI

/// szcast's own dialogs; `NSAlert`'s nested run loop would let hotkeys stack them.
@MainActor
final class DialogController: NSObject, NSWindowDelegate {
    private let settings: AppSettings
    private let onPresentationChanged: (Bool) -> Void
    private var panel: DialogPanel?
    private var accessory: DialogAccessory?
    private var continuation: CheckedContinuation<Int, Never>?

    init(settings: AppSettings, onPresentationChanged: @escaping (Bool) -> Void) {
        self.settings = settings
        self.onPresentationChanged = onPresentationChanged
    }

    func confirm(
        title: String, message: String?, symbol: String?, tone: DialogTone, confirmTitle: String,
        confirmRole: DialogAction.Role, dismissTitle: String = String(localized: "Cancel")
    ) async -> Bool {
        let request = DialogRequest(
            title: title, message: message, symbol: symbol, tone: tone,
            actions: [
                DialogAction(title: confirmTitle, role: confirmRole),
                DialogAction(title: dismissTitle, role: .cancel)
            ],
            defaultIndex: 0, cancelIndex: 1)
        return await present(request) == 0
    }

    /// More than two ways forward; `options` is in dispatch order and the last one is the cancel.
    func choose(
        title: String, message: String?, symbol: String?, tone: DialogTone,
        options: [DialogAction], defaultIndex: Int
    ) async -> Int {
        let request = DialogRequest(
            title: title, message: message, symbol: symbol, tone: tone, actions: options,
            defaultIndex: defaultIndex, cancelIndex: options.count - 1)
        return await present(request)
    }

    func notice(title: String, message: String, symbol: String, tone: DialogTone) async {
        let request = DialogRequest(
            title: title, message: message, symbol: symbol, tone: tone,
            actions: [DialogAction(title: String(localized: "OK"), role: .cancel)], defaultIndex: 0,
            cancelIndex: 0)
        _ = await present(request)
    }

    /// Something already went wrong, unlike `confirm`; true if recovery was taken.
    func reportFailure(
        title: String, message: String, symbol: String, recovery: String?
    ) async
        -> Bool
    {
        var actions = [DialogAction(title: String(localized: "OK"), role: .cancel)]
        if let recovery { actions.append(DialogAction(title: recovery)) }
        // ↵ lands on the recovery action when there is one to take, not on the OK dismissal.
        let recoveryIndex = recovery == nil ? nil : actions.count - 1
        let request = DialogRequest(
            title: title, message: message, symbol: symbol, tone: .danger,
            actions: actions, defaultIndex: recoveryIndex ?? 0, cancelIndex: 0)
        return await present(request) == recoveryIndex
    }

    func pickVolume(current: Float32) async -> Float32? {
        let volume = VolumeState(level: Double(current))
        let request = DialogRequest(
            title: String(localized: "Set Volume"),
            message: String(localized: "Choose the output volume."), symbol: "speaker.wave.2",
            tone: .neutral,
            actions: [
                DialogAction(title: String(localized: "Set Volume")),
                DialogAction(title: String(localized: "Cancel"), role: .cancel)
            ],
            defaultIndex: 0, cancelIndex: 1, accessory: .volume(volume))
        guard await present(request) == 0 else { return nil }
        return Float32(volume.level)
    }

    func fillSnippetArguments(
        snippetName: String, arguments: [SnippetTemplateEngine.MissingArgument]
    ) async -> [String: String]? {
        let state = SnippetArgumentsState(arguments: arguments)
        let request = DialogRequest(
            title: snippetName, message: nil, symbol: "curlybraces", tone: .neutral,
            actions: [
                DialogAction(title: String(localized: "Expand")),
                DialogAction(title: String(localized: "Cancel"), role: .cancel)
            ],
            defaultIndex: 0, cancelIndex: 1, accessory: .snippetArguments(state))
        guard await present(request) == 0 else { return nil }
        return state.values
    }

    func editClipboardText(_ text: String) async -> String? {
        let state = ClipboardEditState(text: text)
        let request = DialogRequest(
            title: String(localized: "Edit Entry"), message: String(localized: "⌘↵ saves."), symbol: nil,
            actions: [
                DialogAction(title: String(localized: "Save")),
                DialogAction(title: String(localized: "Cancel"), role: .cancel)
            ],
            defaultIndex: 0, cancelIndex: 1, accessory: .clipboardText(state))
        guard await present(request) == 0 else { return nil }
        return state.text
    }

    func editEmojiKeywords(glyph: String, name: String, currentKeywords: [String]) async -> [String]? {
        let state = EmojiKeywordInputState(glyph: glyph, emojiName: name, initialKeywords: currentKeywords)
        let request = DialogRequest(
            title: String(localized: "Custom Keywords"),
            message: String(localized: "Assign custom keywords for \(glyph) \(name.capitalized) to find it faster in search."),
            symbol: nil,
            tone: .neutral,
            actions: [
                DialogAction(title: String(localized: "Save")),
                DialogAction(title: String(localized: "Cancel"), role: .cancel)
            ],
            defaultIndex: 0, cancelIndex: 1, accessory: .emojiKeywords(state))
        guard await present(request) == 0 else { return nil }
        return state.text
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            .filter { !$0.isEmpty }
    }

    func promptAlias(entry: AppEntry, currentAlias: String?) async -> (saved: Bool, alias: String?) {
        let suggested = suggestedAlias(for: entry)
        let placeholder = suggested.isEmpty ? "e.g. \(entry.name.prefix(1).lowercased())" : "e.g. \(suggested)"
        let state = AliasInputState(
            initialText: currentAlias ?? "",
            placeholder: placeholder,
            entryName: entry.name
        )
        var actions = [
            DialogAction(title: String(localized: "Save")),
            DialogAction(title: String(localized: "Cancel"), role: .cancel)
        ]
        let hasCurrent = currentAlias != nil && !currentAlias!.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        if hasCurrent {
            actions.append(DialogAction(title: String(localized: "Remove Alias"), role: .destructive))
        }
        let request = DialogRequest(
            title: String(localized: "Set Alias"),
            message: String(localized: "Type a short keyword to trigger or find “\(entry.name)” in search."),
            symbol: "character",
            tone: .neutral,
            actions: actions,
            defaultIndex: 0,
            cancelIndex: 1,
            accessory: .aliasInput(state)
        )
        let chosen = await present(request)
        if chosen == 0 {
            return (true, state.text.trimmingCharacters(in: .whitespacesAndNewlines))
        } else if hasCurrent && chosen == 2 {
            return (true, "")
        } else {
            return (false, nil)
        }
    }

    private func suggestedAlias(for entry: AppEntry) -> String {
        let words = entry.name.split(separator: " ")
        if words.count > 1 {
            return words.compactMap { $0.first.map(String.init) }.joined().lowercased()
        } else if let first = entry.name.first {
            return String(first).lowercased()
        }
        return ""
    }

    func recordHotKey(entry: AppEntry, action: HotKeyAction, hotKeys: HotKeyManager) async {
        let initialBinding = hotKeys.binding(for: action)
        let state = HotKeyRecordState(entry: entry, action: action, initialBinding: initialBinding)
        var actions: [DialogAction] = []
        if initialBinding != nil {
            actions.append(DialogAction(title: String(localized: "Clear Hotkey"), role: .destructive))
        }
        actions.append(DialogAction(title: String(localized: "Cancel"), role: .cancel))

        let request = DialogRequest(
            title: String(localized: "Record Hotkey"),
            message: String(localized: "Press shortcut keys to assign to “\(entry.name)”. Delete to clear, Esc to cancel."),
            symbol: "keyboard",
            tone: .neutral,
            actions: actions,
            defaultIndex: actions.count - 1,
            cancelIndex: actions.count - 1,
            accessory: .hotKeyRecord(state)
        )

        hotKeys.recordingAction = action
        let chosen = await present(request)
        if initialBinding != nil && chosen == 0 {
            hotKeys.setBinding(nil, for: action)
        }
        if hotKeys.recordingAction == action {
            hotKeys.recordingAction = nil
        }
    }

    private func present(_ request: DialogRequest) async -> Int {
        guard continuation == nil else { return request.cancelIndex }
        return await withCheckedContinuation { continuation in
            self.continuation = continuation
            onPresentationChanged(true)
            let width =
                switch request.accessory {
                case nil, .volume: metrics.size.dialogCompactWidth
                case .snippetArguments(let arguments) where arguments.asksOnlyForChoices:
                    metrics.size.dialogCompactWidth
                case .snippetArguments, .clipboardText: metrics.size.dialogWidth
                case .aliasInput, .hotKeyRecord, .emojiKeywords: max(metrics.size.dialogCompactWidth, 340)
                }
            let content = hostingView(
                DialogView(
                    request: request, width: width,
                    onChoose: { [weak self] index in
                        self?.finish(index)
                    }),
                width: width, minHeight: 0)
            let panel = DialogPanel(content: content, cornerRadius: metrics.radius.panel)
            panel.handlesArrowKeys = request.accessory?.claimsArrowKeys ?? false
            panel.handlesTabKey = request.accessory?.claimsTabKey ?? false
            panel.acceptsLineBreaks = request.accessory?.acceptsLineBreaks ?? false
            panel.delegate = self
            panel.onKey = { [weak self] key in
                guard let self else { return }
                switch key {
                case .cancel:
                    finish(request.cancelIndex)
                case .confirm:
                    finish(request.defaultIndex)
                case .increment, .decrement:
                    // Keying the slider lands on the same values Volume Up/Down produce.
                    guard case .volume(let volume) = request.accessory else { return }
                    volume.level = VolumeLevel.stepped(volume.level, up: key == .increment)
                case .tab, .backtab:
                    guard case .snippetArguments(let arguments) = request.accessory else { return }
                    arguments.moveFocus(backwards: key == .backtab)
                }
            }
            self.panel = panel
            accessory = request.accessory
            place(panel)
            // Non-activating like the palette: key focus without pulling the user out.
            panel.makeKeyAndOrderFront(nil)
            panel.orderFrontRegardless()
        }
    }

    private func finish(_ index: Int) {
        guard let continuation else { return }
        self.continuation = nil
        onPresentationChanged(false)
        let closing = panel
        panel = nil
        accessory = nil
        closing?.delegate = nil
        closing?.onKey = nil
        continuation.resume(returning: index)
        closing?.orderOut(nil)
    }

    private var metrics: InterfaceMetrics { settings.interfaceSize.metrics }

    private func hostingView(_ view: some View, width: CGFloat, minHeight: CGFloat) -> NSView {
        let hosting = NSHostingView(
            rootView: AnyView(view.environment(\.metrics, metrics).motionScope()))
        // Measure at the fixed width first: the message wraps, so height follows width.
        hosting.setFrameSize(NSSize(width: width, height: minHeight))
        let fitted = hosting.fittingSize
        hosting.setFrameSize(NSSize(width: width, height: max(fitted.height, minHeight)))
        return hosting
    }

    private func place(_ panel: NSPanel) {
        guard let visible = NSScreen.underCursor?.visibleFrame else { return }
        let size = panel.frame.size
        panel.setFrameOrigin(
            NSPoint(
                x: visible.midX - size.width / 2,
                y: visible.midY - size.height / 2 + visible.height * Self.centerLift))
    }

    /// Optical centering: an exactly centred dialog reads low, as the palette would.
    private static let centerLift: CGFloat = 0.08
    // MARK: - NSWindowDelegate

    /// After AppKit's own first-responder pick, which a view's focus request can't outlast.
    func windowDidBecomeKey(_ notification: Notification) {
        guard let panel, notification.object as? NSWindow === panel else { return }
        // A text field must be made first responder by AppKit; SwiftUI's request for one is lost.
        if case .snippetArguments(let arguments) = accessory,
            arguments.arguments.first?.options.isEmpty == false
        {
            arguments.focusFirstArgument()
        } else {
            panel.focusFirstTextField()
        }
    }

    /// Click-away resolves as a dismissal rather than leaving an orphaned dialog behind.
    func windowDidResignKey(_ notification: Notification) {
        guard let panel, notification.object as? NSWindow === panel else { return }
        panel.onKey?(.cancel)
    }
}
