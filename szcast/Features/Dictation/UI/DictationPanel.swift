import AppKit
import Carbon.HIToolbox
import SwiftUI

@MainActor
@Observable
final class DictationDisplayState {
    enum Phase { case listening, transcribing, completed, fallback }
    var phase: Phase = .listening
    var levels = [Float](repeating: 0, count: DictationSpectrum.barCount)
    var previewText: String = ""
    var isLockedHandsFree: Bool = false
    var isWhisperMode: Bool = false
    var isMicSilent: Bool = false
    var isClamshellMuffled: Bool = false
    var isMuted: Bool = false
    var isRawMode: Bool = false
    var isSpeechActive: Bool = false
    var isCompact: Bool = false
    var activeLanguageCode: String? = nil
    var commandModeText: String? = nil
    var fallbackText: String? = nil
    var fallbackSubtitle: String? = nil
    var onToggleMute: (() -> Void)?
    var onAccept: (() -> Void)?
    var onCancel: (() -> Void)?
    var onSelectLanguage: ((String?) -> Void)?
    var onCopyFallback: (() -> Void)?
    var onRetryPasteFallback: (() -> Void)?
}

private struct DictationWaveform: View {
    let levels: [Float]
    let processing: Bool

    var body: some View {
        HStack(alignment: .center, spacing: Theme.Spacing.dictationWaveGap) {
            ForEach(levels.indices, id: \.self) { index in
                let emphasis =
                    processing
                    ? Double(levels[index])
                    : min(1, Double(min(index, levels.count - 1 - index)) / 3)
                Capsule()
                    .fill(Theme.Colors.textPrimary.opacity(0.4 + 0.6 * emphasis))
                    .frame(
                        width: Theme.Size.dictationWaveBar,
                        height: 3 + (processing ? 9 : 25) * CGFloat(levels[index]))
            }
        }
        .animation(.easeOut(duration: 0.06), value: levels)
    }
}

private struct DictationProcessingWave: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var startedAt = Date()

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: reduceMotion)) { timeline in
            let progress =
                timeline.date.timeIntervalSince(startedAt)
                .truncatingRemainder(dividingBy: 1.2) / 1.2
            let center = (reduceMotion ? 0.5 : progress) * 10 - 2
            HStack(alignment: .center, spacing: 2.5) {
                ForEach(0..<6, id: \.self) { index in
                    let level = Float(max(0, 1 - abs(Double(index) - center) / 2.0))
                    Capsule()
                        .fill(Color.accentColor.opacity(0.4 + 0.6 * Double(level)))
                        .frame(width: 2, height: max(3, 4 + 8 * CGFloat(level)))
                }
            }
            .frame(width: 26, height: 14)
        }
    }
}

private struct DictationPanelView: View {
    let state: DictationDisplayState
    @State private var isHovering = false

    private static let quickLanguages: [(title: String, settingValue: String?)] = [
        ("Automatic", nil),
        ("English", "English"),
        ("Hindi", "Hindi"),
        ("Bengali", "Bengali"),
        ("Spanish", "Spanish"),
        ("French", "French"),
        ("German", "German")
    ]

    private var dotColor: Color {
        switch state.phase {
        case .listening:
            return state.isSpeechActive ? Color.accentColor : Color.red
        case .transcribing:
            return Color.accentColor
        case .completed:
            return Color.green
        case .fallback:
            return Color.orange
        }
    }

    private var accessibilityStatusSummary: String {
        switch state.phase {
        case .listening:
            if state.isMicSilent { return String(localized: "Dictation listening, no microphone input detected") }
            return state.isLockedHandsFree
                ? String(localized: "Dictation listening hands-free")
                : String(localized: "Dictation listening")
        case .transcribing:
            return String(localized: "Transcribing speech")
        case .completed:
            return String(localized: "Dictation inserted")
        case .fallback:
            return state.fallbackSubtitle ?? String(localized: "Copied to clipboard")
        }
    }

