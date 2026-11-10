import Foundation

/// The fallback configuration a fresh install starts with.
enum DefaultFallbacks {
    static let braveSearchID = "quicklink:30e37c45-4a30-4d82-b400-cc6bd135f11b"
    static let chatGPTWebSearchID = "quicklink:9347c095-0545-4e25-8bf4-baeed5d1bc39"
    static let braveAskID = "quicklink:bbd1099b-033d-4317-9b96-8470b962a312"
    static let alternativeToID = "quicklink:e9232dac-4be0-41f4-9b90-dd6b60e15943"
    static let chatGPTID = "quicklink:9da31408-a8d1-4a00-880b-516ac05748cb"
    static let perplexityID = "quicklink:878c6c9e-85a0-4877-9711-2734c88ed5aa"

    /// The default display order matching the fallbacks panel.
    static let order: [String] = [
        braveSearchID,
        chatGPTWebSearchID,
        braveAskID,
        CommandID.quickAI.rawValue,
        CommandID.searchFiles.rawValue,
        CommandID.runShellCommand.rawValue,
        CommandID.define.rawValue,
        alternativeToID,
        chatGPTID,
        perplexityID,
    ]

    /// By default, only Brave Search, ChatGPT Web Search, and Brave Ask are offered.
    static let disabled: Set<String> = [
        CommandID.quickAI.rawValue,
        CommandID.searchFiles.rawValue,
        CommandID.runShellCommand.rawValue,
        CommandID.define.rawValue,
        alternativeToID,
        chatGPTID,
        perplexityID,
    ]
}
