import AppKit

/// Plays subtle audio cues for timers and completions when enabled in settings.
@MainActor
final class SensoryAudioPlayer {
    static let shared = SensoryAudioPlayer()

    private let completionSound = NSSound(named: NSSound.Name("Glass"))
    private let tickSound = NSSound(named: NSSound.Name("Tink"))
    private let popSound = NSSound(named: NSSound.Name("Pop"))

    func playCompletion(enabled: Bool = true) {
        guard enabled else { return }
        completionSound?.stop()
        completionSound?.play()
    }

    func playAction(enabled: Bool = true) {
        guard enabled else { return }
        popSound?.stop()
        popSound?.play()
    }

    func playTick(enabled: Bool = true) {
        guard enabled else { return }
        tickSound?.stop()
        tickSound?.play()
    }
}
