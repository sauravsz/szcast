import AppKit
import CoreGraphics
import Foundation
import OSLog

extension Notification.Name {
    static let cleanKeyboardCountdownChanged = Notification.Name("szcast.cleanKeyboard.countdownChanged")
}

@MainActor
protocol CleanKeyboardPresenter: AnyObject {
    func show(duration: Int)
    func updateCountdown(_ seconds: Int)
    func closeWindow()
}

@MainActor
final class CleanKeyboardService: Observable {
    static let shared = CleanKeyboardService()
    private static let logger = Logger(subsystem: "com.sauravsz.szcast", category: "CleanKeyboard")

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    weak var presenter: CleanKeyboardPresenter?

    private(set) var isCleaning: Bool = false
    private(set) var remainingSeconds: Int = 0
    private var countdownTimer: Timer?
    private var escapeHoldTimer: Timer?

    init() {}

    func startCleaning(duration: Int = 60) {
        guard !isCleaning else { return }

        guard AXIsProcessTrusted() else {
            Self.logger.warning("Accessibility permission is required for Clean Keyboard mode.")
            let alert = NSAlert()
            alert.messageText = String(localized: "Accessibility Permission Required")
            alert.informativeText = String(localized: "Clean Keyboard mode requires Accessibility permission to intercept keyboard input. Please grant permission in System Settings > Privacy & Security > Accessibility.")
            alert.alertStyle = .warning
            alert.addButton(withTitle: String(localized: "Open Settings"))
            alert.addButton(withTitle: String(localized: "Cancel"))
            if alert.runModal() == .alertFirstButtonReturn {
                if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
                    NSWorkspace.shared.open(url)
                }
            }
            return
        }

        guard installTap() else {
            Self.logger.error("Could not install keyboard event tap. Clean Keyboard mode aborted.")
            return
        }
        isCleaning = true
        remainingSeconds = max(duration, 10)

        presenter?.show(duration: remainingSeconds)
        startCountdownTimer()
        Self.logger.info("Clean Keyboard mode activated for \(self.remainingSeconds) seconds")
    }

    func stopCleaning() {
        guard isCleaning else { return }
        isCleaning = false
        countdownTimer?.invalidate()
        countdownTimer = nil
        escapeHoldTimer?.invalidate()
        escapeHoldTimer = nil

        removeTap()
        presenter?.closeWindow()
        Self.logger.info("Clean Keyboard mode stopped")
    }

    func addTime(seconds: Int = 30) {
        remainingSeconds += seconds
        presenter?.updateCountdown(remainingSeconds)
        NotificationCenter.default.post(
            name: .cleanKeyboardCountdownChanged,
            object: nil,
            userInfo: ["seconds": remainingSeconds]
        )
    }

    private func startCountdownTimer() {
        countdownTimer?.invalidate()
        countdownTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self = self, self.isCleaning else { return }
                if self.remainingSeconds > 1 {
                    self.remainingSeconds -= 1
                    self.presenter?.updateCountdown(self.remainingSeconds)
                    NotificationCenter.default.post(
                        name: .cleanKeyboardCountdownChanged,
                        object: nil,
                        userInfo: ["seconds": self.remainingSeconds]
                    )
                } else {
                    self.stopCleaning()
                }
            }
        }
    }

    private func installTap() -> Bool {
        let mask = (1 << CGEventType.keyDown.rawValue) |
                   (1 << CGEventType.keyUp.rawValue) |
                   (1 << CGEventType.flagsChanged.rawValue)

        let callback: CGEventTapCallBack = { proxy, type, event, refcon in
            guard let refcon = refcon else { return Unmanaged.passUnretained(event) }
            let service = Unmanaged<CleanKeyboardService>.fromOpaque(refcon).takeUnretainedValue()
            return service.handleEvent(proxy: proxy, type: type, event: event)
        }

        let refcon = Unmanaged.passUnretained(self).toOpaque()
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask(mask),
            callback: callback,
            userInfo: refcon
        ) else {
            Self.logger.error("Failed to create CGEventTap for keyboard filtering")
            return false
        }

        self.eventTap = tap
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        self.runLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        return true
    }

    private func removeTap() {
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
            if let source = runLoopSource {
                CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
            }
            CFMachPortInvalidate(tap)
            self.eventTap = nil
            self.runLoopSource = nil
        }
    }

    private func handleEvent(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap = eventTap {
                CGEvent.tapEnable(tap: tap, enable: true)
            }
            return Unmanaged.passUnretained(event)
        }

        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
        let flags = event.flags

        // 1. Control + U unlock shortcut (kVK_ANSI_U = 32)
        if flags.contains(.maskControl) && keyCode == 32 {
            Task { @MainActor in
                self.stopCleaning()
            }
            return nil
        }

        // 2. Escape hold detection (kVK_Escape = 53)
        if keyCode == 53 {
            if type == .keyDown {
                if escapeHoldTimer == nil {
                    escapeHoldTimer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: false) { [weak self] _ in
                        Task { @MainActor in
                            self?.stopCleaning()
                        }
                    }
                }
            } else if type == .keyUp {
                escapeHoldTimer?.invalidate()
                escapeHoldTimer = nil
            }
            return nil
        }

        // Drop all other keyboard events
        return nil
    }
}
