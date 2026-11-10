import Foundation

@main
struct WebSearchTest {
    static func main() async {
        var failures = 0

        func check(_ description: String, _ condition: @autoclosure () -> Bool) {
            if condition() {
                print("PASS  \(description)")
            } else {
                print("FAIL  \(description)")
                failures += 1
            }
        }

        // 1. WebSearchProvider properties
        check("allCases contains 3 providers", WebSearchProvider.allCases.count == 3)
        check("tavily title and rawValue", WebSearchProvider.tavily.title == "Tavily" && WebSearchProvider.tavily.rawValue == "tavily")
        check("exa title and rawValue", WebSearchProvider.exa.title == "Exa" && WebSearchProvider.exa.rawValue == "exa")
        check("jina title and rawValue", WebSearchProvider.jina.title == "Jina" && WebSearchProvider.jina.rawValue == "jina")
        check("tavily endpoint", WebSearchProvider.tavily.endpoint.absoluteString == "https://api.tavily.com/search")
        check("exa endpoint", WebSearchProvider.exa.endpoint.absoluteString == "https://api.exa.ai/search")
        check("jina endpoint", WebSearchProvider.jina.endpoint.absoluteString == "https://s.jina.ai")

        // 2. WebSearchResult
        let url1 = URL(string: "https://example.com/swift")!
        let result1 = WebSearchResult(title: "Swift Org", url: url1, snippet: "A modern programming language.")
        let result2 = WebSearchResult(title: "Swift Org", url: url1, snippet: "A modern programming language.")
        check("WebSearchResult equatable equality", result1 == result2)

        // 3. WebSearchContextFormatter
        check("empty results yields empty formatted context", WebSearchContextFormatter.format(results: [], query: "test").isEmpty)

        let formatted = WebSearchContextFormatter.format(results: [result1], query: "Swift language")
        check("formatted includes opening tag", formatted.contains("<web_search_results>"))
        check("formatted includes query header", formatted.contains("Live web search results retrieved for \"Swift language\":"))
        check("formatted includes result item", formatted.contains("[1] Swift Org"))
        check("formatted includes result url", formatted.contains("URL: https://example.com/swift"))
        check("formatted includes snippet", formatted.contains("Snippet: A modern programming language."))
        check("formatted includes closing tag", formatted.contains("</web_search_results>"))
        check("formatted includes citation instruction", formatted.contains("[Source Title](URL)"))

        // 4. WebSearchService query validation
        let service = WebSearchService()
        do {
            let emptyResults = try await service.search(query: "   \n\t  ", provider: .tavily, apiKey: "dummy")
            check("empty query returns empty array without throwing", emptyResults.isEmpty)
        } catch {
            check("empty query should not throw", false)
        }

        if failures > 0 {
            print("\n\(failures) check(s) failed")
            exit(1)
        }
        print("\nAll web search checks passed.")
    }
}
