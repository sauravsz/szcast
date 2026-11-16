import Foundation

struct ModifierKeyDetector: Sendable {
    enum Event: Equatable {
        case pressed(ModifierKey)
        case released(ModifierKey, doubleTap: Bool, held: Bool)
        case cancelled
    }

    static let maxSingleHold: TimeInterval = 0.65

    static let resolutionWindow: Duration = .seconds(
        DoubleTapDetector.maxGap + DoubleTapDetector.maxHold + 0.02)

    private(set) var held: Set<ModifierKey> = []
    private var press: (key: ModifierKey, startedAt: TimeInterval)?
    private var pendingTap: (key: ModifierKey, releasedAt: TimeInterval)?

    mutating func handle(_ keys: Set<ModifierKey>, at now: TimeInterval) -> Event? {
        let previous = held
        held = keys
        guard keys != previous else { return nil }
        if keys.isEmpty {
            guard let press else { return nil }
            self.press = nil
            let duration = now - press.startedAt
            let isHeldForSingle = duration > Self.maxSingleHold
            let isHeldForDouble = duration > DoubleTapDetector.maxHold
            let isDouble =
                !isHeldForDouble && pendingTap?.key == press.key
                && press.startedAt - (pendingTap?.releasedAt ?? 0) <= DoubleTapDetector.maxGap
            pendingTap = isHeldForDouble || isDouble ? nil : (press.key, now)
            return .released(press.key, doubleTap: isDouble, held: isHeldForSingle)
        }
        guard previous.isEmpty, keys.count == 1, let key = keys.first else {
            cancel()
            return .cancelled
        }
        if pendingTap?.key != key { pendingTap = nil }
        press = (key, now)
        return .pressed(key)
    }

    mutating func cancel() {
        press = nil
        pendingTap = nil
    }

    mutating func reset() {
        held = []
        cancel()
    }
}
