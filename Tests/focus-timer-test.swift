import Foundation

@main
struct FocusTimerTest {
    static func main() {
        var failures = 0

        func check(_ description: String, _ condition: @autoclosure () -> Bool) {
            if condition() {
                print("PASS  \(description)")
            } else {
                print("FAIL  \(description)")
                failures += 1
            }
        }

        // 1. Durations
        check("work default duration is 25 minutes", FocusTimerMode.work.defaultDuration == 25 * 60)
        check("short break default duration is 5 minutes", FocusTimerMode.shortBreak.defaultDuration == 5 * 60)
        check("long break default duration is 15 minutes", FocusTimerMode.longBreak.defaultDuration == 15 * 60)

        // 2. Next mode transitions
        check("work leads to short break", FocusTimerMode.work.nextMode == .shortBreak)
        check("short break leads to work", FocusTimerMode.shortBreak.nextMode == .work)
        check("long break leads to work", FocusTimerMode.longBreak.nextMode == .work)

        // 3. Formatting
        check("formats 25 minutes", FocusTimerFormatter.format(seconds: 1500) == "25:00")
        check("formats 65 seconds", FocusTimerFormatter.format(seconds: 65) == "01:05")
        check("formats 0 seconds", FocusTimerFormatter.format(seconds: 0) == "00:00")
        check("clamps negative seconds to 00:00", FocusTimerFormatter.format(seconds: -10) == "00:00")

        let summary = FocusTimerFormatter.formatRemainingSummary(mode: .work, seconds: 1500, status: .running)
        check("summary includes mode title and formatted time", summary == "Focus: 25:00")

        let pausedSummary = FocusTimerFormatter.formatRemainingSummary(mode: .shortBreak, seconds: 300, status: .paused)
        check("paused summary indicates paused status", pausedSummary == "Short Break: 05:00 (Paused)")

        // 4. Engine math
        check("initial progress is 0.0", FocusTimerEngine.progress(remaining: 1500, total: 1500) == 0.0)
        check("halfway progress is 0.5", FocusTimerEngine.progress(remaining: 750, total: 1500) == 0.5)
        check("completed progress is 1.0", FocusTimerEngine.progress(remaining: 0, total: 1500) == 1.0)
        check("decrement next seconds", FocusTimerEngine.nextSeconds(remaining: 10) == 9)
        check("next seconds clamps at 0", FocusTimerEngine.nextSeconds(remaining: 0) == 0)

        if failures > 0 {
            print("\n\(failures) check(s) failed")
            exit(1)
        }
        print("\nAll focus timer checks passed.")
    }
}
