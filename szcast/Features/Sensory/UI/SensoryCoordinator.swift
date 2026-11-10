import AppKit

/// Coordinates subtle haptic/audio cues and confetti animations across features.
@MainActor
final class SensoryCoordinator {
    private let settings: AppSettings

    init(settings: AppSettings) {
        self.settings = settings
    }

    func playCompletionSound() {
        SensoryAudioPlayer.shared.playCompletion(enabled: settings.soundEffectsEnabled)
    }

    func playActionSound() {
        SensoryAudioPlayer.shared.playAction(enabled: settings.soundEffectsEnabled)
    }

    func playTickSound() {
        SensoryAudioPlayer.shared.playTick(enabled: settings.soundEffectsEnabled)
    }

    func burstConfetti(screen: NSScreen? = nil) {
        guard settings.confettiEnabled else { return }
        ConfettiWindowController.shared.burst(screen: screen)
    }

    func celebrateCompletion(screen: NSScreen? = nil) {
        playCompletionSound()
        burstConfetti(screen: screen)
    }
}
