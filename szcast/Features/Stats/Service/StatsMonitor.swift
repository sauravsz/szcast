import Foundation
import Combine

@MainActor
@Observable
final class StatsMonitor {
    static let shared = StatsMonitor()

    private(set) var snapshot: StatsSnapshot = .empty
    private(set) var isRunning: Bool = false
    var isDashboardActive: Bool = false

    /// Closure invoked on MainActor whenever a fresh telemetry snapshot is captured.
    var onUpdate: (@MainActor (StatsSnapshot) -> Void)?

    // Rolling history for sparklines (up to 30 points)
    private(set) var cpuHistory: [Double] = []
    private(set) var ramHistory: [Double] = []
    private(set) var networkDownloadHistory: [Double] = []
    private(set) var networkUploadHistory: [Double] = []

    private var timer: Timer?
    private let reader = SystemTelemetryReader.shared
    private var lastInterval: Double = 1.0

    init() {}

    func start(interval: Double = 1.0) {
        guard !isRunning else {
            if interval != lastInterval {
                stop()
                start(interval: interval)
            }
            return
        }

        lastInterval = interval
        isRunning = true

        // Capture initial reading
        update()

        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.update()
            }
        }
        if let timer = timer {
            RunLoop.main.add(timer, forMode: .common)
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        isRunning = false
    }

    func refresh() {
        update()
    }

    private func update() {
        let snap = reader.captureSnapshot(processLimit: isDashboardActive ? 6 : 0)
        snapshot = snap

        // Append history
        let maxPoints = 30
        cpuHistory.append(snap.cpu.totalUsage)
        if cpuHistory.count > maxPoints { cpuHistory.removeFirst() }

        ramHistory.append(snap.ram.usagePercentage)
        if ramHistory.count > maxPoints { ramHistory.removeFirst() }

        networkDownloadHistory.append(snap.network.downloadBytesPerSecond)
        if networkDownloadHistory.count > maxPoints { networkDownloadHistory.removeFirst() }

        networkUploadHistory.append(snap.network.uploadBytesPerSecond)
        if networkUploadHistory.count > maxPoints { networkUploadHistory.removeFirst() }

        onUpdate?(snap)
    }
}
