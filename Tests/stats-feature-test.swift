import Foundation

@main
@MainActor
struct StatsFeatureTests {
    static var failures = 0
    static var passes = 0

    static func expect(_ condition: Bool, _ message: String) {
        if condition {
            passes += 1
        } else {
            failures += 1
            print("FAIL: \(message)")
        }
    }

    static func main() {
        print("Testing Stats feature suite...")

        let reader = SystemTelemetryReader.shared

        // 1. CPU Telemetry (sample twice so delta ticks & IOReport frequencies populate)
        _ = reader.readCPU()
        Thread.sleep(forTimeInterval: 0.1)
        let cpu = reader.readCPU()
        expect(cpu.logicalCores >= 1, "Logical CPU core count >= 1 (got \(cpu.logicalCores))")
        expect(cpu.physicalCores >= 1, "Physical CPU core count >= 1 (got \(cpu.physicalCores))")
        expect(cpu.totalUsage >= 0 && cpu.totalUsage <= 100, "CPU usage within 0..100% (got \(cpu.totalUsage))")
        expect(cpu.uptimeSeconds > 0, "System uptime > 0 (got \(cpu.uptimeSeconds)s)")
        expect(cpu.loadAverage1m >= 0 && cpu.loadAverage5m >= 0 && cpu.loadAverage15m >= 0, "Load average non-negative")

        // 2. RAM Telemetry (Activity Monitor / exelban stats formula: app + wired + compressed)
        let ram = reader.readRAM()
        expect(ram.totalBytes > 0, "Total RAM > 0 (got \(ram.totalGB) GB)")
        expect(ram.usedBytes > 0, "Used RAM > 0 (got \(ram.usedGB) GB)")
        expect(ram.usagePercentage > 0 && ram.usagePercentage <= 100, "RAM usage % valid (got \(ram.usagePercentage)%)")
        expect(ram.appBytes + ram.wiredBytes + ram.compressedBytes == ram.usedBytes || ram.usedBytes == ram.totalBytes, "RAM used matches app + wired + compressed")
        expect(ram.pressurePercentage >= 0 && ram.pressurePercentage <= 100, "Memory pressure % valid (got \(ram.pressurePercentage)%)")

        // 3. Disk Telemetry
        let disk = reader.readDisk()
        expect(!disk.volumes.isEmpty, "Found at least 1 mounted disk volume")
        if let root = disk.rootVolume {
            expect(root.totalBytes > 0, "Root volume total capacity > 0 (got \(root.totalGB) GB)")
            expect(root.freeBytes > 0, "Root volume free space > 0 (got \(root.freeGB) GB)")
            expect(root.usagePercentage >= 0 && root.usagePercentage <= 100, "Root volume usage % valid")
        } else {
            expect(false, "Root volume found")
        }

        // 4. Battery Telemetry
        let battery = reader.readBattery()
        if battery.hasBattery {
            expect(battery.percentage >= 0 && battery.percentage <= 100, "Battery percentage 0..100 (got \(battery.percentage)%)")
        } else {
            expect(battery.isACConnected, "Desktop Mac is AC connected")
        }

        // 5. Network Telemetry
        let network = reader.readNetwork()
        expect(!network.interfaceName.isEmpty, "Primary interface name not empty (got \(network.interfaceName))")
        expect(!network.interfaceDisplayName.isEmpty, "Interface display name not empty")
        expect(!network.localIP.isEmpty, "Local IP detected (got \(network.localIP))")

        // 6. Top Processes
        let processes = reader.readTopProcesses(limit: 8)
        expect(!processes.byCPU.isEmpty, "Captured top processes by CPU (got \(processes.byCPU.count))")
        expect(!processes.byRAM.isEmpty, "Captured top processes by RAM (got \(processes.byRAM.count))")
        if let topProc = processes.byCPU.first {
            expect(topProc.id > 0, "Top CPU process has valid PID: \(topProc.id) (\(topProc.name))")
        }
        let zeroProcesses = reader.readTopProcesses(limit: 0)
        expect(zeroProcesses.byCPU.isEmpty && zeroProcesses.byRAM.isEmpty, "Top processes with limit 0 returns empty without spawning /bin/ps")

        // 7. Pure Formatting & Nettop Parsing
        expect(StatsFormatting.bytes(6 * 1_073_741_824) == "6 GB", "Exact GB trims .00")
        expect(StatsFormatting.speed(1024) == "1 KB/s", "Formats KB/s cleanly")
        expect(StatsFormatting.uptime(12 * 3600 + 12 * 60) == "12 hours, 12 minutes", "Formats uptime cleanly")
        expect(StatsFormatting.flag(countryCode: "IN") != nil, "Converts ISO country code to regional flag")
        let sampleNettop = ",bytes_in,bytes_out,\ncom.apple.Safari.1234,4096,1024,\nagy.99,15000,500,\n"
        let parsedNet = NetworkTelemetryService.parseNettopOutput(sampleNettop)
        expect(parsedNet[1234]?.name == "com.apple.Safari" && parsedNet[1234]?.bytesIn == 4096, "Parses dotted nettop process names")
        expect(parsedNet[99]?.bytesOut == 500, "Parses simple nettop process entries")

        expect(SystemTelemetryReader.counterDelta(current: 5000, previous: 2000) == 3000, "Normal counter delta")
        let wrapDelta = SystemTelemetryReader.counterDelta(current: 1024, previous: UInt64(UInt32.max) - 1023)
        expect(wrapDelta == 2048, "32-bit interface counter rollover delta")
        expect(SystemTelemetryReader.counterDelta(current: 500, previous: UInt64(UInt32.max) + 500) == 0, "Counter reset returns zero")

        // 8. Full Snapshot capture & hardware sanity checks
        let snapshot = reader.captureSnapshot(processLimit: 5)
        expect(snapshot.cpu.logicalCores >= 1, "Snapshot carries valid CPU stats")
        expect(snapshot.ram.totalBytes > 0, "Snapshot carries valid RAM stats")
        expect(!snapshot.disk.volumes.isEmpty, "Snapshot carries disk volumes")
        expect(
            snapshot.disk.volumes.allSatisfy { $0.totalBytes > 0 && $0.freeBytes > 0 && $0.usedBytes <= $0.totalBytes },
            "All mounted disk volumes report valid non-zero free space"
        )
        if snapshot.battery.hasBattery {
            expect((snapshot.battery.designCapacityMAh ?? 0) > 0, "Battery design capacity populated")
            expect((snapshot.battery.maxCapacityMAh ?? 0) > 0, "Battery max capacity populated")
            expect((1...100).contains(snapshot.battery.healthPercentage ?? 0), "Battery health percentage in 1..100")
            expect((snapshot.battery.voltageMillivolts ?? 0) > 0, "Battery voltage populated")
            if let temp = snapshot.battery.temperature {
                expect(temp > 0 && temp < 120, "Battery temperature in realistic Celsius range (got \(temp))")
            }
        }
        print(
            "Live Battery: cur=\(snapshot.battery.currentCapacityMAh ?? 0) max=\(snapshot.battery.maxCapacityMAh ?? 0) "
                + "design=\(snapshot.battery.designCapacityMAh ?? 0) temp=\(snapshot.battery.temperature ?? -1) "
                + "power=\(snapshot.battery.powerWatts ?? -1)"
        )
        print(
            "Live Network (\(snapshot.network.interfaceName)): downTotal=\(snapshot.network.totalDownloadBytes) "
                + "upTotal=\(snapshot.network.totalUploadBytes)"
        )
        for v in snapshot.disk.volumes {
            print("Live Disk (\(v.name)): freeGB=\(String(format: "%.2f", v.freeGB)) / totalGB=\(String(format: "%.2f", v.totalGB))")
        }

        if failures > 0 {
            print("FAILED: \(failures) failures in stats feature test")
            exit(1)
        } else {
            print("PASSED: All \(passes) assertions passed")
        }
    }
}
