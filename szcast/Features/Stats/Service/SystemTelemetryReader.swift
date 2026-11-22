import Foundation
import IOKit.ps
import Darwin

@MainActor
final class SystemTelemetryReader {
    static let shared = SystemTelemetryReader()

    // Previous CPU ticks for delta calculation
    private var prevCPUTicks: [processor_cpu_load_info] = []
    private var prevHostTicks: host_cpu_load_info?

    // Previous Network ticks for rate calculation
    private var prevNetworkBytes: (inBytes: UInt64, outBytes: UInt64, time: Date)?

    // MARK: - CPU

    func readCPU() -> CPUStats {
        let logicalCores = max(1, ProcessInfo.processInfo.processorCount)
        var physicalCores = logicalCores
        var size = MemoryLayout<Int32>.size
        var physical: Int32 = 0
        if sysctlbyname("hw.physicalcpu", &physical, &size, nil, 0) == 0 {
            physicalCores = Int(physical)
        }

        var numCPUs: natural_t = 0
        var cpuInfo: processor_info_array_t?
        var numCPUInfo: mach_msg_type_number_t = 0

        let result = host_processor_info(
            mach_host_self(),
            PROCESSOR_CPU_LOAD_INFO,
            &numCPUs,
            &cpuInfo,
            &numCPUInfo
        )

        var coreBreakdown: [CPUCoreUsage] = []
        var totalUsage: Double = 0
        var userPct: Double = 0
        var sysPct: Double = 0
        var idlePct: Double = 100

        if result == KERN_SUCCESS, let cpuInfo = cpuInfo {
            let cpuLoadInfo = cpuInfo.withMemoryRebound(
                to: processor_cpu_load_info.self,
                capacity: Int(numCPUs)
            ) { UnsafeBufferPointer(start: $0, count: Int(numCPUs)) }

            let currentTicks = Array(cpuLoadInfo)

            if !prevCPUTicks.isEmpty && prevCPUTicks.count == currentTicks.count {
                var totalUser: UInt64 = 0
                var totalSys: UInt64 = 0
                var totalIdle: UInt64 = 0
                var grandTotal: UInt64 = 0

                for i in 0..<currentTicks.count {
                    let cur = currentTicks[i]
                    let prev = prevCPUTicks[i]

                    let user = cur.cpu_ticks.0 >= prev.cpu_ticks.0 ? UInt64(cur.cpu_ticks.0 - prev.cpu_ticks.0) : 0
                    let sys = cur.cpu_ticks.1 >= prev.cpu_ticks.1 ? UInt64(cur.cpu_ticks.1 - prev.cpu_ticks.1) : 0
                    let idle = cur.cpu_ticks.2 >= prev.cpu_ticks.2 ? UInt64(cur.cpu_ticks.2 - prev.cpu_ticks.2) : 0
                    let nice = cur.cpu_ticks.3 >= prev.cpu_ticks.3 ? UInt64(cur.cpu_ticks.3 - prev.cpu_ticks.3) : 0

                    let coreActive = user + sys + nice
                    let coreTotal = coreActive + idle
                    let coreUsage = coreTotal > 0 ? (Double(coreActive) / Double(coreTotal) * 100.0) : 0.0

                    coreBreakdown.append(CPUCoreUsage(id: i, usagePercentage: min(100.0, max(0.0, coreUsage))))

                    totalUser += user
                    totalSys += sys
                    totalIdle += idle
                    grandTotal += coreTotal
                }

                if grandTotal > 0 {
                    userPct = Double(totalUser) / Double(grandTotal) * 100.0
                    sysPct = Double(totalSys) / Double(grandTotal) * 100.0
                    idlePct = Double(totalIdle) / Double(grandTotal) * 100.0
                    totalUsage = min(100.0, max(0.0, (Double(totalUser + totalSys) / Double(grandTotal) * 100.0)))
                }
            } else {
                // First pass fallback
                for i in 0..<Int(numCPUs) {
                    coreBreakdown.append(CPUCoreUsage(id: i, usagePercentage: 0.0))
                }
            }

            prevCPUTicks = currentTicks
            let sizeDealloc = vm_size_t(numCPUInfo) * vm_size_t(MemoryLayout<integer_t>.stride)
            vm_deallocate(mach_task_self_, vm_address_t(bitPattern: cpuInfo), sizeDealloc)
        }

        return CPUStats(
            totalUsage: totalUsage,
            userPercentage: userPct,
            systemPercentage: sysPct,
            idlePercentage: idlePct,
            physicalCores: physicalCores,
            logicalCores: logicalCores,
            coreBreakdown: coreBreakdown
        )
    }

    // MARK: - RAM

    func readRAM() -> RAMStats {
        var totalBytes: UInt64 = 0
        var size = MemoryLayout<UInt64>.size
        sysctlbyname("hw.memsize", &totalBytes, &size, nil, 0)
        if totalBytes == 0 { totalBytes = 17_179_869_184 }

        var vmStats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.size / MemoryLayout<integer_t>.size)

