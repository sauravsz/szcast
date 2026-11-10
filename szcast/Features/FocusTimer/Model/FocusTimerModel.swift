import Foundation

public enum FocusTimerMode: String, CaseIterable, Sendable {
    case work
    case shortBreak
    case longBreak

    public var title: String {
        switch self {
        case .work: return "Focus"
        case .shortBreak: return "Short Break"
        case .longBreak: return "Long Break"
        }
    }

    public var sfSymbol: String {
        switch self {
        case .work: return "brain.head.profile"
        case .shortBreak: return "cup.and.saucer.fill"
        case .longBreak: return "figure.walk"
        }
    }

    public var defaultDuration: Int {
        switch self {
        case .work: return 25 * 60
        case .shortBreak: return 5 * 60
        case .longBreak: return 15 * 60
        }
    }

    public var nextMode: FocusTimerMode {
        switch self {
        case .work: return .shortBreak
        case .shortBreak, .longBreak: return .work
        }
    }
}

public enum FocusTimerStatus: String, Sendable {
    case idle
    case running
    case paused
}

public enum FocusTimerFormatter {
    public static func format(seconds: Int) -> String {
        let clamped = max(0, seconds)
        let mins = clamped / 60
        let secs = clamped % 60
        return String(format: "%02d:%02d", mins, secs)
    }

    public static func formatRemainingSummary(mode: FocusTimerMode, seconds: Int, status: FocusTimerStatus) -> String {
        let time = format(seconds: seconds)
        switch status {
        case .idle:
            return "\(mode.title): \(time)"
        case .running:
            return "\(mode.title): \(time)"
        case .paused:
            return "\(mode.title): \(time) (Paused)"
        }
    }
}
