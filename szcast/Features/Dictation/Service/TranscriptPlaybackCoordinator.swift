import AVFoundation
import Foundation

@MainActor
@Observable
final class TranscriptPlaybackCoordinator: NSObject, AVAudioPlayerDelegate {
    private var player: AVAudioPlayer?
    private var timerTask: Task<Void, Never>?

    private(set) var loadedRecordID: UUID?
    private(set) var isPlaying = false
    private(set) var currentTime: TimeInterval = 0
    private(set) var duration: TimeInterval = 0
    var rate: Float = 1.0 {
        didSet {
            player?.rate = rate
        }
    }

    func prepare(record: TranscriptRecord?, store: TranscriptStore) {
        guard let record else {
            stop()
            loadedRecordID = nil
            duration = 0
            return
        }
        if loadedRecordID == record.id && player != nil { return }
        stop()
        loadedRecordID = record.id
        duration = record.duration
        guard let url = store.audioURL(for: record),
            let audioPlayer = try? AVAudioPlayer(contentsOf: url)
        else { return }
        audioPlayer.delegate = self
        audioPlayer.enableRate = true
        audioPlayer.rate = rate
        audioPlayer.prepareToPlay()
        player = audioPlayer
        duration = max(audioPlayer.duration, record.duration)
    }

    var canPlay: Bool { player != nil }

    func togglePlayPause() {
        guard let player else { return }
        if player.isPlaying {
            player.pause()
            isPlaying = false
            stopTimer()
        } else {
            player.enableRate = true
            player.rate = rate
            player.play()
            isPlaying = true
            startTimer()
        }
    }

    func seek(to time: TimeInterval, autoPlay: Bool = false) {
        guard let player else { return }
        let clamped = max(0, min(player.duration, time))
        player.currentTime = clamped
        currentTime = clamped
        if autoPlay && !player.isPlaying {
            player.enableRate = true
            player.rate = rate
            player.play()
            isPlaying = true
            startTimer()
        }
    }

    func skip(by delta: TimeInterval) {
        seek(to: currentTime + delta)
    }

    func cycleRate() {
        let rates: [Float] = [1.0, 1.25, 1.5, 2.0]
        if let idx = rates.firstIndex(where: { abs($0 - rate) < 0.05 }) {
            rate = rates[(idx + 1) % rates.count]
        } else {
            rate = 1.0
        }
    }

    func stop() {
        stopTimer()
        player?.stop()
        player = nil
        isPlaying = false
        currentTime = 0
    }

    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor [weak self] in
            self?.isPlaying = false
            self?.currentTime = 0
            self?.stopTimer()
        }
    }

    private func startTimer() {
        stopTimer()
        timerTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                guard let self, let player = self.player, player.isPlaying else { break }
                self.currentTime = player.currentTime
                try? await Task.sleep(for: .milliseconds(33))
            }
        }
    }

    private func stopTimer() {
        timerTask?.cancel()
        timerTask = nil
    }
}
