import Foundation

struct OpenAIConfiguration {
    var apiKey: String
    var baseURL: String
    var model: String
}

struct ChatMessage: Codable {
    var role: String
    var content: String
}

struct OpenAIChatClient {
    enum ClientError: LocalizedError {
        case missingAPIKey
        case invalidBaseURL
        case invalidResponse
        case apiError(String)

        var errorDescription: String? {
            switch self {
            case .missingAPIKey:
                return "请先填写接口密钥"
            case .invalidBaseURL:
                return "接口地址无效"
            case .invalidResponse:
                return "模型返回格式无法解析"
            case .apiError(let message):
                return message
            }
        }
    }

    func complete(
        messages: [ChatMessage],
        configuration: OpenAIConfiguration,
        temperature: Double = 0.15,
        maxTokens: Int = 900,
        timeoutInterval: TimeInterval = 600
    ) async throws -> String {
        guard !configuration.apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ClientError.missingAPIKey
        }
        let endpoint = try chatCompletionsURL(baseURL: configuration.baseURL)

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = timeoutInterval
        request.setValue("Bearer \(configuration.apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(
            ChatCompletionRequest(
                model: configuration.model,
                messages: messages,
                temperature: temperature,
                maxTokens: maxTokens,
                stream: false
            )
        )

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch let error as URLError where error.code == .timedOut {
            throw ClientError.apiError("AI 请求超时：模型生成时间过长，请减少推荐竞品数量或稍后重试")
        } catch {
            throw error
        }
        if let httpResponse = response as? HTTPURLResponse,
           !(200...299).contains(httpResponse.statusCode) {
            let message = parseAPIError(from: data) ?? "AI 请求失败：HTTP \(httpResponse.statusCode)"
            throw ClientError.apiError(message)
        }

        let decoded = try JSONDecoder().decode(ChatCompletionResponse.self, from: data)
        guard let content = decoded.choices.first?.message.content?.nilIfBlank else {
            throw ClientError.invalidResponse
        }
        return content
    }

    func chatCompletionsURL(baseURL: String) throws -> URL {
        guard let endpoint = URL(string: normalizedBaseURL(baseURL) + "/chat/completions") else {
            throw ClientError.invalidBaseURL
        }
        return endpoint
    }

    private func normalizedBaseURL(_ value: String) -> String {
        var result = value.trimmingCharacters(in: .whitespacesAndNewlines)
        while result.hasSuffix("/") {
            result.removeLast()
        }
        if result.hasSuffix("/v1") {
            return result
        }
        return result + "/v1"
    }

    private func parseAPIError(from data: Data) -> String? {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return String(data: data, encoding: .utf8)
        }
        if let error = object["error"] as? [String: Any],
           let message = error["message"] as? String {
            return message
        }
        return object["message"] as? String
    }
}

private struct ChatCompletionRequest: Codable {
    var model: String
    var messages: [ChatMessage]
    var temperature: Double
    var maxTokens: Int
    var stream: Bool

    enum CodingKeys: String, CodingKey {
        case model
        case messages
        case temperature
        case maxTokens = "max_tokens"
        case stream
    }
}

private struct ChatCompletionResponse: Codable {
    struct Choice: Codable {
        struct Message: Codable {
            var content: String?
        }
        var message: Message
    }
    var choices: [Choice]
}
