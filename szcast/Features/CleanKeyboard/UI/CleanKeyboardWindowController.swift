import AppKit
import SwiftUI

@MainActor
final class CleanKeyboardWindowController: NSWindowController, CleanKeyboardPresenter {
    private let service: CleanKeyboardService
    private var currentSeconds: Int = 60

    init(service: CleanKeyboardService) {
        self.service = service

        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 380, height: 280),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.modalPanel.rawValue + 3)
        panel.ignoresMouseEvents = false
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isReleasedWhenClosed = false

        super.init(window: panel)
        service.presenter = self
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func show(duration: Int) {
        currentSeconds = duration
        guard let panel = window as? NSPanel else { return }

        let rootView = CleanKeyboardOverlayView(
            service: service,
            initialSeconds: duration
        )
        let hostingView = NSHostingView(rootView: rootView)
        panel.contentView = hostingView
        panel.center()
        panel.orderFrontRegardless()
    }

    func updateCountdown(_ seconds: Int) {
        currentSeconds = seconds
    }

    func closeWindow() {
        window?.orderOut(nil)
    }
}

struct CleanKeyboardOverlayView: View {
    let service: CleanKeyboardService
    @State private var remainingSeconds: Int

    init(service: CleanKeyboardService, initialSeconds: Int) {
        self.service = service
        _remainingSeconds = State(initialValue: initialSeconds)
    }

    private var formattedTime: String {
        let mins = remainingSeconds / 60
        let secs = remainingSeconds % 60
        return String(format: "%02d:%02d", mins, secs)
    }

    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "lock.shield.fill")
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(Color.orange)
                Text(String(localized: "Clean Keyboard Mode"))
                    .font(.title3.weight(.bold))
                    .foregroundStyle(.primary)
            }
            .padding(.top, 8)

            Text(String(localized: "Wipe down your keyboard safely. All keystrokes are blocked."))
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 12)

            // Timer display
            Text(formattedTime)
                .font(.system(size: 40, weight: .heavy, design: .monospaced))
                .foregroundStyle(.primary)
                .padding(.vertical, 4)

            Text(String(localized: "Hold Escape for 3s or press Control + U to unlock"))
                .font(.caption2)
                .foregroundStyle(.secondary)

            HStack(spacing: 12) {
                Button {
                    service.addTime(seconds: 30)
                    remainingSeconds += 30
                } label: {
                    Label(String(localized: "+30s"), systemImage: "plus")
                        .font(.body.weight(.medium))
                }
                .buttonStyle(.bordered)
                .controlSize(.regular)

                Button {
                    service.stopCleaning()
                } label: {
                    Label(String(localized: "Unlock Keyboard"), systemImage: "lock.open.fill")
                        .font(.body.weight(.semibold))
                }
                .buttonStyle(.borderedProminent)
                .tint(Color.orange)
                .controlSize(.regular)
            }
            .padding(.top, 4)
        }
        .padding(24)
        .frame(width: 380, height: 270)
        .background {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(Color.primary.opacity(0.12), lineWidth: 1)
                }
        }
        .onReceive(NotificationCenter.default.publisher(for: .cleanKeyboardCountdownChanged)) { notification in
            if let secs = notification.userInfo?["seconds"] as? Int {
                remainingSeconds = secs
            }
        }
    }
}
