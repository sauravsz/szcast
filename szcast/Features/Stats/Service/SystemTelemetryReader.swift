import Foundation
import IOKit
import IOKit.ps
import CoreWLAN
import CoreLocation
import SystemConfiguration
import Darwin

@MainActor
final class SystemTelemetryReader {
    static let shared = SystemTelemetryReader()

    private var prevCPUTicks: [processor_cpu_load_info] = []
    private var prevNetworkBytes: (inBytes: UInt64, outBytes: UInt64, interface: String, time: Date)?
    private var prevDiskBytes: (readBytes: UInt64, writeBytes: UInt64, time: Date)?
    private lazy var frequencyReader = AppleSiliconFrequencyReader()
    private lazy var locationManager = CLLocationManager()
    private lazy var coreTopology: (efficiency: Int, performance: Int) = Self.readCoreTopology()
    private lazy var bootTime: Date? = Self.readBootTime()
    private lazy var interfaceDisplayNames: [String: String] = Self.readInterfaceDisplayNames()
    private lazy var dynamicStore: SCDynamicStore? = SCDynamicStoreCreate(
        nil, "com.sauravsz.szcast.stats" as CFString, nil, nil)

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

        let efficiencyCount = coreTopology.efficiency
        let performanceCount = coreTopology.performance
        let hasSplitClusters = efficiencyCount > 0 && performanceCount > 0

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
                    let isEff = hasSplitClusters && i < efficiencyCount