    var body: some View {
        Group {
            if state.phase == .fallback {
                fallbackCardBody
            } else if state.isCompact {
                compactPillBody
            } else {
                standardPillBody
            }
        }
        .onHover { hovering in
            isHovering = hovering
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(accessibilityStatusSummary)
    }

    private var fallbackCardBody: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(Color.orange)
                .frame(width: 8, height: 8)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(state.fallbackSubtitle ?? String(localized: "Copied — Focus field & press ⌘V"))
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Theme.Colors.textPrimary)
                    .lineLimit(1)
                if let text = state.fallbackText, !text.isEmpty {
                    Text(text)
                        .font(.system(size: 10))
                        .foregroundStyle(Theme.Colors.textSecondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: 6) {
                if let copy = state.onCopyFallback {
                    Button(action: copy) {
                        Image(systemName: "doc.on.doc")
                            .font(.system(size: 11, weight: .medium))
                    }
                    .buttonStyle(.plain)
                    .help("Copy text")
                    .accessibilityLabel("Copy dictated text")
                }
                if let retryPaste = state.onRetryPasteFallback {
                    Button(action: retryPaste) {
                        Text("Paste")
                            .font(.system(size: 10, weight: .semibold))
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(Capsule().fill(Color.accentColor.opacity(0.22)))
                    }
                    .buttonStyle(.plain)
                    .help("Paste into active app")
                    .accessibilityLabel("Paste into focused field")
                }
                if let dismiss = state.onCancel {
                    Button(action: dismiss) {
                        Image(systemName: "xmark")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(Theme.Colors.textSecondary)
                    }
                    .buttonStyle(.plain)
                    .help("Dismiss")
                    .accessibilityLabel("Dismiss notification")
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(width: 360, height: 52)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Theme.Colors.border.opacity(0.35), lineWidth: 0.5)
        )
    }

    private var compactPillBody: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(dotColor)
                .frame(width: 7, height: 7)
                .shadow(color: dotColor.opacity(0.6), radius: state.isSpeechActive ? 3 : 2)
                .accessibilityHidden(true)

