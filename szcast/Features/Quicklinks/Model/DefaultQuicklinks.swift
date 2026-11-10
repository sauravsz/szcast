import Foundation

/// The quicklinks shipped with szcast by default for web searches and fallbacks.
enum DefaultQuicklinks {
    static let braveSearchUUID = UUID(uuidString: "30E37C45-4A30-4D82-B400-CC6BD135F11B")!
    static let chatGPTWebSearchUUID = UUID(uuidString: "9347C095-0545-4E25-8BF4-BAEED5D1BC39")!
    static let braveAskUUID = UUID(uuidString: "BBD1099B-033D-4317-9B96-8470B962A312")!
    static let alternativeToUUID = UUID(uuidString: "E9232DAC-4BE0-41F4-9B90-DD6B60E15943")!
    static let chatGPTUUID = UUID(uuidString: "9DA31408-A8D1-4A00-880B-516AC05748CB")!
    static let perplexityUUID = UUID(uuidString: "878C6C9E-85A0-4877-9711-2734C88ED5AA")!

    static var all: [Quicklink] {
        [
            Quicklink(
                id: braveSearchUUID,
                name: "Brave Search",
                link: "https://search.brave.com/search?q={argument name=\"Query\"}"
            ),
            Quicklink(
                id: chatGPTWebSearchUUID,
                name: "ChatGPT Web Search",
                link: "https://chatgpt.com/?q={argument name=\"Query\"}&hints=search"
            ),
            Quicklink(
                id: braveAskUUID,
                name: "Brave Ask",
                link: "https://search.brave.com/ask?q={argument name=\"Query\"}"
            ),
            Quicklink(
                id: alternativeToUUID,
                name: "Alternative to",
                link: "https://alternativeto.net/browse/search/?q={argument name=\"Query\"}"
            ),
            Quicklink(
                id: chatGPTUUID,
                name: "ChatGPT",
                link: "https://chatgpt.com/?q={argument name=\"Query\"}"
            ),
            Quicklink(
                id: perplexityUUID,
                name: "Perplexity",
                link: "https://www.perplexity.ai/?q={argument name=\"Query\"}"
            ),
        ]
    }
}
