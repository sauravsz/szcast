import Foundation
import Observation

/// Drives the Pomodoro / focus timer state, menu bar item, notifications, and celebrations.
@MainActor
@Observable
final class FocusTimerCoordinator {
    private let settings: AppSettings
    private let sensory: SensoryCoordinator
    private let showMessage: (String, DialogTone) -> Void

    private(set) var mode: FocusTimerMode = .work
    private(set) var status: FocusTimerStatus = .idle
    private(set) var remainingSeconds: Int = 25 * 60
    private(set) var totalSeconds: Int = 25 * 60

    @ObservationIgnored private var tickTask: Task<Void, Never>?
    @ObservationIgnored private var targetEndDate: Date?

    var isActive: Bool {
        status == .running || status == .paused
    }

    var formattedRemaining: String {
        FocusTimerFormatter.format(seconds: remainingSeconds)
    }

    var progress: Double {
        FocusTimerEngine.progress(remaining: remainingSeconds, total: totalSeconds)
    }

    init(
        settings: AppSettings,
        sensory: SensoryCoordinator,
        showMessage: @escaping (String, DialogTone) -> Void
    ) {
        self.settings = settings
        self.sensory = sensory
        self.showMessage = showMessage
        let defaultWork = settings.focusTimerWorkDuration * 60
        self.remainingSeconds = defaultWork
        self.totalSeconds = defaultWork
    }

    func start(mode: FocusTimerMode = .work, customDuration: Int? = nil) {
        tickTask?.cancel()
        self.mode = mode
        let duration: Int = {
            if let customDuration, customDuration > 0 { return customDuration }
            switch mode {
            case .work: return settings.focusTimerWorkDuration * 60
            case .shortBreak: return settings.focusTimerShortBreak * 60
            case .longBreak: return settings.focusTimerLongBreak * 60
            }
        }()

        self.totalSeconds = duration
        self.remainingSeconds = duration
        self.status = .running
        sensory.playActionSound()
        startTicking()
    }

    func pause() {
        guard status == .running else { return }
        tickTask?.cancel()
        targetEndDate = nil
        status = .paused
        sensory.playActionSound()
    }

    func resume() {
        guard status == .paused else { return }
        status = .running
        sensory.playActionSound()
        startTicking()
    }

    func toggle() {
        switch status {
        case .running:
            pause()
        case .paused:
            resume()
        case .idle:
            start(mode: mode)
        }
    }

    func reset() {
        tickTask?.cancel()
        targetEndDate = nil
        status = .idle
        sensory.playActionSound()
        let resetDuration: Int = {
            switch mode {
            case .work: return settings.focusTimerWorkDuration * 60
            case .shortBreak: return settings.focusTimerShortBreak * 60
            case .longBreak: return settings.focusTimerLongBreak * 60
            }
        }()
        remainingSeconds = resetDuration
        totalSeconds = resetDuration
    }

    private func startTicking() {
        tickTask?.cancel()
        let target = Date().addingTimeInterval(Double(remainingSeconds))
        targetEndDate = target
        tickTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                guard let self, !Task.isCancelled, self.status == .running else { break }

                let remaining = max(0, Int(ceil(target.timeIntervalSinceNow)))
                self.remainingSeconds = remaining

                if remaining <= 0 {
                    self.finishCurrentSession()
                    break
                }
            }
        }
    }

    private func finishCurrentSession() {
        tickTask?.cancel()
        status = .idle
        let finishedMode = mode
        sensory.celebrateCompletion()
        showMessage("\(finishedMode.title) complete!", .success)

        // Advance to the logical next mode for convenience
        mode = finishedMode.nextMode
        let nextDuration: Int = {
            switch mode {
            case .work: return settings.focusTimerWorkDuration * 60
            case .shortBreak: return settings.focusTimerShortBreak * 60
            case .longBreak: return settings.focusTimerLongBreak * 60
            }
        }()
        remainingSeconds = nextDuration
        totalSeconds = nextDuration
    }
}
