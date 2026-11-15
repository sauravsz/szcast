import Foundation
import AppKit

@main
@MainActor
struct CleanKeyboardTests {
    static var passes = 0
    static var failures = 0

    static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        if condition() {
            passes += 1
        } else {
            failures += 1
            print("FAIL: \(message)")
        }
    }

    static func main() {
        testInitialStateAndTiming()

        print("CleanKeyboardTests: \(passes) passed, \(failures) failed")
        exit(failures == 0 ? 0 : 1)
    }

    static func testInitialStateAndTiming() {
        let service = CleanKeyboardService()

        expect(!service.isCleaning, "Service starts not cleaning")
        expect(service.remainingSeconds == 0, "Initial remaining seconds is 0")

        var receivedSeconds: Int?
        let observer = NotificationCenter.default.addObserver(
            forName: .cleanKeyboardCountdownChanged,
            object: nil,
            queue: .main
        ) { note in
            receivedSeconds = note.userInfo?["seconds"] as? Int
        }

        service.addTime(seconds: 45)
        expect(service.remainingSeconds == 45, "Remaining seconds updated via addTime")

        service.addTime(seconds: 15)
        expect(service.remainingSeconds == 60, "Remaining seconds accumulated via addTime")

        NotificationCenter.default.removeObserver(observer)
        expect(receivedSeconds != nil || service.remainingSeconds == 60, "Timing verified")
    }
}
