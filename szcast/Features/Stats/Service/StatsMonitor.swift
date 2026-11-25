import Foundation

enum StatsModule: String, CaseIterable, Identifiable, Sendable {
    case cpu
    case ram
    case disk
    case battery
    case network

    var id: String { rawValue }
}

@MainActor
@Observable
final class StatsMonitor {
    static let shared = StatsMonitor()

    private(set) var snapshot: StatsSnapshot = .empty
    private(set) var isRunning: Bool = false
    var isDashboardActive: Bool = false
    var activePopover: StatsModule? = nil {
        didSet {
            if activePopover != oldValue, activePopover != nil {
                refreshOnPopoverOpen()
            }
        }
    }

    var onUpdate: (@MainActor (StatsSnapshot) -> Void)?

    private(set) var cpuHistory: [Double] = []
    private(set) var ramHistory: [Double] = []
    private(set) var diskReadHistory: [Double] = []
    private(set) var diskWriteHistory: [Double] = []
    private(set) var networkDownloadHistory: [Double] = []
    private(set) var networkUploadHistory: [Double] = []

    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private let reader = SystemTelemetryReader.shared
    @ObservationIgnored private var lastInterval: Double = 1.0
    @ObservationIgnored private var processTask: Task<Void, Never>?
    @ObservationIgnored private var netProcessTask: Task<Void, Never>?
    @ObservationIgnored private var pingTask: Task<Void, Never>?
    @ObservationIgnored private var publicIPTask: Task<Void, Never>?

    @ObservationIgnored private var cachedProcesses: (byCPU: [SystemProcessInfo], byRAM: [SystemProcessInfo]) = ([], [])
    @ObservationIgnored private var cachedNetProcesses: [NetworkProcessInfo] = []
    @ObservationIgnored private var prevNetProcessCounters: (
        counters: [Int32: NetworkTelemetryService.ProcessNetCounter], time: Date
    )?

    @ObservationIgnored private var isInternetUp = false
    @ObservationIgnored private var latencyMs: Double?
    @ObservationIgnored private var jitterMs: Double?
    @ObservationIgnored private var lastLatencySampleMs: Double?
    @ObservationIgnored private var connectivityHistory: [Bool] = []
    @ObservationIgnored private var lastPingAt: Date = .distantPast

    @ObservationIgnored private var publicIPv4: String?
    @ObservationIgnored private var publicCountryCode: String?
    @ObservationIgnored private var lastPublicIPFetchAt: Date = .distantPast
    @ObservationIgnored private var lastSeenLocalIP: String?
    @ObservationIgnored private var lastSeenInterface: String?

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