            if state.phase == .completed {
                Image(systemName: "checkmark")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Color.green)
            } else if state.phase == .listening {
                HStack(alignment: .center, spacing: 2) {
                    ForEach(0..<6, id: \.self) { i in
                        let level = i < state.levels.count ? state.levels[i] : 0
                        Capsule()
                            .fill(state.isSpeechActive ? Color.accentColor : Theme.Colors.textPrimary.opacity(0.75))
                            .frame(width: 2, height: max(3, CGFloat(level) * 14))
                    }
                }
                .frame(width: 26, height: 14)
                .animation(.easeOut(duration: 0.08), value: state.levels)

                if state.isLockedHandsFree || isHovering {
                    if let accept = state.onAccept {
                        Button(action: accept) {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 12))
                                .foregroundStyle(Color.green)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Finish dictation")
                    }
                    if let cancel = state.onCancel {
                        Button(action: cancel) {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 12))
                                .foregroundStyle(Theme.Colors.textSecondary)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Cancel dictation")
                    }
                }
            } else {
                DictationProcessingWave()
                    .frame(width: 26, height: 14)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .frame(minWidth: 74, maxWidth: (state.isLockedHandsFree || isHovering) ? 120 : 88, minHeight: 34, maxHeight: 34)
        .glassEffect(.regular, in: .capsule)
        .overlay(
            Capsule()
                .stroke(Theme.Colors.border.opacity(0.3), lineWidth: 0.5)
        )
    }

    private var standardPillBody: some View {
        HStack(spacing: 6) {
            // Recording status dot
            Circle()
                .fill(dotColor)
                .frame(width: 7, height: 7)
                .shadow(color: dotColor.opacity(0.6), radius: state.isSpeechActive ? 3.5 : 2)
                .accessibilityHidden(true)

            if state.phase == .completed {
                Image(systemName: "checkmark")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Color.green)
                    .accessibilityHidden(true)
                Text("Done")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Color.green)
                    .lineLimit(1)
            } else if state.phase == .listening {
                // Compact Level Meter Bars (6 bars)
                HStack(alignment: .center, spacing: 2) {
                    ForEach(0..<6, id: \.self) { i in
                        let level = i < state.levels.count ? state.levels[i] : 0
                        Capsule()
                            .fill(state.isSpeechActive ? Color.accentColor : Theme.Colors.textPrimary.opacity(0.75))
                            .frame(width: 2, height: max(3, CGFloat(level) * 14))
                    }
                }
                .frame(width: 26, height: 14)
                .animation(.easeOut(duration: 0.08), value: state.levels)
                .accessibilityHidden(true)

                if state.isMicSilent {
                    HStack(spacing: 3) {
                        Image(systemName: "mic.slash.fill")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(Color.orange)
                        Text("No sound detected")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(Color.orange)
                    }
                } else if state.isClamshellMuffled {
                    HStack(spacing: 3) {
                        Image(systemName: "laptopcomputer.slash")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(Color.yellow)
                        Text("Lid closed (mic muffled)")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(Color.yellow)
                    }
                } else if let cmd = state.commandModeText, !cmd.isEmpty {
                    Image(systemName: "pencil.line")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Color.accentColor)
                    Text("Rewrite: \(cmd)")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Theme.Colors.textPrimary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else if !state.previewText.isEmpty {
                    Text(state.previewText)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Theme.Colors.textPrimary)
                        .lineLimit(1)
                        .truncationMode(.head)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .accessibilityLabel("Live dictation preview")
                        .accessibilityValue(state.previewText)
                } else {
                    Text(state.isWhisperMode ? "Whisper listening…" : "Listening…")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Theme.Colors.textSecondary)
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)
                }

                if state.isLockedHandsFree || isHovering {
                    if let toggleMute = state.onToggleMute {
                        Button(action: toggleMute) {
                            Image(systemName: state.isMuted ? "mic.slash.fill" : "mic.fill")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(state.isMuted ? Color.red : Color.secondary)
                        }
                        .buttonStyle(.plain)
                        .help(state.isMuted ? "Unmute Microphone" : "Mute Microphone")
                        .accessibilityLabel(state.isMuted ? "Unmute microphone" : "Mute microphone")
                    }
                    if state.isLockedHandsFree, let onSelectLang = state.onSelectLanguage {
                        Menu {
                            ForEach(Self.quickLanguages, id: \.title) { entry in
                                Button(entry.title) {
                                    onSelectLang(entry.settingValue)
                                }
                            }
                        } label: {
                            Text(state.activeLanguageCode ?? "AUTO")
                                .font(.system(size: 8, weight: .bold))
                                .padding(.horizontal, 4)
                                .padding(.vertical, 2)
                                .background(Capsule().fill(Theme.Colors.border.opacity(0.28)))
                        }
                        .menuStyle(.borderlessButton)
                        .fixedSize()
                        .help("Switch dictation language")
                        .accessibilityLabel("Switch dictation language")
                        .accessibilityValue(state.activeLanguageCode ?? "Automatic")
                    }
                    if state.isLockedHandsFree, let onAccept = state.onAccept {
                        Button(action: onAccept) {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 12))
                                .foregroundStyle(Color.green)
                        }
                        .buttonStyle(.plain)
                        .help("Finish & Insert")
                        .accessibilityLabel("Finish dictation")
                    }
                    if let onCancel = state.onCancel {
                        Button(action: onCancel) {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 12))
                                .foregroundStyle(Theme.Colors.textSecondary)
                        }
                        .buttonStyle(.plain)
                        .help("Cancel Dictation (Esc)")
                        .accessibilityLabel("Cancel dictation")
                    }
                }
                if state.isRawMode {
                    Text("RAW")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(Color.secondary)
                }
            } else {
                DictationProcessingWave()
                    .frame(width: 26, height: 14)

                Text("Transcribing…")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .frame(
            minWidth: 160,
            maxWidth: (state.commandModeText != nil && !state.commandModeText!.isEmpty)
                ? 360
                : (state.previewText.isEmpty ? (state.isLockedHandsFree ? 250 : 192) : 360),
            minHeight: 36, maxHeight: 36
        )
        .glassEffect(.regular, in: .capsule)
        .overlay(
            Capsule()
                .stroke(Theme.Colors.border.opacity(0.3), lineWidth: 0.5)
        )
    }
}

