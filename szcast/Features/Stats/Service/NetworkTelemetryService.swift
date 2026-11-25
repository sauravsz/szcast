import Foundation
import Darwin

enum NetworkTelemetryService {
    struct PublicIPInfo: Sendable {
        let ip: String
        let countryCode: String?
    }

    struct ProcessNetCounter: Sendable {
        let pid: Int32
        let name: String
        let bytesIn: UInt64
        let bytesOut: UInt64
    }

    private static let ephemeralSession: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.urlCache = nil
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        config.timeoutIntervalForRequest = 4
        config.timeoutIntervalForResource = 5
        return URLSession(configuration: config)
    }()

    /// Measures ICMP round-trip latency via an unprivileged datagram socket.
    nonisolated static func pingHost(_ host: String = "1.1.1.1") async -> Double? {
        await Task.detached(priority: .utility) {
            let sock = socket(AF_INET, SOCK_DGRAM, IPPROTO_ICMP)
            guard sock >= 0 else { return nil }
            defer { close(sock) }

            var timeout = timeval(tv_sec: 1, tv_usec: 500_000)
            setsockopt(
                sock, SOL_SOCKET, SO_RCVTIMEO, &timeout,
                socklen_t(MemoryLayout<timeval>.size))

            var addr = sockaddr_in()
            addr.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
            addr.sin_family = sa_family_t(AF_INET)
            guard inet_pton(AF_INET, host, &addr.sin_addr) == 1 else { return nil }

            let ident = UInt16.random(in: 1...UInt16.max)
            var packet = [UInt8](repeating: 0, count: 64)
            packet[0] = 8
            packet[1] = 0
            packet[4] = UInt8(ident >> 8)
            packet[5] = UInt8(ident & 0xFF)
            packet[6] = 0
            packet[7] = 1

            var sum: UInt32 = 0
            for i in stride(from: 0, to: packet.count, by: 2) {
                sum += UInt32(packet[i]) << 8 | UInt32(packet[i + 1])
            }
            while (sum >> 16) != 0 {
                sum = (sum & 0xFFFF) + (sum >> 16)
            }
            let checksum = ~UInt16(sum & 0xFFFF)
            packet[2] = UInt8(checksum >> 8)
            packet[3] = UInt8(checksum & 0xFF)

            let startNs = DispatchTime.now().uptimeNanoseconds
            let sent = withUnsafePointer(to: &addr) {
                $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { sa in
                    sendto(sock, packet, packet.count, 0, sa, socklen_t(MemoryLayout<sockaddr_in>.size))
                }
            }
            guard sent > 0 else { return nil }

            var buffer = [UInt8](repeating: 0, count: 256)
            let received = recv(sock, &buffer, buffer.count, 0)
            guard received >= 28 else { return nil }
            let elapsedMs = Double(DispatchTime.now().uptimeNanoseconds - startNs) / 1_000_000.0
            return elapsedMs
        }.value
    }

    nonisolated static func fetchPublicIP() async -> PublicIPInfo? {
        if let url = URL(string: "https://ipinfo.io/json"),
           let (data, response) = try? await ephemeralSession.data(from: url),
           (response as? HTTPURLResponse)?.statusCode == 200,
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let ip = json["ip"] as? String, !ip.isEmpty
        {
            let country = json["country"] as? String
            return PublicIPInfo(ip: ip, countryCode: country)
        }

        if let url = URL(string: "https://api.ipify.org?format=json"),
           let (data, response) = try? await ephemeralSession.data(from: url),
           (response as? HTTPURLResponse)?.statusCode == 200,
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let ip = json["ip"] as? String, !ip.isEmpty
        {
            return PublicIPInfo(ip: ip, countryCode: nil)
        }
        return nil
    }

    nonisolated static func sampleNetworkProcessCounters() async -> [Int32: ProcessNetCounter] {
        await Task.detached(priority: .utility) {
            let task = Process()
            task.executableURL = URL(fileURLWithPath: "/usr/bin/nettop")
            task.arguments = ["-P", "-L", "1", "-n", "-J", "bytes_in,bytes_out", "-t", "external"]
            let outPipe = Pipe()
            task.standardOutput = outPipe
            task.standardError = Pipe()

            do {
                let exit = try task.runObservingExit()
                let data = outPipe.fileHandleForReading.readDataToEndOfFile()
                exit.wait()
                guard let output = String(data: data, encoding: .utf8) else { return [:] }
                return parseNettopOutput(output)
            } catch {
                return [:]
            }
        }.value
    }

    nonisolated static func parseNettopOutput(_ output: String) -> [Int32: ProcessNetCounter] {
        var result: [Int32: ProcessNetCounter] = [:]
        for rawLine in output.components(separatedBy: "\n") {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.isEmpty, !line.hasPrefix(",") else { continue }
            let fields = line.split(separator: ",", omittingEmptySubsequences: false)
            guard fields.count >= 3 else { continue }
            let procToken = String(fields[0])
            guard let dotIndex = procToken.lastIndex(of: ".") else { continue }
            let pidString = String(procToken[procToken.index(after: dotIndex)...])
            let name = String(procToken[..<dotIndex])
            guard let pid = Int32(pidString), !name.isEmpty,
                  let bytesIn = UInt64(fields[1]),
                  let bytesOut = UInt64(fields[2]) else { continue }
            result[pid] = ProcessNetCounter(pid: pid, name: name, bytesIn: bytesIn, bytesOut: bytesOut)
        }
        return result
    }

    nonisolated static func executablePath(for pid: Int32) -> String? {
        var buffer = [CChar](repeating: 0, count: 4096)
        let length = proc_pidpath(pid, &buffer, UInt32(buffer.count))
        guard length > 0 else { return nil }
        let bytes = buffer.prefix(Int(length)).prefix(while: { $0 != 0 }).map { UInt8(bitPattern: $0) }
        return String(decoding: bytes, as: UTF8.self)
    }
}
