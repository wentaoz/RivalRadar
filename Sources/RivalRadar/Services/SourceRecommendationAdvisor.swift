import Foundation

struct SourceRecommendationAdvisor {
    private static let recommendationRequestTimeout: TimeInterval = 600

    private let chatClient = OpenAIChatClient()
    private let discoveryClient = TavilyDiscoveryClient()

    func recommendJSON(
        businessDescription: String,
        competitorCount: Int,
        tavilyAPIKey: String,
        configuration: OpenAIConfiguration
    ) async throws -> String {
        guard let description = businessDescription.nilIfBlank else {
            throw SourceRecommendationAdvisorError.missingBusinessDescription
        }
        guard let tavilyAPIKey = tavilyAPIKey.nilIfBlank else {
            throw SourceRecommendationAdvisorError.missingTavilyAPIKey
        }

        let cappedCount = min(max(competitorCount, 1), 30)
        let discoveryResults = try await discover(description: description, competitorCount: cappedCount, apiKey: tavilyAPIKey)
        let maxTokens = min(8_000, max(2_200, cappedCount * 340 + 1_100))
        let response = try await chatClient.complete(
            messages: [
                ChatMessage(role: "system", content: systemPrompt),
                ChatMessage(role: "user", content: userPrompt(description: description, competitorCount: cappedCount, discoveryResults: discoveryResults))
            ],
            configuration: configuration,
            temperature: 0.2,
            maxTokens: maxTokens,
            timeoutInterval: Self.recommendationRequestTimeout
        )
        return try await validatedRecommendationJSON(
            from: response,
            configuration: configuration,
            maxTokens: maxTokens
        )
    }

    private func discover(description: String, competitorCount: Int, apiKey: String) async throws -> [TavilyDiscoveryResult] {
        let queries = discoveryQueries(description: description, competitorCount: competitorCount)
        var results: [TavilyDiscoveryResult] = []
        var blockingErrors: [Error] = []

        await withTaskGroup(of: TavilyDiscoveryOutcome.self) { group in
            for query in queries {
                group.addTask {
                    do {
                        let queryResults = try await discoveryClient.search(
                            query: query,
                            apiKey: apiKey,
                            timeoutInterval: Self.recommendationRequestTimeout
                        )
                        return .success(queryResults.map { result in
                            var enriched = result
                            enriched.query = query
                            return enriched
                        })
                    } catch {
                        return .failure(error)
                    }
                }
            }

            for await outcome in group {
                switch outcome {
                case .success(let queryResults):
                    results.append(contentsOf: queryResults)
                case .failure(let error):
                    if !isTransientDiscoveryError(error) {
                        blockingErrors.append(error)
                    }
                }
            }
        }

        if results.isEmpty, let error = blockingErrors.first {
            throw error
        }
        return Array(results.prefix(24))
    }

    private func discoveryQueries(description: String, competitorCount: Int) -> [String] {
        [
            "\(description) competitors official websites",
            "\(description) loan app credit company market players",
            "\(description) regulator registered lending apps",
            "\(description) app reviews complaints news"
        ]
        .map { "\($0) top \(competitorCount)" }
    }

    private func isTransientDiscoveryError(_ error: Error) -> Bool {
        if let urlError = error as? URLError {
            switch urlError.code {
            case .timedOut, .networkConnectionLost, .notConnectedToInternet, .cannotFindHost, .cannotConnectToHost, .dnsLookupFailed:
                return true
            default:
                return false
            }
        }
        return error.localizedDescription.lowercased().contains("timed out")
    }