        let kerr = withUnsafeMutablePointer(to: &vmStats) { ptr in
            ptr.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }

        guard kerr == KERN_SUCCESS else {
            return RAMStats(
                usedBytes: totalBytes / 2,
                freeBytes: totalBytes / 2,
                activeBytes: totalBytes / 4,
                inactiveBytes: totalBytes / 4,
                wiredBytes: totalBytes / 4,
                compressedBytes: 0,
                totalBytes: totalBytes,
                swapUsedBytes: 0,
                swapTotalBytes: 0
            )
        }

        let pageSize = UInt64(getpagesize())
        let activeBytes = UInt64(vmStats.active_count) * pageSize
        let inactiveBytes = UInt64(vmStats.inactive_count) * pageSize
        let wiredBytes = UInt64(vmStats.wire_count) * pageSize
        let freeBytes = UInt64(vmStats.free_count) * pageSize
        let compressedBytes = UInt64(vmStats.compressor_page_count) * pageSize
        let usedBytes = activeBytes + wiredBytes + compressedBytes

        // Swap usage
        var swapUsage = xsw_usage()
        var swapSize = MemoryLayout<xsw_usage>.size
        var swapUsed: UInt64 = 0
        var swapTotal: UInt64 = 0
        if sysctlbyname("vm.swapusage", &swapUsage, &swapSize, nil, 0) == 0 {
            swapUsed = UInt64(swapUsage.xsu_used)
            swapTotal = UInt64(swapUsage.xsu_total)
        }

