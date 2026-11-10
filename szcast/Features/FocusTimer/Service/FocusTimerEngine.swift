import Foundation

public enum FocusTimerEngine {
    public static func progress(remaining: Int, total: Int) -> Double {
        guard total > 0 else { return 0.0 }
        let elapsed = max(0, total - max(0, remaining))
        return min(1.0, max(0.0, Double(elapsed) / Double(total)))
    }

    public static func nextSeconds(remaining: Int) -> Int {
        max(0, remaining - 1)
    }
}