    private var systemPrompt: String {
        """
        你是竞品情报数据源架构师。你的任务是把业务自然语言描述和 Tavily 发现结果，转换成 RivalRadar 可导入的 JSON。
        必须只输出 JSON 对象，不要 Markdown，不要解释。

        JSON 结构必须是：
        {
          "recommendation_summary": "一句话说明推荐逻辑",
          "competitors": {
            "<competitor_key>": {
              "name": "竞品显示名",
              "aliases": [],
              "markets": [],
              "focus_market": "",
              "languages": [],
              "keywords": [],
              "notes": "",
              "sources": [
                {
                  "name": "数据源名称",
                  "type": "tavilySearch | webPage | rss | searchAPI",
                  "url": "",
                  "keywords": [],
                  "reason": "",
                  "frequency": "globalDefault",
                  "is_enabled": true,
                  "requires_login": false,
                  "include_domains": [],
                  "exclude_domains": [],
                  "query_group": "",
                  "source_profile": "",
                  "topic": "general | news | finance",
                  "search_depth": "basic",
                  "time_range": "week",
                  "max_results": 5,
                  "include_raw_content": true
                }
              ]
            }
          }
        }

        要求：
        - competitors 数量不要超过用户要求；如果公开资料不足，优先给高可信竞品。
        - 每个竞品给 1-3 个高价值 sources，至少给 1 个 tavilySearch；有明确官网时给 webPage；有明确 RSS/Atom 时给 rss。
        - tavilySearch 使用全局 Tavily API key，不要在 JSON 中写任何 api key、cookie 或 Chrome profile 路径。
        - 通用 searchAPI 只有在业务描述或发现结果明确提供 endpoint/供应商时才推荐；导入时应是未启用，所以 JSON 里写 "is_enabled": false。
        - 登录来源用 type="webPage" 且 requires_login=true 表示；导入时应是未启用，所以 JSON 里写 "is_enabled": false。
        - 公开网页、RSS、Tavily 来源默认 "is_enabled": true。
        - keywords 要包括当地语言、英文行业词、产品词、监管词、投诉词和增长词。
        - include_domains 只放域名，不放 URL，不要放 API key。
        - 不要编造内部系统、私有数据库、验证码后页面或不可访问来源。
        - 输出必须能被 JSONDecoder 解析，不能包含尾随逗号或注释。
        """
    }

    private func userPrompt(
        description: String,
        competitorCount: Int,
        discoveryResults: [TavilyDiscoveryResult]
    ) -> String {
        let discoveries = discoveryResults.enumerated().map { index, result in
            """
            \(index + 1). query: \(result.query)
               title: \(result.title.clipped(to: 140))
               url: \(result.url)
               domain: \(result.domain)
               snippet: \(result.content.clipped(to: 260))
            """
        }
        .joined(separator: "\n")

        return """
        业务描述：
        \(description)

        期望推荐竞品数量：\(competitorCount)

        Tavily 发现结果：
        \(discoveries.nilIfBlank ?? "Tavily 发现结果为空或部分请求超时，请仅基于业务描述生成保守推荐。")

        请基于以上信息生成 RivalRadar 通用数据源推荐 JSON。优先推荐能够长期自动监控的公开来源。
        """
    }

    private func validatedRecommendationJSON(
        from response: String,
        configuration: OpenAIConfiguration,
        maxTokens: Int
    ) async throws -> String {
        let initial = decodeFirstValidCandidate(from: SourceRecommendationJSONRepair.candidates(from: response))
        if let json = initial.json {
            return json
        }

        let repairResponse: String
        do {
            repairResponse = try await chatClient.complete(
                messages: [
                    ChatMessage(role: "system", content: jsonRepairSystemPrompt),
                    ChatMessage(role: "user", content: jsonRepairUserPrompt(invalidJSON: response))
                ],
                configuration: configuration,
                temperature: 0,
                maxTokens: maxTokens,
                timeoutInterval: Self.recommendationRequestTimeout
            )
        } catch {
            throw SourceRecommendationAdvisorError.invalidAIJSON(
                "原始返回无法解析：\(initial.errorMessage ?? "未知错误")；自动修复请求失败：\(error.localizedDescription)"
            )
        }

        let repaired = decodeFirstValidCandidate(from: SourceRecommendationJSONRepair.candidates(from: repairResponse))
        if let json = repaired.json {
            return json
        }

        throw SourceRecommendationAdvisorError.invalidAIJSON(
            "原始返回无法解析：\(initial.errorMessage ?? "未知错误")；自动修复后仍无法解析：\(repaired.errorMessage ?? "未知错误")"
        )
    }