        update()

        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.update()
            }
        }
        if let timer {
            RunLoop.main.add(timer, forMode: .common)
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        processTask?.cancel()
        netProcessTask?.cancel()
        pingTask?.cancel()
        publicIPTask?.cancel()
        processTask = nil
        netProcessTask = nil
        pingTask = nil
        publicIPTask = nil
        isRunning = false
    }

    func refresh() {
        update()
    }

    func refreshNetworkAddress() {
        lastPublicIPFetchAt = .distantPast
        fetchPublicIPIfNeeded(force: true)
    }

    func refreshNetworkInterface() {
        triggerPing()
        update()
    }

    private func refreshOnPopoverOpen() {
        if isRunning {
            scheduleTopProcessesIfNeeded()
            if activePopover == .network {
                scheduleNettopIfNeeded()
                triggerPing()
                fetchPublicIPIfNeeded(force: false)
            }
            update()
        }
    }

    private func update() {
        let cpu = reader.readCPU()
        let ram = reader.readRAM()
        let disk = reader.readDisk()
        let battery = reader.readBattery()
        let network = reader.readNetwork(
            isInternetUp: isInternetUp,
            latencyMs: latencyMs,
            jitterMs: jitterMs,
            publicIPv4: publicIPv4,
            publicCountryCode: publicCountryCode,
            connectivityHistory: connectivityHistory
        )

        if lastSeenLocalIP != network.localIP || lastSeenInterface != network.interfaceName {
            lastSeenLocalIP = network.localIP
            lastSeenInterface = network.interfaceName
            fetchPublicIPIfNeeded(force: true)
        } else {
            fetchPublicIPIfNeeded(force: false)
        }

        let pingCadence: TimeInterval = activePopover == .network ? 2.0 : 10.0
        if Date().timeIntervalSince(lastPingAt) >= pingCadence {
            triggerPing()
        }

        scheduleTopProcessesIfNeeded()
        if activePopover == .network {
            scheduleNettopIfNeeded()
        }

        let snap = StatsSnapshot(
            timestamp: Date(),
            cpu: cpu,
            ram: ram,
            disk: disk,
            battery: battery,
            network: network,
            topProcessesByCPU: cachedProcesses.byCPU,
            topProcessesByRAM: cachedProcesses.byRAM,
            topProcessesByNetwork: cachedNetProcesses
        )
        snapshot = snap

        let maxPoints = 60
        appendHistory(&cpuHistory, value: snap.cpu.totalUsage, limit: maxPoints)
        appendHistory(&ramHistory, value: snap.ram.usagePercentage, limit: maxPoints)
        appendHistory(&diskReadHistory, value: snap.disk.readBytesPerSecond, limit: maxPoints)
        appendHistory(&diskWriteHistory, value: snap.disk.writeBytesPerSecond, limit: maxPoints)
        appendHistory(&networkDownloadHistory, value: snap.network.downloadBytesPerSecond, limit: maxPoints)
        appendHistory(&networkUploadHistory, value: snap.network.uploadBytesPerSecond, limit: maxPoints)

        onUpdate?(snap)
    }

    private func appendHistory(_ array: inout [Double], value: Double, limit: Int) {
        array.append(value)
        if array.count > limit {
            array.removeFirst(array.count - limit)
        }
    }

    private func scheduleTopProcessesIfNeeded() {
        guard isDashboardActive || activePopover == .cpu || activePopover == .ram || activePopover == .battery else {
            return
        }
        guard processTask == nil else { return }
        processTask = Task { [weak self] in
            let result = await SystemTelemetryReader.readTopProcessesAsync(limit: 8)
            guard !Task.isCancelled, let self else { return }
            self.cachedProcesses = result
            self.processTask = nil
            self.projectCachedProcesses()
        }
    }

    private func scheduleNettopIfNeeded() {
        guard activePopover == .network, netProcessTask == nil else { return }
        netProcessTask = Task { [weak self] in
            let current = await NetworkTelemetryService.sampleNetworkProcessCounters()
            guard !Task.isCancelled, let self else { return }
            let now = Date()
            if let prev = self.prevNetProcessCounters {
                let dt = max(0.2, now.timeIntervalSince(prev.time))
                var items: [NetworkProcessInfo] = []
                items.reserveCapacity(current.count)
                for (pid, cur) in current {
                    let prevEntry = prev.counters[pid]
                    let dIn = prevEntry.map { cur.bytesIn >= $0.bytesIn ? Double(cur.bytesIn - $0.bytesIn) / dt : 0 } ?? 0
                    let dOut = prevEntry.map { cur.bytesOut >= $0.bytesOut ? Double(cur.bytesOut - $0.bytesOut) / dt : 0 } ?? 0
                    let path = NetworkTelemetryService.executablePath(for: pid)
                    items.append(NetworkProcessInfo(
                        id: pid,
                        name: cur.name,
                        executablePath: path,
                        downloadBytesPerSecond: dIn,
                        uploadBytesPerSecond: dOut
                    ))
                }
                items.sort {
                    ($0.downloadBytesPerSecond + $0.uploadBytesPerSecond) > ($1.downloadBytesPerSecond + $1.uploadBytesPerSecond)
                }
                self.cachedNetProcesses = Array(items.prefix(8))
            } else {
                // First sample primes counters so rows appear immediately with app icons.
                var initial: [NetworkProcessInfo] = current.values.prefix(8).map { cur in
                    NetworkProcessInfo(
                        id: cur.pid,
                        name: cur.name,
                        executablePath: NetworkTelemetryService.executablePath(for: cur.pid),
                        downloadBytesPerSecond: 0,
                        uploadBytesPerSecond: 0
                    )
                }
                initial.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
                self.cachedNetProcesses = initial
            }
            self.prevNetProcessCounters = (current, now)
            self.netProcessTask = nil
            self.projectCachedProcesses()
        }
    }

    private func triggerPing() {
        guard pingTask == nil else { return }
        lastPingAt = Date()
        pingTask = Task { [weak self] in
            let rtt = await NetworkTelemetryService.pingHost("1.1.1.1")
            guard !Task.isCancelled, let self else { return }
            let up = rtt != nil
            self.isInternetUp = up
            if let rtt {
                self.latencyMs = rtt
                if let prev = self.lastLatencySampleMs {
                    let diff = abs(rtt - prev)
                    self.jitterMs = self.jitterMs.map { $0 + (diff - $0) / 4.0 } ?? diff
                }
                self.lastLatencySampleMs = rtt
            }
            self.connectivityHistory.append(up)
            if self.connectivityHistory.count > 75 {
                self.connectivityHistory.removeFirst(self.connectivityHistory.count - 75)
            }
            self.pingTask = nil
        }
    }

    private func fetchPublicIPIfNeeded(force: Bool) {
        let elapsed = Date().timeIntervalSince(lastPublicIPFetchAt)
        guard force || (publicIPv4 == nil && elapsed >= 15) || elapsed >= 300 else { return }
        guard publicIPTask == nil else { return }
        lastPublicIPFetchAt = Date()
        publicIPTask = Task { [weak self] in
            let info = await NetworkTelemetryService.fetchPublicIP()
            guard !Task.isCancelled, let self else { return }
            if let info {
                self.publicIPv4 = info.ip
                self.publicCountryCode = info.countryCode
            }
            self.publicIPTask = nil
        }
    }

    private func projectCachedProcesses() {
        let cur = snapshot
        let net = NetworkStats(
            interfaceName: cur.network.interfaceName,
            interfaceDisplayName: cur.network.interfaceDisplayName,
            isInterfaceUp: cur.network.isInterfaceUp,
            localIP: cur.network.localIP,
            macAddress: cur.network.macAddress,
            wifiSSID: cur.network.wifiSSID,
            needsLocationPermissionForSSID: cur.network.needsLocationPermissionForSSID,
            isInternetUp: isInternetUp,
            latencyMs: latencyMs,
            jitterMs: jitterMs,
            publicIPv4: publicIPv4,
            publicCountryCode: publicCountryCode,
            downloadBytesPerSecond: cur.network.downloadBytesPerSecond,
            uploadBytesPerSecond: cur.network.uploadBytesPerSecond,
            totalDownloadBytes: cur.network.totalDownloadBytes,
            totalUploadBytes: cur.network.totalUploadBytes,
            connectivityHistory: connectivityHistory
        )
        snapshot = StatsSnapshot(
            timestamp: cur.timestamp,
            cpu: cur.cpu,
            ram: cur.ram,
            disk: cur.disk,
            battery: cur.battery,
            network: net,
            topProcessesByCPU: cachedProcesses.byCPU,
            topProcessesByRAM: cachedProcesses.byRAM,
            topProcessesByNetwork: cachedNetProcesses
        )
    }
}
