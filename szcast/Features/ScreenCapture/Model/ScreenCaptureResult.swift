import Foundation

struct ScreenCaptureResult: Sendable, Equatable {
    enum Kind: Sendable, Equatable {
        case text(String)
        case qrCode(payload: String)
    }

    let kind: Kind
    let rawText: String

    var isURL: Bool {
        if let url = URL(string: rawText), url.scheme != nil, url.host != nil {
            return true
        }
        return false
    }

    var displaySummary: String {
        switch kind {
        case .qrCode(let payload):
            return "QR Code: \(payload)"
        case .text(let text):
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.count <= 60 {
                return trimmed
            }
            return String(trimmed.prefix(57)) + "..."
        }
    }
}