    private func decodeFirstValidCandidate(from candidates: [String]) -> (json: String?, errorMessage: String?) {
        var lastError: String?
        for candidate in candidates {
            guard let data = candidate.data(using: .utf8) else {
                lastError = "模型返回文本编码无效"
                continue
            }
            do {
                _ = try JSONDecoder().decode(SourceRecommendationConfiguration.self, from: data)
                return (candidate, nil)
            } catch {
                lastError = Self.describeDecodeError(error)
            }
        }
        return (nil, lastError ?? "未找到 JSON 对象")
    }

    private var jsonRepairSystemPrompt: String {
        """
        你是严格的 JSON 修复器。你的任务是把输入修复成合法 JSON 对象。
        必须只输出 JSON，不要 Markdown，不要解释。
        不要新增 API key、cookie、Chrome profile 或任何凭证。
        保留原有业务含义和字段，必要时只修复引号、逗号、括号、转义和 JSON 结构。
        JSON 根节点必须包含 competitors 对象。
        """
    }

    private func jsonRepairUserPrompt(invalidJSON: String) -> String {
        """
        请修复下面这段 RivalRadar 数据源推荐 JSON，使其成为可以被 JSONDecoder 解析的合法 JSON：

        \(invalidJSON.clipped(to: 80_000))
        """
    }

    private static func describeDecodeError(_ error: Error) -> String {
        func path(_ codingPath: [CodingKey]) -> String {
            let value = codingPath.map(\.stringValue).joined(separator: ".")
            return value.isEmpty ? "JSON 根节点" : value
        }

        switch error {
        case let DecodingError.dataCorrupted(context):
            return "\(path(context.codingPath))：\(context.debugDescription)"
        case let DecodingError.typeMismatch(type, context):
            return "\(path(context.codingPath))：字段类型不匹配，期望 \(type)。\(context.debugDescription)"
        case let DecodingError.valueNotFound(type, context):
            return "\(path(context.codingPath))：缺少必填值，期望 \(type)。\(context.debugDescription)"
        case let DecodingError.keyNotFound(key, context):
            return "\(path(context.codingPath))：缺少字段 \(key.stringValue)。\(context.debugDescription)"
        default:
            return error.localizedDescription
        }
    }
}

enum SourceRecommendationJSONRepair {
    static func candidates(from value: String) -> [String] {
        let stripped = stripCodeFences(value)
        let extracted = extractJSONObject(from: stripped) ?? stripped
        let normalized = normalize(extracted)
        let completed = completeTrailingContainers(normalized)
        let repaired = removeTrailingCommas(
            quoteUnquotedKeys(
                escapeNewlinesInsideStrings(
                    removeComments(completed)
                )
            )
        )

        return unique([
            extracted,
            normalized,
            completed,
            repaired
        ])
    }

