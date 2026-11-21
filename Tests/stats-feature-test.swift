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

        // 1. CPU Telemetry
        let cpu = reader.readCPU()
        expect(cpu.logicalCores >= 1, "Logical CPU core count >= 1 (got \(cpu.logicalCores))")
        expect(cpu.physicalCores >= 1, "Physical CPU core count >= 1 (got \(cpu.physicalCores))")
        expect(cpu.totalUsage >= 0 && cpu.totalUsage <= 100, "CPU usage within 0..100% (got \(cpu.totalUsage))")

        // 2. RAM Telemetry
        let ram = reader.readRAM()
        expect(ram.totalBytes > 0, "Total RAM > 0 (got \(ram.totalGB) GB)")
        expect(ram.usedBytes > 0, "Used RAM > 0 (got \(ram.usedGB) GB)")
        expect(ram.usagePercentage > 0 && ram.usagePercentage <= 100, "RAM usage % valid (got \(ram.usagePercentage)%)")
        expect(ram.activeBytes + ram.wiredBytes + ram.compressedBytes == ram.usedBytes, "RAM used matches components")

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
        expect(!network.localIP.isEmpty, "Local IP detected (got \(network.localIP))")

        // 6. Top Processes
        let processes = reader.readTopProcesses(limit: 5)
        expect(!processes.byCPU.isEmpty, "Captured top processes by CPU (got \(processes.byCPU.count))")
        expect(!processes.byRAM.isEmpty, "Captured top processes by RAM (got \(processes.byRAM.count))")
        if let topProc = processes.byCPU.first {
            expect(topProc.id > 0, "Top CPU process has valid PID: \(topProc.id) (\(topProc.name))")
        }

        // 7. Full Snapshot capture
        let snapshot = reader.captureSnapshot(processLimit: 5)
        expect(snapshot.cpu.logicalCores >= 1, "Snapshot carries valid CPU stats")
        expect(snapshot.ram.totalBytes > 0, "Snapshot carries valid RAM stats")
        expect(!snapshot.disk.volumes.isEmpty, "Snapshot carries disk volumes")

        if failures > 0 {
            print("FAILED: \(failures) failures in stats feature test")
            exit(1)
        } else {
            print("PASSED: All \(passes) assertions passed")
        }
    }
}