                    coreBreakdown.append(CPUCoreUsage(
                        id: i,
                        usagePercentage: min(100.0, max(0.0, coreUsage)),
                        isEfficiency: isEff
                    ))

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
                for i in 0..<Int(numCPUs) {
                    let isEff = hasSplitClusters && i < efficiencyCount
                    coreBreakdown.append(CPUCoreUsage(id: i, usagePercentage: 0.0, isEfficiency: isEff))
                }
            }

            prevCPUTicks = currentTicks
            let sizeDealloc = vm_size_t(numCPUInfo) * vm_size_t(MemoryLayout<integer_t>.stride)
            vm_deallocate(mach_task_self_, vm_address_t(bitPattern: cpuInfo), sizeDealloc)
        }

        let efficiencyUsage: Double?
        let performanceUsage: Double?
        if hasSplitClusters, coreBreakdown.count >= efficiencyCount + performanceCount {
            let effCores = coreBreakdown.prefix(efficiencyCount)
            let perfCores = coreBreakdown.dropFirst(efficiencyCount).prefix(performanceCount)
            efficiencyUsage = effCores.map(\.usagePercentage).reduce(0, +) / Double(efficiencyCount)
            performanceUsage = perfCores.map(\.usagePercentage).reduce(0, +) / Double(performanceCount)
        } else {
            efficiencyUsage = nil
            performanceUsage = nil
        }

        var loads = [Double](repeating: 0, count: 3)
        getloadavg(&loads, 3)

        let uptime = bootTime.map { max(0, Date().timeIntervalSince($0)) } ?? ProcessInfo.processInfo.systemUptime
        let freqs = frequencyReader.sample(
            efficiencyCores: efficiencyCount,
            performanceCores: performanceCount
        )

        return CPUStats(
            totalUsage: totalUsage,
            userPercentage: userPct,
            systemPercentage: sysPct,
            idlePercentage: idlePct,
            physicalCores: physicalCores,
            logicalCores: logicalCores,
            efficiencyUsage: efficiencyUsage,
            performanceUsage: performanceUsage,
            uptimeSeconds: uptime,
            loadAverage1m: loads[0],
            loadAverage5m: loads[1],
            loadAverage15m: loads[2],
            allCoresFrequencyMHz: freqs.allMHz,
            efficiencyFrequencyMHz: freqs.efficiencyMHz,
            performanceFrequencyMHz: freqs.performanceMHz,
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
        var count = mach_msg_type_number_t(
            MemoryLayout<vm_statistics64_data_t>.stride / MemoryLayout<integer_t>.stride
        )

        let kerr = withUnsafeMutablePointer(to: &vmStats) { ptr in
            ptr.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }

        var pressureRaw: Int32 = 1
        var pressureSize = MemoryLayout<Int32>.size
        sysctlbyname("kern.memorystatus_vm_pressure_level", &pressureRaw, &pressureSize, nil, 0)
        let pressureLevel = MemoryPressureLevel(rawValue: Int(pressureRaw)) ?? .normal

        var memStatusFreePct: Int32 = 50
        var memStatusSize = MemoryLayout<Int32>.size
        let hasMemStatus = sysctlbyname("kern.memorystatus_level", &memStatusFreePct, &memStatusSize, nil, 0) == 0

        guard kerr == KERN_SUCCESS else {
            let fallbackPressure = hasMemStatus ? max(0, min(100, 100 - Int(memStatusFreePct))) : 50
            return RAMStats(
                usedBytes: totalBytes / 2,
                freeBytes: totalBytes / 2,
                appBytes: totalBytes / 4,
                activeBytes: totalBytes / 4,
                inactiveBytes: totalBytes / 4,
                wiredBytes: totalBytes / 4,
                compressedBytes: 0,
                totalBytes: totalBytes,
                swapUsedBytes: 0,
                swapTotalBytes: 0,
                pressurePercentage: fallbackPressure,
                pressureLevel: pressureLevel
            )
        }

        let pageSize = UInt64(getpagesize())
        let appPages = vmStats.internal_page_count > vmStats.purgeable_count
            ? UInt64(vmStats.internal_page_count - vmStats.purgeable_count)
            : 0
        let appBytes = appPages * pageSize
        let activeBytes = UInt64(vmStats.active_count) * pageSize
        let inactiveBytes = UInt64(vmStats.inactive_count) * pageSize
        let wiredBytes = UInt64(vmStats.wire_count) * pageSize
        let compressedBytes = UInt64(vmStats.compressor_page_count) * pageSize
        let usedBytes = min(totalBytes, appBytes + wiredBytes + compressedBytes)
        let freeBytes = totalBytes > usedBytes ? totalBytes - usedBytes : 0

        var swapUsage = xsw_usage()
        var swapSize = MemoryLayout<xsw_usage>.size
        var swapUsed: UInt64 = 0
        var swapTotal: UInt64 = 0
        if sysctlbyname("vm.swapusage", &swapUsage, &swapSize, nil, 0) == 0 {
            swapUsed = UInt64(swapUsage.xsu_used)
            swapTotal = UInt64(swapUsage.xsu_total)
        }

        let pressurePct: Int
        if hasMemStatus {
            pressurePct = max(0, min(100, 100 - Int(memStatusFreePct)))
        } else {
            pressurePct = max(0, min(100, Int((Double(usedBytes) / Double(totalBytes) * 100.0).rounded())))
        }

        return RAMStats(
            usedBytes: usedBytes,
            freeBytes: freeBytes,
            appBytes: appBytes,
            activeBytes: activeBytes,
            inactiveBytes: inactiveBytes,
            wiredBytes: wiredBytes,
            compressedBytes: compressedBytes,
            totalBytes: totalBytes,
            swapUsedBytes: swapUsed,
            swapTotalBytes: swapTotal,
            pressurePercentage: pressurePct,
            pressureLevel: pressureLevel
        )
    }

    // MARK: - Disk

    func readDisk() -> DiskStats {
        let keys: [URLResourceKey] = [
            .volumeNameKey,
            .volumeTotalCapacityKey,
            .volumeAvailableCapacityForImportantUsageKey,
            .volumeAvailableCapacityKey,
            .volumeIsRemovableKey,
            .volumeLocalizedFormatDescriptionKey
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
                fileSystemType: values.volumeLocalizedFormatDescription,
                isRemovable: values.volumeIsRemovable ?? false,
                totalBytes: total,
                freeBytes: free,
                usedBytes: used
            ))
        }

        let io = readDiskIO()
        return DiskStats(
            volumes: volumes,
            readBytesPerSecond: io.readPerSec,
            writeBytesPerSecond: io.writePerSec,
            totalReadBytes: io.totalRead,
            totalWriteBytes: io.totalWrite
        )
    }

    private func readDiskIO() -> (readPerSec: Double, writePerSec: Double, totalRead: UInt64, totalWrite: UInt64) {
        var totalRead: UInt64 = 0
        var totalWrite: UInt64 = 0

        var iterator: io_iterator_t = 0
        if IOServiceGetMatchingServices(
            kIOMainPortDefault,
            IOServiceMatching("IOBlockStorageDriver"),
            &iterator
        ) == KERN_SUCCESS {
            defer { IOObjectRelease(iterator) }
            while case let service = IOIteratorNext(iterator), service != 0 {
                defer { IOObjectRelease(service) }
                guard let stats = IORegistryEntryCreateCFProperty(
                    service, "Statistics" as CFString, kCFAllocatorDefault, 0
                )?.takeRetainedValue() as? [String: Any] else { continue }
                if let r = stats["Bytes (Read)"] as? UInt64 { totalRead += r }
                else if let r = stats["Bytes (Read)"] as? Int64, r > 0 { totalRead += UInt64(r) }
                if let w = stats["Bytes (Write)"] as? UInt64 { totalWrite += w }
                else if let w = stats["Bytes (Write)"] as? Int64, w > 0 { totalWrite += UInt64(w) }
            }
        }

        let now = Date()
        var readRate: Double = 0
        var writeRate: Double = 0
        if let prev = prevDiskBytes {
            let dt = max(0.1, now.timeIntervalSince(prev.time))
            if totalRead >= prev.readBytes {
                readRate = Double(totalRead - prev.readBytes) / dt
            }
            if totalWrite >= prev.writeBytes {
                writeRate = Double(totalWrite - prev.writeBytes) / dt
            }
        }
        prevDiskBytes = (totalRead, totalWrite, now)
        return (readRate, writeRate, totalRead, totalWrite)
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
            let smart = readSmartBatteryDetails()

            return BatteryStats(
                hasBattery: true,
                percentage: min(100, max(0, percentage)),
                isCharging: isCharging,
                isACConnected: isAC,
                timeRemainingMinutes: timeRemaining,
                cycleCount: smart.cycleCount,
                health: health,
                healthPercentage: smart.healthPct,
                currentCapacityMAh: smart.currentMAh,
                maxCapacityMAh: smart.maxMAh,
                designCapacityMAh: smart.designMAh,
                voltageMillivolts: smart.voltageMV,
                amperageMilliamps: smart.amperageMA,
                powerWatts: smart.powerWatts,
                adapterWatts: smart.adapterWatts,
                temperature: smart.temperatureC
            )
        }

        return .empty
    }

    private struct SmartBatteryDetails {
        var cycleCount: Int?
        var healthPct: Int?
        var currentMAh: Int?
        var maxMAh: Int?
        var designMAh: Int?
        var voltageMV: Int?
        var amperageMA: Int?
        var powerWatts: Double?
        var adapterWatts: Int?
        var temperatureC: Double?
    }

    private func readSmartBatteryDetails() -> SmartBatteryDetails {
        var details = SmartBatteryDetails()
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSmartBattery"))
        guard service != 0 else { return details }
        defer { IOObjectRelease(service) }

        var props: Unmanaged<CFMutableDictionary>?
        guard IORegistryEntryCreateCFProperties(service, &props, kCFAllocatorDefault, 0) == KERN_SUCCESS,
              let dict = props?.takeRetainedValue() as? [String: Any] else {
            return details
        }

        details.cycleCount = dict["CycleCount"] as? Int
        let batteryData = dict["BatteryData"] as? [String: Any]
        details.designMAh = (dict["DesignCapacity"] as? Int) ?? (batteryData?["DesignCapacity"] as? Int)
        details.maxMAh = (dict["AppleRawMaxCapacity"] as? Int)
            ?? (batteryData?["AppleRawMaxCapacity"] as? Int)
            ?? (batteryData?["FullChargeCapacity"] as? Int)
        details.currentMAh = (dict["AppleRawCurrentCapacity"] as? Int)
            ?? (batteryData?["AppleRawCurrentCapacity"] as? Int)
            ?? (batteryData?["RemainingCapacity"] as? Int)

        if let maxCap = details.maxMAh, let designCap = details.designMAh, designCap > 0 {
            details.healthPct = min(100, Int((Double(maxCap) / Double(designCap) * 100.0).rounded()))
        }

        if let voltage = dict["Voltage"] as? Int {
            details.voltageMV = voltage
        }
        if let ampNum = dict["InstantAmperage"] as? Int64 ?? dict["Amperage"] as? Int64 {
            details.amperageMA = Int(ampNum)
        } else if let amp = dict["Amperage"] as? Int {
            details.amperageMA = amp
        }
        if let v = details.voltageMV, let a = details.amperageMA {
            details.powerWatts = (Double(v) * Double(a)) / 1_000_000.0
        }
        if let adapter = dict["AdapterDetails"] as? [String: Any], let watts = adapter["Watts"] as? Int, watts > 0 {
            details.adapterWatts = watts
        }
        if let tempRaw = dict["Temperature"] as? Double, tempRaw > 0 {
            let celsius = tempRaw > 2000 ? (tempRaw / 100.0) : (tempRaw > 200 ? tempRaw / 10.0 - 273.15 : tempRaw / 100.0)
            if celsius > 0 && celsius < 120 {
                details.temperatureC = celsius
            }
        }
        return details
    }

    // MARK: - Network

    func readNetwork(
        isInternetUp: Bool = false,
        latencyMs: Double? = nil,
        jitterMs: Double? = nil,
        publicIPv4: String? = nil,
        publicCountryCode: String? = nil,
        connectivityHistory: [Bool] = []
    ) -> NetworkStats {
        let primaryHint = readPrimaryInterfaceName()
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0, let firstAddr = ifaddr else {
            return .empty
        }
        defer { freeifaddrs(ifaddr) }

        struct IfaceAccum {
            var isUp = false
            var inBytes: UInt64 = 0
            var outBytes: UInt64 = 0
            var mac = ""
            var ipv4: String?
        }

        var interfaces: [String: IfaceAccum] = [:]
        var ptr: UnsafeMutablePointer<ifaddrs>? = firstAddr

        while let current = ptr {
            let name = String(cString: current.pointee.ifa_name)
            let flags = Int32(current.pointee.ifa_flags)
            let isUp = (flags & IFF_UP) == IFF_UP
            let isRunning = (flags & IFF_RUNNING) == IFF_RUNNING
            let isLoopback = (flags & IFF_LOOPBACK) == IFF_LOOPBACK

            if !isLoopback, let addr = current.pointee.ifa_addr {
                var accum = interfaces[name] ?? IfaceAccum()
                if isUp && isRunning { accum.isUp = true }
                let family = addr.pointee.sa_family
                if family == UInt8(AF_LINK) {
                    if let data = current.pointee.ifa_data {
                        let networkData = data.assumingMemoryBound(to: if_data.self)
                        accum.inBytes = UInt64(networkData.pointee.ifi_ibytes)
                        accum.outBytes = UInt64(networkData.pointee.ifi_obytes)
                    }
                    accum.mac = extractMACAddress(addr) ?? accum.mac
                } else if family == UInt8(AF_INET) {
                    var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                    if getnameinfo(
                        addr, socklen_t(addr.pointee.sa_len),
                        &host, socklen_t(host.count), nil, 0, NI_NUMERICHOST
                    ) == 0 {
                        let ip = Self.decodeCString(host)
                        if !ip.isEmpty && ip != "127.0.0.1" {
                            accum.ipv4 = ip
                        }
                    }
                }
                interfaces[name] = accum
            }
            ptr = current.pointee.ifa_next
        }

        let chosenName = primaryHint
            ?? interfaces.first(where: { $0.key.hasPrefix("en") && $0.value.isUp && $0.value.ipv4 != nil })?.key
            ?? interfaces.first(where: { $0.key.hasPrefix("en") && $0.value.isUp })?.key
            ?? "en0"
        let chosen = interfaces[chosenName] ?? IfaceAccum()

        let now = Date()
        var downRate: Double = 0
        var upRate: Double = 0

        if let prev = prevNetworkBytes, prev.interface == chosenName {
            let deltaSeconds = max(0.1, now.timeIntervalSince(prev.time))
            if chosen.inBytes >= prev.inBytes {
                downRate = Double(chosen.inBytes - prev.inBytes) / deltaSeconds
            }
            if chosen.outBytes >= prev.outBytes {
                upRate = Double(chosen.outBytes - prev.outBytes) / deltaSeconds
            }
        }
        prevNetworkBytes = (chosen.inBytes, chosen.outBytes, chosenName, now)

        let friendly = interfaceDisplayNames[chosenName]
        let displayName = friendly.map { "\($0) (\(chosenName))" } ?? chosenName

        let wifiIface = CWWiFiClient.shared().interface(withName: chosenName)
        let isWiFi = wifiIface != nil && (friendly?.localizedCaseInsensitiveContains("wi-fi") ?? (chosenName == "en0"))
        let ssid = wifiIface?.ssid()
        let mac = wifiIface?.hardwareAddress() ?? chosen.mac
        let authStatus = locationManager.authorizationStatus
        let needsLocation = isWiFi && ssid == nil && authStatus != .authorizedAlways && authStatus != .authorized

        return NetworkStats(
            interfaceName: chosenName,
            interfaceDisplayName: displayName,
            isInterfaceUp: chosen.isUp,
            localIP: chosen.ipv4 ?? "127.0.0.1",
            macAddress: mac,
            wifiSSID: ssid,
            needsLocationPermissionForSSID: needsLocation,
            isInternetUp: isInternetUp,
            latencyMs: latencyMs,
            jitterMs: jitterMs,
            publicIPv4: publicIPv4,
            publicCountryCode: publicCountryCode,
            downloadBytesPerSecond: downRate,
            uploadBytesPerSecond: upRate,
            totalDownloadBytes: chosen.inBytes,
            totalUploadBytes: chosen.outBytes,
            connectivityHistory: connectivityHistory
        )
    }

    // MARK: - Top Processes (Sync for tests, Async off-main for live UI)

    func readTopProcesses(limit: Int = 5) -> (byCPU: [SystemProcessInfo], byRAM: [SystemProcessInfo]) {
        guard limit > 0 else { return ([], []) }

        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/ps")
        task.arguments = ["-A", "-c", "-o", "pid=,pcpu=,rss=,comm=", "-r"]

        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = Pipe()

        do {
            let exit = try task.runObservingExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            exit.wait()

            guard let output = String(data: data, encoding: .utf8) else {
                return ([], [])
            }
            return Self.parseTopProcesses(output: output, limit: limit)
        } catch {
            return ([], [])
        }
    }

    nonisolated static func readTopProcessesAsync(
        limit: Int = 8
    ) async -> (byCPU: [SystemProcessInfo], byRAM: [SystemProcessInfo]) {
        guard limit > 0 else { return ([], []) }
        return await Task.detached(priority: .utility) {
            let task = Process()
            task.executableURL = URL(fileURLWithPath: "/bin/ps")
            task.arguments = ["-A", "-c", "-o", "pid=,pcpu=,rss=,comm=", "-r"]

            let pipe = Pipe()
            task.standardOutput = pipe
            task.standardError = Pipe()

            do {
                let exit = try task.runObservingExit()
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                exit.wait()
                guard let output = String(data: data, encoding: .utf8) else { return ([], []) }
                return parseTopProcesses(output: output, limit: limit)
            } catch {
                return ([], [])
            }
        }.value
    }

    nonisolated private static func parseTopProcesses(
        output: String,
        limit: Int
    ) -> (byCPU: [SystemProcessInfo], byRAM: [SystemProcessInfo]) {
        var entries: [SystemProcessInfo] = []
        for line in output.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { continue }
            let parts = trimmed.split(maxSplits: 3, whereSeparator: \.isWhitespace).map(String.init)
            guard parts.count >= 4,
                  let pid = Int32(parts[0]),
                  let cpu = Double(parts[1]),
                  let rssKB = UInt64(parts[2]) else { continue }

            entries.append(SystemProcessInfo(
                id: pid,
                name: parts[3],
                executablePath: NetworkTelemetryService.executablePath(for: pid),
                cpuPercentage: cpu,
                memoryBytes: rssKB * 1024
            ))
        }

        let byCPU = Array(entries.sorted { $0.cpuPercentage > $1.cpuPercentage }.prefix(limit))
        let byRAM = Array(entries.sorted { $0.memoryBytes > $1.memoryBytes }.prefix(limit))
        return (byCPU, byRAM)
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
            topProcessesByRAM: processes.byRAM,
            topProcessesByNetwork: []
        )
    }

    // MARK: - Helpers

    private func readPrimaryInterfaceName() -> String? {
        guard let dynamicStore,
              let dict = SCDynamicStoreCopyValue(dynamicStore, "State:/Network/Global/IPv4" as CFString) as? [String: Any]
        else { return nil }
        return dict["PrimaryInterface"] as? String
    }

    private func extractMACAddress(_ sa: UnsafeMutablePointer<sockaddr>) -> String? {
        sa.withMemoryRebound(to: sockaddr_dl.self, capacity: 1) { sdlPtr in
            let nameLen = Int(sdlPtr.pointee.sdl_nlen)
            let addrLen = Int(sdlPtr.pointee.sdl_alen)
            guard addrLen == 6 else { return nil }
            return withUnsafePointer(to: &sdlPtr.pointee.sdl_data) { dataPtr in
                let raw = UnsafeRawPointer(dataPtr).assumingMemoryBound(to: UInt8.self)
                let bytes = (0..<addrLen).map { String(format: "%02x", raw[nameLen + $0]) }
                return bytes.joined(separator: ":")
            }
        }
    }

    private static func decodeCString(_ buffer: [CChar]) -> String {
        let bytes = buffer.prefix(while: { $0 != 0 }).map { UInt8(bitPattern: $0) }
        return String(decoding: bytes, as: UTF8.self)
    }

    private static func readCoreTopology() -> (efficiency: Int, performance: Int) {
        var levels: Int32 = 0
        var size = MemoryLayout<Int32>.size
        guard sysctlbyname("hw.nperflevels", &levels, &size, nil, 0) == 0, levels >= 2 else {
            return (0, 0)
        }
        var efficiency = 0
        var performance = 0
        for level in 0..<levels {
            var nameBuffer = [CChar](repeating: 0, count: 64)
            var nameLen = nameBuffer.count
            sysctlbyname("hw.perflevel\(level).name", &nameBuffer, &nameLen, nil, 0)
            let name = decodeCString(nameBuffer).lowercased()
            var count: Int32 = 0
            var countSize = MemoryLayout<Int32>.size
            sysctlbyname("hw.perflevel\(level).logicalcpu", &count, &countSize, nil, 0)
            if name.contains("efficiency") { efficiency += Int(count) }
            else if name.contains("performance") { performance += Int(count) }
        }
        return (efficiency, performance)
    }

    private static func readBootTime() -> Date? {
        var boottime = timeval()
        var size = MemoryLayout<timeval>.stride
        guard sysctlbyname("kern.boottime", &boottime, &size, nil, 0) == 0, boottime.tv_sec > 0 else {
            return nil
        }
        return Date(timeIntervalSince1970: Double(boottime.tv_sec) + Double(boottime.tv_usec) / 1_000_000.0)
    }

    private static func readInterfaceDisplayNames() -> [String: String] {
        guard let list = SCNetworkInterfaceCopyAll() as? [SCNetworkInterface] else { return [:] }
        var map: [String: String] = [:]
        for iface in list {
            if let bsd = SCNetworkInterfaceGetBSDName(iface) as String?,
               let localized = SCNetworkInterfaceGetLocalizedDisplayName(iface) as String? {
                map[bsd] = localized
            }
        }
        return map
    }
}