    private static func stripCodeFences(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\u{feff}", with: "")
            .components(separatedBy: .newlines)
            .filter { line in
                let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
                return !trimmed.hasPrefix("```")
            }
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func extractJSONObject(from value: String) -> String? {
        guard let start = value.firstIndex(of: "{") else { return nil }

        var depth = 0
        var inString = false
        var isEscaped = false
        var index = start

        while index < value.endIndex {
            let character = value[index]
            if inString {
                if isEscaped {
                    isEscaped = false
                } else if character == "\\" {
                    isEscaped = true
                } else if character == "\"" {
                    inString = false
                }
            } else {
                if character == "\"" {
                    inString = true
                } else if character == "{" {
                    depth += 1
                } else if character == "}" {
                    depth -= 1
                    if depth == 0 {
                        return String(value[start...index])
                    }
                }
            }
            index = value.index(after: index)
        }

        return String(value[start...])
    }

    private static func normalize(_ value: String) -> String {
        value
            .replacingOccurrences(of: "“", with: "\"")
            .replacingOccurrences(of: "”", with: "\"")
            .replacingOccurrences(of: "‘", with: "'")
            .replacingOccurrences(of: "’", with: "'")
            .replacingOccurrences(of: "\u{200b}", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func removeComments(_ value: String) -> String {
        var result = ""
        var index = value.startIndex
        var inString = false
        var isEscaped = false

        while index < value.endIndex {
            let character = value[index]
            let nextIndex = value.index(after: index)
            let next = nextIndex < value.endIndex ? value[nextIndex] : nil

            if inString {
                result.append(character)
                if isEscaped {
                    isEscaped = false
                } else if character == "\\" {
                    isEscaped = true
                } else if character == "\"" {
                    inString = false
                }
                index = nextIndex
                continue
            }

            if character == "\"" {
                inString = true
                result.append(character)
                index = nextIndex
                continue
            }

            if character == "/", next == "/" {
                index = nextIndex
                while index < value.endIndex, value[index] != "\n" {
                    index = value.index(after: index)
                }
                continue
            }

            if character == "/", next == "*" {
                index = value.index(after: nextIndex)
                while index < value.endIndex {
                    let current = value[index]
                    let after = value.index(after: index)
                    if current == "*", after < value.endIndex, value[after] == "/" {
                        index = value.index(after: after)
                        break
                    }
                    index = after
                }
                continue
            }

            result.append(character)
            index = nextIndex
        }

        return result
    }

    private static func escapeNewlinesInsideStrings(_ value: String) -> String {
        var result = ""
        var inString = false
        var isEscaped = false

        for character in value {
            if inString {
                if isEscaped {
                    result.append(character)
                    isEscaped = false
                } else if character == "\\" {
                    result.append(character)
                    isEscaped = true
                } else if character == "\"" {
                    result.append(character)
                    inString = false
                } else if character == "\n" {
                    result.append("\\n")
                } else if character == "\r" {
                    result.append("\\r")
                } else {
                    result.append(character)
                }
            } else {
                result.append(character)
                if character == "\"" {
                    inString = true
                }
            }
        }

        return result
    }

    private static func quoteUnquotedKeys(_ value: String) -> String {
        replacing(
            pattern: #"([,{]\s*)([A-Za-z_][A-Za-z0-9_-]*)(\s*:)"#,
            in: value,
            template: #"$1"$2"$3"#
        )
    }

    private static func removeTrailingCommas(_ value: String) -> String {
        replacing(pattern: #",(\s*[}\]])"#, in: value, template: "$1")
    }

    private static func completeTrailingContainers(_ value: String) -> String {
        var stack: [Character] = []
        var inString = false
        var isEscaped = false

        for character in value {
            if inString {
                if isEscaped {
                    isEscaped = false
                } else if character == "\\" {
                    isEscaped = true
                } else if character == "\"" {
                    inString = false
                }
                continue
            }

            if character == "\"" {
                inString = true
            } else if character == "{" {
                stack.append("}")
            } else if character == "[" {
                stack.append("]")
            } else if (character == "}" || character == "]"), stack.last == character {
                stack.removeLast()
            }
        }

        var completed = value
        if inString {
            completed.append("\"")
        }
        completed.append(contentsOf: stack.reversed())
        return completed
    }

    private static func replacing(pattern: String, in value: String, template: String) -> String {
        do {
            let regex = try NSRegularExpression(pattern: pattern)
            let range = NSRange(value.startIndex..<value.endIndex, in: value)
            return regex.stringByReplacingMatches(in: value, range: range, withTemplate: template)
        } catch {
            return value
        }
    }

    private static func unique(_ values: [String]) -> [String] {
        var seen = Set<String>()
        return values.compactMap { value in
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return nil }
            guard !seen.contains(trimmed) else { return nil }
            seen.insert(trimmed)
            return trimmed
        }
    }
}

enum SourceRecommendationAdvisorError: LocalizedError {
    case missingBusinessDescription
    case missingTavilyAPIKey
    case tavilyHTTP(statusCode: Int, body: String)
    case invalidTavilyResponse(String)
    case invalidAIJSON(String)

    var errorDescription: String? {
        switch self {
        case .missingBusinessDescription:
            return "请先输入业务描述"
        case .missingTavilyAPIKey:
            return "请先在设置页填写 Tavily Search API Key"
        case .tavilyHTTP(let statusCode, let body):
            let suffix = body.nilIfBlank.map { "：\($0.clipped(to: 400))" } ?? ""
            return "Tavily 发现搜索失败：HTTP \(statusCode)\(suffix)"
        case .invalidTavilyResponse(let detail):
            return "Tavily 发现搜索返回格式无法解析：\(detail.clipped(to: 400))"
        case .invalidAIJSON(let message):
            return "AI 返回的推荐 JSON 无法解析：\(message)"
        }
    }
}

struct TavilyDiscoveryClient {
    func search(
        query: String,
        apiKey: String,
        endpoint: String = "https://api.tavily.com/search",
        timeoutInterval: TimeInterval = 600
    ) async throws -> [TavilyDiscoveryResult] {
        guard let url = URL(string: endpoint) else {
            throw CollectorError.invalidURL(endpoint)
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = timeoutInterval
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONEncoder().encode(
            TavilyDiscoveryRequest(
                query: query,
                searchDepth: TavilySearchDepth.basic.rawValue,
                topic: TavilyTopic.general.rawValue,
                maxResults: 5,
                includeRawContent: false,
                includeAnswer: false,
                includeImages: false
            )
        )

        let (data, response) = try await URLSession.shared.data(for: request)
        if let httpResponse = response as? HTTPURLResponse,
           !(200...299).contains(httpResponse.statusCode) {
            throw SourceRecommendationAdvisorError.tavilyHTTP(
                statusCode: httpResponse.statusCode,
                body: apiErrorMessage(from: data)
            )
        }

        do {
            let decoded = try JSONDecoder().decode(TavilyDiscoveryResponse.self, from: data)
            return decoded.results.compactMap { item in
                guard let title = item.title.nilIfBlank,
                      let url = item.url.nilIfBlank else {
                    return nil
                }
                return TavilyDiscoveryResult(
                    query: query,
                    title: title,
                    url: url,
                    content: item.content ?? "",
                    domain: URLNormalizer.domain(from: url)
                )
            }
        } catch {
            throw SourceRecommendationAdvisorError.invalidTavilyResponse(error.localizedDescription)
        }
    }

    private func apiErrorMessage(from data: Data) -> String {
        guard !data.isEmpty else { return "" }
        if let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            if let error = object["error"] as? [String: Any],
               let message = error["message"] as? String {
                return message
            }
            if let message = object["message"] as? String {
                return message
            }
            if let detail = object["detail"] as? String {
                return detail
            }
        }
        return String(data: data, encoding: .utf8) ?? ""
    }
}

struct TavilyDiscoveryResult {
    var query: String
    var title: String
    var url: String
    var content: String
    var domain: String
}

private enum TavilyDiscoveryOutcome {
    case success([TavilyDiscoveryResult])
    case failure(Error)
}

private struct TavilyDiscoveryRequest: Encodable {
    var query: String
    var searchDepth: String
    var topic: String
    var maxResults: Int
    var includeRawContent: Bool
    var includeAnswer: Bool
    var includeImages: Bool

    enum CodingKeys: String, CodingKey {
        case query
        case searchDepth = "search_depth"
        case topic
        case maxResults = "max_results"
        case includeRawContent = "include_raw_content"
        case includeAnswer = "include_answer"
        case includeImages = "include_images"
    }
}

private struct TavilyDiscoveryResponse: Decodable {
    struct Result: Decodable {
        var title: String
        var url: String
        var content: String?
    }

    var results: [Result]
}