        return RAMStats(
            usedBytes: usedBytes,
            freeBytes: freeBytes,
            activeBytes: activeBytes,
            inactiveBytes: inactiveBytes,
            wiredBytes: wiredBytes,
            compressedBytes: compressedBytes,
            totalBytes: totalBytes,
            swapUsedBytes: swapUsed,
            swapTotalBytes: swapTotal
        )
    }

    // MARK: - Disk

    func readDisk() -> DiskStats {
        let keys: [URLResourceKey] = [
            .volumeNameKey,
            .volumeTotalCapacityKey,
            .volumeAvailableCapacityForImportantUsageKey,
            .volumeAvailableCapacityKey
        ]

        let urls = FileManager.default.mountedVolumeURLs(
            includingResourceValuesForKeys: keys,
            options: [.skipHiddenVolumes]
        ) ?? [URL(fileURLWithPath: "/")]

        var volumes: [DiskVolume] = []

        for url in urls {
            guard let values = try? url.resourceValues(forKeys: Set(keys)) else { continue }
            let name = values.volumeName ?? (url.path == "/" ? "Macintosh HD" : url.lastPathComponent)
            let total = Int64(values.volumeTotalCapacity ?? 0)
            guard total > 0 else { continue }

            let free = values.volumeAvailableCapacityForImportantUsage
                ?? Int64(values.volumeAvailableCapacity ?? 0)
            let used = max(0, total - free)

            volumes.append(DiskVolume(
                name: name,
                mountPath: url.path,
                totalBytes: total,
                freeBytes: free,
                usedBytes: used
            ))
        }

        return DiskStats(volumes: volumes)
    }

    // MARK: - Battery

    func readBattery() -> BatteryStats {
        guard let snapshot = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sources = IOPSCopyPowerSourcesList(snapshot)?.takeRetainedValue() as? [CFTypeRef],
              !sources.isEmpty else {
            return .empty
        }

        for source in sources {
            guard let desc = IOPSGetPowerSourceDescription(snapshot, source)?.takeUnretainedValue() as? [String: Any] else {
                continue
            }

            let isPresent = desc[kIOPSIsPresentKey] as? Bool ?? false
            guard isPresent else { continue }

            let curCap = desc[kIOPSCurrentCapacityKey] as? Int ?? 100
            let maxCap = desc[kIOPSMaxCapacityKey] as? Int ?? 100
            let percentage = maxCap > 0 ? Int((Double(curCap) / Double(maxCap)) * 100.0) : curCap
            let isCharging = desc[kIOPSIsChargingKey] as? Bool ?? false
            let powerState = desc[kIOPSPowerSourceStateKey] as? String
            let isAC = powerState == kIOPSACPowerValue

            var timeRemaining: Int? = nil
            if isCharging {
                if let toFull = desc[kIOPSTimeToFullChargeKey] as? Int, toFull > 0 {
                    timeRemaining = toFull
                }
            } else {
                if let toEmpty = desc[kIOPSTimeToEmptyKey] as? Int, toEmpty > 0 {
                    timeRemaining = toEmpty
                }
            }

            let health = desc[kIOPSBatteryHealthKey] as? String ?? "Normal"

            return BatteryStats(
                hasBattery: true,
                percentage: min(100, max(0, percentage)),
                isCharging: isCharging,
                isACConnected: isAC,
                timeRemainingMinutes: timeRemaining,
                cycleCount: nil,
                health: health,
                temperature: nil
            )
        }

        return .empty
    }

    // MARK: - Network

    func readNetwork() -> NetworkStats {
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0, let firstAddr = ifaddr else {
            return .empty
        }
        defer { freeifaddrs(ifaddr) }

        var totalIn: UInt64 = 0
        var totalOut: UInt64 = 0
        var primaryName = "en0"
        var localIP = "127.0.0.1"

        var ptr: UnsafeMutablePointer<ifaddrs>? = firstAddr
        while let current = ptr {
            let name = String(cString: current.pointee.ifa_name)
            let flags = Int32(current.pointee.ifa_flags)
            let isUp = (flags & IFF_UP) == IFF_UP
            let isRunning = (flags & IFF_RUNNING) == IFF_RUNNING
            let isLoopback = (flags & IFF_LOOPBACK) == IFF_LOOPBACK

            if isUp && isRunning && !isLoopback {
                let family = current.pointee.ifa_addr.pointee.sa_family
                if family == UInt8(AF_LINK) {
                    if let data = current.pointee.ifa_data {
                        let networkData = data.assumingMemoryBound(to: if_data.self)
                        totalIn += UInt64(networkData.pointee.ifi_ibytes)
                        totalOut += UInt64(networkData.pointee.ifi_obytes)
                        if name.hasPrefix("en") { primaryName = name }
                    }
                } else if family == UInt8(AF_INET), let addr = current.pointee.ifa_addr {
                    var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                    if getnameinfo(addr, socklen_t(addr.pointee.sa_len), &host, socklen_t(host.count), nil, 0, NI_NUMERICHOST) == 0 {
                        let ip = String(cString: host)
                        if !ip.isEmpty && ip != "127.0.0.1" {
                            localIP = ip
                        }
                    }
                }
            }
            ptr = current.pointee.ifa_next
        }

        let now = Date()
        var downRate: Double = 0
        var upRate: Double = 0

        if let prev = prevNetworkBytes {
            let deltaSeconds = max(0.1, now.timeIntervalSince(prev.time))
            if totalIn >= prev.inBytes {
                downRate = Double(totalIn - prev.inBytes) / deltaSeconds
            }
            if totalOut >= prev.outBytes {
                upRate = Double(totalOut - prev.outBytes) / deltaSeconds
            }
        }

        prevNetworkBytes = (inBytes: totalIn, outBytes: totalOut, time: now)

        return NetworkStats(
            interfaceName: primaryName,
            localIP: localIP,
            downloadBytesPerSecond: downRate,
            uploadBytesPerSecond: upRate,
            totalDownloadBytes: totalIn,
            totalUploadBytes: totalOut
        )
    }

    // MARK: - Top Processes

    func readTopProcesses(limit: Int = 5) -> (byCPU: [SystemProcessInfo], byRAM: [SystemProcessInfo]) {
        guard limit > 0 else { return ([], []) }

        let task = Process()
        task.launchPath = "/bin/ps"
        // ps -A -c -o pid=,pcpu=,rss=,comm= -r
        task.arguments = ["-A", "-c", "-o", "pid=,pcpu=,rss=,comm=", "-r"]

        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = Pipe()

        do {
            try task.run()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            task.waitUntilExit()

            guard let output = String(data: data, encoding: .utf8) else {
                return ([], [])
            }

            var entries: [SystemProcessInfo] = []
            let lines = output.components(separatedBy: "\n")

            for line in lines {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                guard !trimmed.isEmpty else { continue }
                let parts = trimmed.split(maxSplits: 3, whereSeparator: \.isWhitespace).map(String.init)
                guard parts.count >= 4,
                      let pid = Int32(parts[0]),
                      let cpu = Double(parts[1]),
                      let rssKB = UInt64(parts[2]) else { continue }

                let name = parts[3]
                let memoryBytes = rssKB * 1024

                entries.append(SystemProcessInfo(
                    id: pid,
                    name: name,
                    cpuPercentage: cpu,
                    memoryBytes: memoryBytes
                ))
            }

            let byCPU = Array(entries.sorted { $0.cpuPercentage > $1.cpuPercentage }.prefix(limit))
            let byRAM = Array(entries.sorted { $0.memoryBytes > $1.memoryBytes }.prefix(limit))

            return (byCPU, byRAM)
        } catch {
            return ([], [])
        }
    }

    // MARK: - Full Snapshot

    func captureSnapshot(processLimit: Int = 5) -> StatsSnapshot {
        let cpu = readCPU()
        let ram = readRAM()
        let disk = readDisk()
        let battery = readBattery()
        let network = readNetwork()
        let processes = readTopProcesses(limit: processLimit)

        return StatsSnapshot(
            timestamp: Date(),
            cpu: cpu,
            ram: ram,
            disk: disk,
            battery: battery,
            network: network,
            topProcessesByCPU: processes.byCPU,
            topProcessesByRAM: processes.byRAM
        )
    }
}
