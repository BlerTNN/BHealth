//
//  TavilySearchClient.swift
//  BHealth
//
//  Created by Codex on 2026-07-02.
//

import Foundation

struct TavilySearchClient {
    private let apiKeyStore: TavilyAPIKeyStore
    private let session: URLSession

    init(apiKeyStore: TavilyAPIKeyStore = .shared, session: URLSession = .shared) {
        self.apiKeyStore = apiKeyStore
        self.session = session
    }

    var hasAPIKey: Bool {
        apiKeyStore.hasAPIKey
    }

    func search(_ query: String, maxResults: Int = 3) async throws -> WebSearchContext {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedQuery.isEmpty else { throw TavilySearchError.emptyQuery }

        let apiKey = try apiKeyStore.readAPIKey()
        guard let url = URL(string: "https://api.tavily.com/search") else {
            throw TavilySearchError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 12
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("BHealth", forHTTPHeaderField: "X-Project-ID")

        let body = TavilySearchRequest(
            query: trimmedQuery,
            searchDepth: "basic",
            topic: "general",
            maxResults: max(1, min(maxResults, 5)),
            includeAnswer: true,
            includeRawContent: false,
            includeImages: false
        )
        request.httpBody = try JSONEncoder.tavilyEncoder.encode(body)

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw TavilySearchError.invalidResponse
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw TavilySearchError.httpStatus(httpResponse.statusCode, body)
        }

        let decoded = try JSONDecoder.tavilyDecoder.decode(TavilySearchResponse.self, from: data)
        return WebSearchContext(
            provider: "Tavily Search API",
            query: decoded.query ?? trimmedQuery,
            answer: decoded.answer?.trimmingCharacters(in: .whitespacesAndNewlines).nonEmpty,
            results: decoded.results.prefix(maxResults).map { result in
                WebSearchResult(
                    title: result.title,
                    url: result.url,
                    content: result.content,
                    score: result.score
                )
            }
        )
    }
}

struct WebSearchContext: Codable, Hashable {
    let provider: String
    let query: String
    let answer: String?
    let results: [WebSearchResult]

    var isEmpty: Bool {
        answer == nil && results.isEmpty
    }
}

struct WebSearchResult: Codable, Hashable {
    let title: String
    let url: String
    let content: String
    let score: Double?
}

enum WebSearchPlanner {
    static func query(
        for text: String,
        mode: AssistantMode,
        calculation: MealCalculationResult?
    ) -> String? {
        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedText.isEmpty else { return nil }

        switch mode {
        case .healthCoach:
            if needsCurrentInformation(trimmedText) {
                return trimmedText
            }
            return nil
        case .foodLog:
            if calculation == nil || calculation?.confidence == "low" || mentionsPackagedOrRestaurantFood(trimmedText) {
                return "\(trimmedText) nutrition calories protein fat carbohydrate"
            }
            return nil
        }
    }

    private static func needsCurrentInformation(_ text: String) -> Bool {
        let normalized = text
            .folding(options: [.diacriticInsensitive, .widthInsensitive], locale: .current)
            .lowercased()
        let markers = [
            "最新", "最近", "新闻", "现在", "今年", "今日", "今天",
            "current", "latest", "recent", "news", "today", "this year"
        ]
        return markers.contains { normalized.contains($0) }
    }

    private static func mentionsPackagedOrRestaurantFood(_ text: String) -> Bool {
        let normalized = text
            .folding(options: [.diacriticInsensitive, .widthInsensitive], locale: .current)
            .lowercased()
        let markers = [
            "品牌", "包装", "营养成分表", "外卖", "餐厅", "菜单", "官网", "连锁",
            "麦当劳", "肯德基", "星巴克", "瑞幸", "喜茶", "奈雪",
            "brand", "package", "label", "restaurant", "menu", "official", "chain",
            "mcdonald", "kfc", "starbucks"
        ]
        return markers.contains { normalized.contains($0) }
    }
}

private struct TavilySearchRequest: Encodable {
    let query: String
    let searchDepth: String
    let topic: String
    let maxResults: Int
    let includeAnswer: Bool
    let includeRawContent: Bool
    let includeImages: Bool

    enum CodingKeys: String, CodingKey {
        case query
        case searchDepth = "search_depth"
        case topic
        case maxResults = "max_results"
        case includeAnswer = "include_answer"
        case includeRawContent = "include_raw_content"
        case includeImages = "include_images"
    }
}

private struct TavilySearchResponse: Decodable {
    let query: String?
    let answer: String?
    let results: [TavilySearchResult]

    enum CodingKeys: String, CodingKey {
        case query
        case answer
        case results
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        query = try container.decodeIfPresent(String.self, forKey: .query)
        answer = try container.decodeIfPresent(String.self, forKey: .answer)
        results = (try? container.decode([TavilySearchResult].self, forKey: .results)) ?? []
    }
}

private struct TavilySearchResult: Decodable {
    let title: String
    let url: String
    let content: String
    let score: Double?
}

enum TavilySearchError: LocalizedError {
    case emptyQuery
    case invalidURL
    case invalidResponse
    case httpStatus(Int, String)

    var errorDescription: String? {
        switch self {
        case .emptyQuery:
            return "Search query is empty."
        case .invalidURL:
            return "Tavily Search API URL is invalid."
        case .invalidResponse:
            return "Tavily Search API returned an invalid response."
        case .httpStatus(let status, let body):
            return body.isEmpty ? "Tavily Search API request failed: HTTP \(status)." : "Tavily Search API request failed: HTTP \(status). \(body)"
        }
    }
}

private extension String {
    var nonEmpty: String? {
        isEmpty ? nil : self
    }
}

private extension JSONEncoder {
    static var tavilyEncoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.withoutEscapingSlashes]
        return encoder
    }
}

private extension JSONDecoder {
    static var tavilyDecoder: JSONDecoder {
        JSONDecoder()
    }
}
