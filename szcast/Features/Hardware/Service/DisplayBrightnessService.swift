import AppKit
import Foundation

@MainActor
final class DisplayBrightnessService {
    static let shared = DisplayBrightnessService()

    private typealias SetBrightnessFunc = @convention(c) (CGDirectDisplayID, Float) -> Int32
    private typealias GetBrightnessFunc = @convention(c) (CGDirectDisplayID, UnsafeMutablePointer<Float>) -> Int32

    private let setBrightnessPtr: SetBrightnessFunc?
    private let getBrightnessPtr: GetBrightnessFunc?

    init() {
        if let handle = dlopen("/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices", RTLD_LAZY) {
            if let setSym = dlsym(handle, "DisplayServicesSetBrightness") {
                setBrightnessPtr = unsafeBitCast(setSym, to: SetBrightnessFunc.self)
            } else {
                setBrightnessPtr = nil
            }
            if let getSym = dlsym(handle, "DisplayServicesGetBrightness") {
                getBrightnessPtr = unsafeBitCast(getSym, to: GetBrightnessFunc.self)
            } else {
                getBrightnessPtr = nil
            }
        } else {
            setBrightnessPtr = nil
            getBrightnessPtr = nil
        }
    }

    func currentBrightness() -> Float? {
        let displayID = CGMainDisplayID()
        guard let getBrightnessPtr else { return nil }
        var brightness: Float = 0
        let status = getBrightnessPtr(displayID, &brightness)
        return status == 0 ? brightness : nil
    }

    @discardableResult
    func setBrightness(_ level: Float) -> Bool {
        let clamped = max(0.0, min(1.0, level))
        let displayID = CGMainDisplayID()

        var succeeded = false
        if let setBrightnessPtr {
            succeeded = setBrightnessPtr(displayID, clamped) == 0
        }

        // Also attempt Lunar CLI if installed for external monitor DDC support
        adjustLunarIfAvailable(percent: Int(clamped * 100))

        return succeeded
    }

    @discardableResult
    func stepBrightness(by delta: Float) -> Float? {
        let current = currentBrightness() ?? 0.5
        let target = max(0.0, min(1.0, current + delta))
        if setBrightness(target) {
            return target
        }
        return nil
    }

    private func adjustLunarIfAvailable(percent: Int) {
        let candidates = ["/usr/local/bin/lunar", "/opt/homebrew/bin/lunar", "/Applications/Lunar.app/Contents/MacOS/Lunar"]
        guard let binary = candidates.first(where: { FileManager.default.isExecutableFile(atPath: $0) }) else {
            return
        }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: binary)
        process.arguments = ["set", "brightness", "\(percent)"]
        try? process.run()
    }
}
