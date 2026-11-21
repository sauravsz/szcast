import Foundation

public struct MeetingNote: Identifiable, Codable, Equatable, Sendable {
    public var id: UUID
    public var title: String
    public var date: Date
    public var duration: TimeInterval
    public var transcript: String
    public var summary: String
    public var actionItems: [String]
    public var decisions: [String]

    public init(
        id: UUID = UUID(),
        title: String,
        date: Date = Date(),
        duration: TimeInterval = 0,
        transcript: String,
        summary: String = "",
        actionItems: [String] = [],
        decisions: [String] = []
    ) {
        self.id = id
        self.title = title
        self.date = date
        self.duration = duration
        self.transcript = transcript
        self.summary = summary
        self.actionItems = actionItems
        self.decisions = decisions
    }

    public var markdownMemo: String {
        var lines: [String] = []
        lines.append("# \(title)")
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        lines.append("*Recorded on \(formatter.string(from: date)) · Duration: \(Int(duration / 60))m \(Int(duration.truncatingRemainder(dividingBy: 60)))s*")
        lines.append("")

        if !summary.isEmpty {
            lines.append("## Executive Summary")
            lines.append(summary)
            lines.append("")
        }

        if !decisions.isEmpty {
            lines.append("## Key Decisions")
            for d in decisions {
                lines.append("- \(d)")
            }
            lines.append("")
        }

        if !actionItems.isEmpty {
            lines.append("## Action Items")
            for item in actionItems {
                lines.append("- [ ] \(item)")
            }
            lines.append("")
        }

        if !transcript.isEmpty {
            lines.append("## Full Transcript")
            lines.append(transcript)
        }

        return lines.joined(separator: "\n")
    }
}
