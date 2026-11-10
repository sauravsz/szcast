import Foundation

public enum WebSearchProvider: String, CaseIterable, Identifiable, Sendable {
    case tavily = "tavily"
    case exa = "exa"
    case jina = "jina"

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .tavily: return "Tavily"
        case .exa: return "Exa"
        case .jina: return "Jina"
        }
    }

    public var placeholder: String {
        switch self {
        case .tavily: return "tvly-..."
        case .exa: return "exa-..."
        case .jina: return "jina_..."
        }
    }

    public var endpoint: URL {
        switch self {
        case .tavily: return URL(string: "https://api.tavily.com/search")!
        case .exa: return URL(string: "https://api.exa.ai/search")!
        case .jina: return URL(string: "https://s.jina.ai")!
        }
    }
}

public struct WebSearchResult: Equatable, Sendable {
    public let title: String
    public let url: URL
    public let snippet: String

    public init(title: String, url: URL, snippet: String) {
        self.title = title
        self.url = url
        self.snippet = snippet
    }
}

public enum WebSearchContextFormatter {
    public static func format(results: [WebSearchResult], query: String) -> String {
        guard !results.isEmpty else { return "" }
        var lines: [String] = [
            "<web_search_results>",
            "Live web search results retrieved for \"\(query)\":\n"
        ]
        for (index, item) in results.enumerated() {
            let num = index + 1
            lines.append("[\(num)] \(item.title)")
            lines.append("URL: \(item.url.absoluteString)")
            if !item.snippet.isEmpty {
                lines.append("Snippet: \(item.snippet)")
            }
            lines.append("")
        }
        lines.append("</web_search_results>")
        lines.append(
            "Instructions: Incorporate the above live web search facts where relevant. Cite sources inline using Markdown links formatted as [Source Title](URL) referencing the exact URLs provided above."
        )
        return lines.joined(separator: "\n")
    }
}