private final class DictationPanel: NSPanel, AnimatedPanel {
    init(content: NSView) {
        super.init(
            contentRect: NSRect(origin: .zero, size: CGSize(width: 192, height: 36)),
            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        contentView = content
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        followMotion()
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

@MainActor
final class DictationPanelController {
    let state = DictationDisplayState()
    private var panel: DictationPanel?
    private var globalEventMonitor: Any?
    private var localEventMonitor: Any?
    private var activePosition: DictationPillPosition = .bottomCenter
    private var activeCaretRect: CGRect?
    private var lastResizeInstant: CFAbsoluteTime = 0
    private var fallbackDismissTask: Task<Void, Never>?
    var onAccept: (() -> Void)?
    var onCancel: (() -> Void)?

    /// Computes pill origin on screen across Bottom Center, Top Notch, Top Right, and Near Caret placements.
    static func frameForPill(
        size: CGSize,
        position: DictationPillPosition,
        visibleFrame: CGRect,
        fullFrame: CGRect,
        caretRect: CGRect?
    ) -> NSRect {
        let margin: CGFloat = 14
        let origin: CGPoint
        switch position {
        case .bottomCenter:
            origin = CGPoint(
                x: visibleFrame.midX - size.width / 2,
                y: visibleFrame.minY + visibleFrame.height * 0.08 - size.height / 2
            )
        case .topNotch:
            let topSafeY = min(visibleFrame.maxY - size.height - 6, fullFrame.maxY - 38 - size.height)
            origin = CGPoint(
                x: visibleFrame.midX - size.width / 2,
                y: max(visibleFrame.minY + margin, topSafeY)
            )
        case .topRight:
            origin = CGPoint(
                x: visibleFrame.maxX - size.width - 18,
                y: visibleFrame.maxY - size.height - margin
            )
        case .nearCaret:
            if let caret = caretRect, caret.height > 0 {
                let clampedX = min(
                    max(caret.minX, visibleFrame.minX + margin),
                    visibleFrame.maxX - size.width - margin
                )
                let belowY = caret.minY - size.height - 8
                let finalY = belowY >= visibleFrame.minY + margin
                    ? belowY
                    : min(visibleFrame.maxY - size.height - margin, caret.maxY + 8)
                origin = CGPoint(x: clampedX, y: finalY)
            } else {
                origin = CGPoint(
                    x: visibleFrame.midX - size.width / 2,
                    y: visibleFrame.minY + visibleFrame.height * 0.08 - size.height / 2
                )
            }
        }
        return NSRect(origin: origin, size: size)
    }

    func show(
        position: DictationPillPosition = .bottomCenter,
        compact: Bool = false,
        caretRect: CGRect? = nil,
        activeLanguage: String? = nil
    ) {
        fallbackDismissTask?.cancel()
        fallbackDismissTask = nil
        let screen = NSScreen.main ?? NSScreen.screens.first
        guard let screen else { return }
        activePosition = position
        activeCaretRect = caretRect
        let panel =
            self.panel
            ?? DictationPanel(
                content: NSHostingView(rootView: DictationPanelView(state: state).motionScope()))
        self.panel = panel
        state.isCompact = compact
        state.activeLanguageCode = DictationLanguage.isoCode(for: activeLanguage)?.uppercased()
        state.fallbackText = nil
        state.fallbackSubtitle = nil
        state.isSpeechActive = false
        let isCommand = state.commandModeText != nil && !(state.commandModeText?.isEmpty ?? true)
        let pillWidth: CGFloat
        if compact {
            pillWidth = state.isLockedHandsFree ? 116 : 84
        } else if isCommand {
            pillWidth = min(360, max(240, CGFloat((state.commandModeText?.count ?? 0) * 7 + 110)))
        } else {
            pillWidth = state.isLockedHandsFree ? 248 : 192
        }
        let pillSize = CGSize(width: pillWidth, height: compact ? 34 : 36)
        panel.setFrame(
            Self.frameForPill(
                size: pillSize,
                position: position,
                visibleFrame: screen.visibleFrame,
                fullFrame: screen.frame,
                caretRect: caretRect
            ),
            display: true
        )
        state.phase = .listening
        state.levels = [Float](repeating: 0, count: DictationSpectrum.barCount)
        state.previewText = ""
        state.isMicSilent = false
        state.isClamshellMuffled = false
        panel.orderFrontRegardless()

        installEscapeMonitors()
    }

    func updatePreviewText(_ text: String) {
        state.previewText = text
        guard !state.isCompact, let panel, let screen = panel.screen ?? NSScreen.main else { return }
        let now = CFAbsoluteTimeGetCurrent()
        let isCommand = state.commandModeText != nil && !(state.commandModeText?.isEmpty ?? true)
        let targetWidth: CGFloat
        if isCommand {
            targetWidth = min(360, max(240, CGFloat((state.commandModeText?.count ?? 0) * 7 + 110)))
        } else if text.isEmpty {
            targetWidth = state.isLockedHandsFree ? 248 : 192
        } else {
            targetWidth = min(360, max(192, CGFloat(text.count * 7 + (state.isLockedHandsFree ? 120 : 85))))
        }
        let diff = abs(panel.frame.width - targetWidth)
        guard diff > 8 else { return }
        guard now - lastResizeInstant >= 0.14 || diff >= 28 || text.isEmpty else { return }
        lastResizeInstant = now

        let newFrame = Self.frameForPill(
            size: CGSize(width: targetWidth, height: 36),
            position: activePosition,
            visibleFrame: screen.visibleFrame,
            fullFrame: screen.frame,
            caretRect: activeCaretRect
        )
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.12
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().setFrame(newFrame, display: true)
        }
    }

    func showFallbackCard(text: String, subtitle: String) {
        fallbackDismissTask?.cancel()
        let screen = NSScreen.main ?? NSScreen.screens.first
        guard let screen else { return }
        let panel =
            self.panel
            ?? DictationPanel(
                content: NSHostingView(rootView: DictationPanelView(state: state).motionScope()))
        self.panel = panel
        state.fallbackText = text
        state.fallbackSubtitle = subtitle
        state.phase = .fallback
        let cardFrame = Self.frameForPill(
            size: CGSize(width: 360, height: 52),
            position: activePosition,
            visibleFrame: screen.visibleFrame,
            fullFrame: screen.frame,
            caretRect: activeCaretRect
        )
        panel.setFrame(cardFrame, display: true)
        panel.orderFrontRegardless()
        installEscapeMonitors()

        fallbackDismissTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(4.5))
            guard !Task.isCancelled else { return }
            self?.close()
        }
    }

    func showSuccessAndClose() {
        fallbackDismissTask?.cancel()
        fallbackDismissTask = nil
        state.phase = .completed
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(350))
            self?.close()
        }
    }

    func close() {
        fallbackDismissTask?.cancel()
        fallbackDismissTask = nil
        removeEscapeMonitors()
        panel?.orderOut(nil)
        panel = nil
    }

    private func installEscapeMonitors() {
        if globalEventMonitor == nil {
            globalEventMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
                if event.keyCode == UInt16(kVK_Escape) {
                    Task { @MainActor [weak self] in
                        self?.onCancel?()
                    }
                }
            }
        }
        if localEventMonitor == nil {
            localEventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                if event.keyCode == UInt16(kVK_Escape) {
                    self?.onCancel?()
                    return nil
                }
                return event
            }
        }
    }

    private func removeEscapeMonitors() {
        if let monitor = globalEventMonitor {
            NSEvent.removeMonitor(monitor)
            globalEventMonitor = nil
        }
        if let monitor = localEventMonitor {
            NSEvent.removeMonitor(monitor)
            localEventMonitor = nil
        }
    }
}
