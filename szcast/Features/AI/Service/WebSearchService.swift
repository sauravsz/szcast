import Foundation

public enum WebSearchError: LocalizedError, Sendable {
    case unauthorized(provider: String)
    case rateLimited(provider: String)
    case httpError(provider: String, statusCode: Int, message: String)
    case invalidResponse

    public var errorDescription: String? {
        switch self {
        case .unauthorized(let provider):
            return String(localized: "\(provider) API key is invalid or unauthorized. Please verify your API key in Settings > AI.")
        case .rateLimited(let provider):
            return String(localized: "\(provider) rate limit exceeded. Please wait a moment or upgrade your plan.")
        case .httpError(let provider, let code, let msg):
            return String(localized: "\(provider) search error (\(code)): \(msg)")
        case .invalidResponse:
            return String(localized: "Invalid response from web search service.")
        }
    }
}

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
        guard let http = response as? HTTPURLResponse else {
            throw WebSearchError.invalidResponse
        }
        if http.statusCode == 401 || http.statusCode == 403 {
            throw WebSearchError.unauthorized(provider: "Tavily")
        }
        if http.statusCode == 429 {
            throw WebSearchError.rateLimited(provider: "Tavily")
        }
        guard (200...299).contains(http.statusCode) else {
            let msg = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw WebSearchError.httpError(provider: "Tavily", statusCode: http.statusCode, message: msg)
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
        guard let http = response as? HTTPURLResponse else {
            throw WebSearchError.invalidResponse
        }
        if http.statusCode == 401 || http.statusCode == 403 {
            throw WebSearchError.unauthorized(provider: "Exa")
        }
        if http.statusCode == 429 {
            throw WebSearchError.rateLimited(provider: "Exa")
        }
        guard (200...299).contains(http.statusCode) else {
            let msg = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw WebSearchError.httpError(provider: "Exa", statusCode: http.statusCode, message: msg)
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
        var allowed = CharacterSet.urlPathAllowed
        allowed.remove(charactersIn: "/?#&")
        guard let encoded = query.addingPercentEncoding(withAllowedCharacters: allowed) else {
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
        guard let http = response as? HTTPURLResponse else {
            throw WebSearchError.invalidResponse
        }
        if http.statusCode == 401 || http.statusCode == 403 {
            throw WebSearchError.unauthorized(provider: "Jina")
        }
        if http.statusCode == 429 {
            throw WebSearchError.rateLimited(provider: "Jina")
        }
        guard (200...299).contains(http.statusCode) else {
            let msg = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw WebSearchError.httpError(provider: "Jina", statusCode: http.statusCode, message: msg)
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
