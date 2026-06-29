//
//  DeepSeekClient.swift
//  BHealth
//
//  Created by Codex on 2026-06-26.
//

import Foundation

struct DeepSeekClient {
    private let apiKeyStore: KeychainAPIKeyStore
    private let session: URLSession

    init(apiKeyStore: KeychainAPIKeyStore = .shared, session: URLSession = .shared) {
        self.apiKeyStore = apiKeyStore
        self.session = session
    }

    func complete(messages: [DeepSeekMessage], temperature: Double = 0.2) async throws -> String {
        let apiKey = try apiKeyStore.readAPIKey()
        guard let url = URL(string: "https://api.deepseek.com/chat/completions") else {
            throw DeepSeekError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 45
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

        let body = DeepSeekChatRequest(
            model: "deepseek-v4-flash",
            messages: messages,
            temperature: temperature,
            maxTokens: 900,
            responseFormat: DeepSeekResponseFormat(type: "json_object")
        )
        request.httpBody = try JSONEncoder.deepSeekEncoder.encode(body)

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw DeepSeekError.invalidResponse
        }

        guard (200..<300).contains(httpResponse.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw DeepSeekError.httpStatus(httpResponse.statusCode, body)
        }

        let decoded = try JSONDecoder.deepSeekDecoder.decode(DeepSeekChatResponse.self, from: data)
        guard let content = decoded.choices.first?.message.content, !content.isEmpty else {
            throw DeepSeekError.emptyResponse
        }

        return content
    }
}

struct DeepSeekMessage: Codable, Hashable {
    let role: String
    let content: String
}

private struct DeepSeekChatRequest: Encodable {
    let model: String
    let messages: [DeepSeekMessage]
    let temperature: Double
    let maxTokens: Int
    let responseFormat: DeepSeekResponseFormat

    enum CodingKeys: String, CodingKey {
        case model
        case messages
        case temperature
        case maxTokens = "max_tokens"
        case responseFormat = "response_format"
    }
}

private struct DeepSeekResponseFormat: Encodable {
    let type: String
}

private struct DeepSeekChatResponse: Decodable {
    let choices: [Choice]

    struct Choice: Decodable {
        let message: ResponseMessage
    }

    struct ResponseMessage: Decodable {
        let content: String
    }
}

enum DeepSeekError: LocalizedError {
    case invalidURL
    case invalidResponse
    case httpStatus(Int, String)
    case emptyResponse

    func message(language: AppLanguage) -> String {
        switch self {
        case .invalidURL:
            return AppText.text("DeepSeek API 地址无效。", "DeepSeek API URL is invalid.", language: language)
        case .invalidResponse:
            return AppText.text("DeepSeek API 返回格式无效。", "DeepSeek API returned an invalid response.", language: language)
        case .httpStatus(let status, let body):
            if body.isEmpty {
                return AppText.text("DeepSeek API 请求失败：HTTP \(status)。", "DeepSeek API request failed: HTTP \(status).", language: language)
            }
            return AppText.text("DeepSeek API 请求失败：HTTP \(status)。\(body)", "DeepSeek API request failed: HTTP \(status). \(body)", language: language)
        case .emptyResponse:
            return AppText.text("DeepSeek API 没有返回内容。", "DeepSeek API returned no content.", language: language)
        }
    }

    var errorDescription: String? {
        message(language: .chinese)
    }
}

private extension JSONEncoder {
    static var deepSeekEncoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.withoutEscapingSlashes]
        return encoder
    }
}

private extension JSONDecoder {
    static var deepSeekDecoder: JSONDecoder {
        JSONDecoder()
    }
}
