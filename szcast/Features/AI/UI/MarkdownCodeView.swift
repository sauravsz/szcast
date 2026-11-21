import SwiftUI

/// Lines soft-wrap: a second scroll view would fight the transcript's own dissolve.
struct MarkdownCodeView: View {
    @Environment(\.metrics) private var metrics
    let language: String?
    let text: String
    @State private var justInserted = false

    private var isTerminalCommand: Bool {
        guard let lang = language?.lowercased() else { return false }
        return lang == "bash" || lang == "sh" || lang == "zsh" || lang == "shell"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: metrics.spacing.sm) {
            HStack(spacing: metrics.spacing.md) {
                if let language {
                    Text(language)
                        .font(metrics.typography.keyCap)
                        .foregroundStyle(Theme.Colors.textTertiary)
                }
                Spacer(minLength: 0)
                HStack(spacing: metrics.spacing.sm) {
                    if isTerminalCommand {
                        Button {
                            let escaped = text.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
                            let script = "tell application \"Terminal\" to do script \"\(escaped)\" activate"
                            if let appleScript = NSAppleScript(source: script) {
                                var error: NSDictionary?
                                appleScript.executeAndReturnError(&error)
                            }
                        } label: {
                            HStack(spacing: 3) {
                                Image(systemName: "terminal")
                                Text("Run in Terminal")
                            }
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(Theme.Colors.textSecondary)
                        }
                        .buttonStyle(.plain)
                        .help("Run command in Terminal")
                    }

                    Button {
                        let app = NSWorkspace.shared.frontmostApplication
                        Paster.pasteString(text, previousApp: app)
                        justInserted = true
                        Task {
                            try? await Task.sleep(for: .seconds(1.2))
                            justInserted = false
                        }
                    } label: {
                        HStack(spacing: 3) {
                            Image(systemName: justInserted ? "checkmark" : "arrow.right.doc.on.clipboard")
                            Text(justInserted ? "Inserted!" : "Insert")
                        }
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(justInserted ? Color.green : Theme.Colors.textSecondary)
                    }
                    .buttonStyle(.plain)
                    .help("Paste code directly into your active editor or app")

                    ChatCopyButton(text: text, label: String(localized: "Copy Code"))
                }
            }
            Text(text)
                .font(metrics.typography.code)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, metrics.spacing.xl)
        .padding(.vertical, metrics.spacing.lg)
        .background(
            RoundedRectangle(cornerRadius: metrics.radius.card, style: .continuous)
                .fill(Theme.Colors.cardFill)
        )
        .overlay(
            RoundedRectangle(cornerRadius: metrics.radius.card, style: .continuous)
                .stroke(Theme.Colors.cardStroke))
    }
}
