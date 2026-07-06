import Foundation

struct TavilySourceJSONConfig: Codable {
    var apiKey: String?
    var endpoint: String?
    var queryTemplate: String?
    var topic: String?
    var searchDepth: String?
    var timeRange: String?
    var maxResults: Int?
    var includeRawContent: Bool?

    enum CodingKeys: String, CodingKey {
        case apiKey
        case endpoint
        case queryTemplate
        case topic
        case searchDepth
        case searchDepthSnake = "search_depth"
        case timeRange
        case timeRangeSnake = "time_range"
        case maxResults
        case maxResultsSnake = "max_results"
        case includeRawContent
        case includeRawContentSnake = "include_raw_content"
    }

    init(
        apiKey: String? = nil,
        endpoint: String? = nil,
        queryTemplate: String? = nil,
        topic: String? = nil,
        searchDepth: String? = nil,
        timeRange: String? = nil,
        maxResults: Int? = nil,
        includeRawContent: Bool? = nil
    ) {
        self.apiKey = apiKey
        self.endpoint = endpoint
        self.queryTemplate = queryTemplate
        self.topic = topic
        self.searchDepth = searchDepth
        self.timeRange = timeRange
        self.maxResults = maxResults
        self.includeRawContent = includeRawContent
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        apiKey = try container.decodeIfPresent(String.self, forKey: .apiKey)
        endpoint = try container.decodeIfPresent(String.self, forKey: .endpoint)
        queryTemplate = try container.decodeIfPresent(String.self, forKey: .queryTemplate)
        topic = try container.decodeIfPresent(String.self, forKey: .topic)
        searchDepth = try container.decodeIfPresent(String.self, forKey: .searchDepth)
            ?? container.decodeIfPresent(String.self, forKey: .searchDepthSnake)
        timeRange = try container.decodeIfPresent(String.self, forKey: .timeRange)
            ?? container.decodeIfPresent(String.self, forKey: .timeRangeSnake)
        maxResults = try container.decodeIfPresent(Int.self, forKey: .maxResults)
            ?? container.decodeIfPresent(Int.self, forKey: .maxResultsSnake)
        includeRawContent = try Self.decodeRawContentFlag(from: container)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(apiKey, forKey: .apiKey)
        try container.encodeIfPresent(endpoint, forKey: .endpoint)
        try container.encodeIfPresent(queryTemplate, forKey: .queryTemplate)
        try container.encodeIfPresent(topic, forKey: .topic)
        try container.encodeIfPresent(searchDepth, forKey: .searchDepth)
        try container.encodeIfPresent(timeRange, forKey: .timeRange)
        try container.encodeIfPresent(maxResults, forKey: .maxResults)
        try container.encodeIfPresent(includeRawContent, forKey: .includeRawContent)
    }

    static func jsonString(
        apiKey: String,
        endpoint: String,
        queryTemplate: String,
        topic: TavilyTopic,
        searchDepth: TavilySearchDepth,
        timeRange: TavilyTimeRange,
        maxResults: Int,
        includeRawContent: Bool
    ) -> String {
        let config = TavilySourceJSONConfig(
            apiKey: apiKey,
            endpoint: endpoint.nilIfBlank ?? "https://api.tavily.com/search",
            queryTemplate: queryTemplate.nilIfBlank ?? "{competitor} {keywords}",
            topic: topic.rawValue,
            searchDepth: searchDepth.rawValue,
            timeRange: timeRange.apiValue ?? "none",
            maxResults: maxResults,
            includeRawContent: includeRawContent
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        guard let data = try? encoder.encode(config),
              let value = String(data: data, encoding: .utf8) else {
            return "{}"
        }
        return value
    }

    private static func decodeRawContentFlag(from container: KeyedDecodingContainer<CodingKeys>) throws -> Bool? {
        do {
            if let value = try container.decodeIfPresent(Bool.self, forKey: .includeRawContent) {
                return value
            }
        } catch {}
        do {
            if let value = try container.decodeIfPresent(Bool.self, forKey: .includeRawContentSnake) {
                return value
            }
        } catch {}
        do {
            if let value = try container.decodeIfPresent(String.self, forKey: .includeRawContent) {
                return rawContentStringToBool(value)
            }
        } catch {}
        do {
            if let value = try container.decodeIfPresent(String.self, forKey: .includeRawContentSnake) {
                return rawContentStringToBool(value)
            }
        } catch {}
        return nil
    }

    private static func rawContentStringToBool(_ value: String) -> Bool {
        let normalized = value.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        return normalized == "true" || normalized == "text" || normalized == "markdown"
    }
}
