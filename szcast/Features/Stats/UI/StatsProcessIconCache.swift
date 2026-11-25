import AppKit
import UniformTypeIdentifiers

@MainActor
final class StatsProcessIconCache {
    static let shared = StatsProcessIconCache()

    private struct CacheKey: Hashable {
        let pid: Int32
        let path: String?
    }

    private var cache: [CacheKey: NSImage] = [:]
    private var order: [CacheKey] = []
    private let maxEntries = 96

    private lazy var fallbackIcon: NSImage = {
        let icon = NSWorkspace.shared.icon(for: .unixExecutable)
        icon.size = NSSize(width: 16, height: 16)
        return icon
    }()

    func icon(forPID pid: Int32, executablePath: String?) -> NSImage {
        let key = CacheKey(pid: pid, path: executablePath)
        if let hit = cache[key] {
            return hit
        }

        var resolved: NSImage?
        if let app = NSRunningApplication(processIdentifier: pid), let appIcon = app.icon {
            resolved = appIcon
        } else if let executablePath, !executablePath.isEmpty {
            if let bundleURL = appBundleURL(from: executablePath) {
                resolved = NSWorkspace.shared.icon(forFile: bundleURL.path)
            } else {
                resolved = NSWorkspace.shared.icon(forFile: executablePath)
            }
        }

        let finalIcon = (resolved?.copy() as? NSImage) ?? fallbackIcon
        finalIcon.size = NSSize(width: 16, height: 16)

        if cache.count >= maxEntries, let oldest = order.first {
            order.removeFirst()
            cache.removeValue(forKey: oldest)
        }
        cache[key] = finalIcon
        order.append(key)
        return finalIcon
    }

    private func appBundleURL(from executablePath: String) -> URL? {
        var url = URL(fileURLWithPath: executablePath)
        while url.pathComponents.count > 1 {
            if url.pathExtension == "app" {
                return url
            }
            url.deleteLastPathComponent()
        }
        return nil
    }
}
