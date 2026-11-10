import Foundation

/// Augments an underlying AIProvider with live web search results from Tavily, Exa, or Jina.
struct WebSearchAIProvider: AIProvider {
    private let base: any AIProvider
    private let searchService: WebSearchService
    private let provider: WebSearchProvider
    private let apiKey: String

    init(
        base: any AIProvider,
        searchService: WebSearchService = WebSearchService(),
        provider: WebSearchProvider,
        apiKey: String
    ) {
        self.base = base
        self.searchService = searchService
        self.provider = provider
        self.apiKey = apiKey
    }

    func stream(_ request: AIRequest) -> AIProviderStream {
        guard request.webSearch, !apiKey.isEmpty else {
            return base.stream(request)
        }

        return AIProviderStream { continuation in
            let task = Task.detached {
                do {
                    let query = extractSearchQuery(from: request)
                    var augmentedRequest = request

                    if !query.isEmpty {
                        continuation.yield(.searching(query))
                        let results = (try? await searchService.search(
                            query: query, provider: provider, apiKey: apiKey)) ?? []
                        continuation.yield(.searched(query))

                        if !results.isEmpty {
                            let context = WebSearchContextFormatter.format(results: results, query: query)
                            let currentInstructions = request.instructions ?? ""
                            let combinedInstructions = currentInstructions.isEmpty
                                ? context
                                : currentInstructions + "\n\n" + context

                            augmentedRequest = AIRequest(
                                instructions: combinedInstructions,
                                messages: request.messages,
                                webSearch: false,
                                tools: request.tools,
                                conversationID: request.conversationID
                            )
                        }
                    }

                    for try await event in base.stream(augmentedRequest) {
                        try Task.checkCancellation()
                        continuation.yield(event)
                    }
                    continuation.finish()
                } catch is CancellationError {
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private func extractSearchQuery(from request: AIRequest) -> String {
        for message in request.messages.reversed() {
            if message.role == .user {
                let text = message.text.trimmingCharacters(in: .whitespacesAndNewlines)
                if !text.isEmpty { return text }
            }
        }
        return ""
    }
}
