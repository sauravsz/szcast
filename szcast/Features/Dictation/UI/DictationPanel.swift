import AppKit
import Carbon.HIToolbox
import SwiftUI

@MainActor
@Observable
final class DictationDisplayState {
    enum Phase { case listening, transcribing }
    var phase: Phase = .listening
    var levels = [Float](repeating: 0, count: DictationSpectrum.barCount)
    var previewText: String = ""
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

    var body: some View {
        HStack(spacing: 6) {
            // Recording status dot
            Circle()
                .fill(state.phase == .listening ? Color.red : Color.accentColor)
                .frame(width: 7, height: 7)
                .shadow(color: (state.phase == .listening ? Color.red : Color.accentColor).opacity(0.6), radius: 2)

            if state.phase == .listening {
                // Compact Level Meter Bars (6 bars)
                HStack(alignment: .center, spacing: 2) {
                    ForEach(0..<6, id: \.self) { i in
                        let level = i < state.levels.count ? state.levels[i] : 0
                        Capsule()
                            .fill(Theme.Colors.textPrimary.opacity(0.75))
                            .frame(width: 2, height: max(3, CGFloat(level) * 14))
                    }
                }
                .frame(width: 26, height: 14)
                .animation(.easeOut(duration: 0.08), value: state.levels)

                if !state.previewText.isEmpty {
                    Text(state.previewText)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Theme.Colors.textPrimary)
                        .lineLimit(1)
                        .truncationMode(.head)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    Text("Listening…")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Theme.Colors.textSecondary)
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)
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
        .frame(minWidth: 120, maxWidth: 192, minHeight: 36, maxHeight: 36)
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
    var onAccept: (() -> Void)?
    var onCancel: (() -> Void)?

    func show() {
        let screen = NSScreen.main ?? NSScreen.screens.first
        guard let frame = screen?.visibleFrame else { return }
        let panel =
            panel
            ?? DictationPanel(
                content: NSHostingView(rootView: DictationPanelView(state: state).motionScope()))
        self.panel = panel
        let pillSize = CGSize(width: 192, height: 36)
        panel.setFrameOrigin(
            NSPoint(
                x: frame.midX - pillSize.width / 2,
                y: frame.minY + frame.height * 0.08 - pillSize.height / 2))
        state.phase = .listening
        state.levels = [Float](repeating: 0, count: DictationSpectrum.barCount)
        state.previewText = ""
        panel.orderFrontRegardless()

        installEscapeMonitors()
    }

    func close() {
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
