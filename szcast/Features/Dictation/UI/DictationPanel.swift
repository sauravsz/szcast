import AppKit
import Carbon.HIToolbox
import SwiftUI

@MainActor
@Observable
final class DictationDisplayState {
    enum Phase { case listening, transcribing }
    var phase: Phase = .listening
    var levels = [Float](repeating: 0, count: DictationSpectrum.barCount)
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
            let center = (reduceMotion ? 0.5 : progress) * 28 - 4
            DictationWaveform(
                levels: (0..<DictationSpectrum.barCount).map { index in
                    Float(max(0, 1 - abs(Double(index) - center) / 4))
                }, processing: true)
        }
    }
}

private struct DictationPanelView: View {
    let state: DictationDisplayState

    var body: some View {
        HStack(spacing: Theme.Spacing.sm) {
            // Recording status dot
            Circle()
                .fill(state.phase == .listening ? Color.red : Color.accentColor)
                .frame(width: 8, height: 8)
                .shadow(color: (state.phase == .listening ? Color.red : Color.accentColor).opacity(0.6), radius: 3)

            if state.phase == .listening {
                // Compact Level Meter Bars
                HStack(alignment: .center, spacing: 3) {
                    ForEach(0..<10, id: \.self) { i in
                        let level = i < state.levels.count ? state.levels[i] : 0
                        Capsule()
                            .fill(Theme.Colors.textPrimary.opacity(0.75))
                            .frame(width: 2.5, height: max(3, CGFloat(level) * 16))
                    }
                }
                .frame(height: 16)
                .animation(.easeOut(duration: 0.08), value: state.levels)
            } else {
                DictationProcessingWave()
                    .frame(width: 50)
            }

            Text(state.phase == .listening ? "Listening…" : "Transcribing…")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Theme.Colors.textSecondary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .frame(minWidth: 170, minHeight: 36)
        .glassEffect(.regular, in: .capsule)
        .overlay(
            Capsule()
                .stroke(Theme.Colors.border.opacity(0.3), lineWidth: 0.5)
        )
    }
}

private final class DictationPanel: NSPanel, AnimatedPanel {
    var onAccept: (() -> Void)?
    var onCancel: (() -> Void)?

    init(content: NSView) {
        super.init(
            contentRect: NSRect(origin: .zero, size: CGSize(width: 190, height: 40)),
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

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func sendEvent(_ event: NSEvent) {
        if event.type == .keyDown, !event.isARepeat {
            switch Int(event.keyCode) {
            case kVK_Return, kVK_ANSI_KeypadEnter: onAccept?(); return
            case kVK_Escape: onCancel?(); return
            default: break
            }
        }
        super.sendEvent(event)
    }
}

@MainActor
final class DictationPanelController {
    let state = DictationDisplayState()
    private var panel: DictationPanel?
    var onAccept: (() -> Void)?
    var onCancel: (() -> Void)?

    func show() {
        let screen = NSScreen.main ?? NSScreen.screens.first
        guard let frame = screen?.visibleFrame else { return }
        let panel =
            panel
            ?? DictationPanel(
                content: NSHostingView(rootView: DictationPanelView(state: state).motionScope()))
        panel.onAccept = onAccept
        panel.onCancel = onCancel
        self.panel = panel
        let pillSize = CGSize(width: 190, height: 40)
        panel.setFrameOrigin(
            NSPoint(
                x: frame.midX - pillSize.width / 2,
                y: frame.minY + frame.height * 0.08 - pillSize.height / 2))
        state.phase = .listening
        state.levels = [Float](repeating: 0, count: DictationSpectrum.barCount)
        panel.makeKeyAndOrderFront(nil)
    }

    func close() {
        panel?.orderOut(nil)
        panel = nil
    }
}
