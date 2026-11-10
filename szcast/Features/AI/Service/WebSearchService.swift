import Foundation

public struct WebSearchService: Sendable {
    private let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    public func search(
        query: String,
        provider: WebSearchProvider,
        apiKey: String
    ) async throws -> [WebSearchResult] {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedQuery.isEmpty else { return [] }

        switch provider {
        case .tavily:
            return try await searchTavily(query: trimmedQuery, apiKey: apiKey)
        case .exa:
            return try await searchExa(query: trimmedQuery, apiKey: apiKey)
        case .jina:
            return try await searchJina(query: trimmedQuery, apiKey: apiKey)
        }
    }

    private func searchTavily(query: String, apiKey: String) async throws -> [WebSearchResult] {
        var request = URLRequest(url: WebSearchProvider.tavily.endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 12
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let payload: [String: Any] = [
            "api_key": apiKey,
            "query": query,
            "search_depth": "basic",
            "max_results": 5,
            "include_answer": true
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            return []
        }

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let results = json["results"] as? [[String: Any]] else {
            return []
        }

        return results.compactMap { item in
            guard let urlString = item["url"] as? String,
                  let url = URL(string: urlString) else { return nil }
            let title = (item["title"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? url.host() ?? urlString
            let content = (item["content"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return WebSearchResult(title: title, url: url, snippet: content)
        }
    }

    private func searchExa(query: String, apiKey: String) async throws -> [WebSearchResult] {
        var request = URLRequest(url: WebSearchProvider.exa.endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 12
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")

        let payload: [String: Any] = [
            "query": query,
            "num_results": 5,
            "contents": [
                "text": ["max_characters": 800]
            ]
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            return []
        }

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let results = json["results"] as? [[String: Any]] else {
            return []
        }

        return results.compactMap { item in
            guard let urlString = item["url"] as? String,
                  let url = URL(string: urlString) else { return nil }
            let title = (item["title"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? url.host() ?? urlString
            let text = (item["text"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return WebSearchResult(title: title, url: url, snippet: text)
        }
    }

    private func searchJina(query: String, apiKey: String) async throws -> [WebSearchResult] {
        guard let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) else {
            return []
        }
        guard let url = URL(string: "https://s.jina.ai/\(encoded)") else { return [] }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 12
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("none", forHTTPHeaderField: "X-Retain-Images")

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            return []
        }

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let items = json["data"] as? [[String: Any]] else {
            return []
        }

        return items.compactMap { item in
            guard let urlString = item["url"] as? String,
                  let url = URL(string: urlString) else { return nil }
            let title = (item["title"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? url.host() ?? urlString
            let content = (item["content"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return WebSearchResult(title: title, url: url, snippet: content)
        }
    }
}
