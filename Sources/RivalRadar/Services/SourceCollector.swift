import Foundation

enum CollectorError: LocalizedError {
    case invalidURL(String)
    case missingSearchAPIKey(String)
    case apiHTTPError(service: String, statusCode: Int, body: String)
    case invalidSearchResponse(service: String, detail: String)

    var errorDescription: String? {
        switch self {
        case .invalidURL(let value):
            return "URL 无效：\(value)"
        case .missingSearchAPIKey(let service):
            return "\(service) 接口密钥未配置"
        case .apiHTTPError(let service, let statusCode, let body):
            let suffix = body.nilIfBlank.map { "：\($0.clipped(to: 400))" } ?? ""
            return "\(service) 请求失败：HTTP \(statusCode)\(suffix)"
        case .invalidSearchResponse(let service, let detail):
            return "\(service) 返回格式无法解析：\(detail.clipped(to: 400))"
        }
    }
}

final class SourceCollector {
    private static let externalRequestTimeout: TimeInterval = 600

    private let chromeSessionReader = ChromeSessionReader()

    func collect(source: IntelligenceSource, competitor: Competitor) async throws -> [RawCollectedItem] {
        switch source.type {
        case .webPage:
            return [try await collectWebPage(source: source)]
        case .rss:
            return try await collectRSS(source: source)
        case .searchAPI:
            return try await collectSearchAPI(source: source, competitor: competitor)
        case .tavilySearch:
            return try await collectTavilySearch(source: source, competitor: competitor)
        }
    }

    private func collectWebPage(source: IntelligenceSource) async throws -> RawCollectedItem {
        guard let url = URL(string: source.url.nilIfBlank ?? "") else {
            throw CollectorError.invalidURL(source.url)
        }
        let request = try request(for: url, source: source)
        let (data, _) = try await URLSession.shared.data(for: request)
        return HTMLExtractor.extract(from: data, sourceURL: url)
    }

    private func collectRSS(source: IntelligenceSource) async throws -> [RawCollectedItem] {
        guard let url = URL(string: source.url.nilIfBlank ?? "") else {
            throw CollectorError.invalidURL(source.url)
        }
        let request = try request(for: url, source: source)
        let (data, _) = try await URLSession.shared.data(for: request)
        return RSSFeedParser(feedURL: url).parse(data: data)
    }

    private func collectSearchAPI(source: IntelligenceSource, competitor: Competitor) async throws -> [RawCollectedItem] {
        let query = source.searchQueryTemplate
            .replacingOccurrences(of: "{competitor}", with: competitor.name)
            .replacingOccurrences(of: "{aliases}", with: competitor.aliases.joined(separator: " "))
            .replacingOccurrences(of: "{keywords}", with: source.keywords.joined(separator: " "))
            .replacingOccurrences(of: "{languages}", with: source.tavilyLanguageHints.joined(separator: " "))
            .replacingOccurrences(of: "{market}", with: source.tavilyCountry)
            .replacingOccurrences(of: "{focus_market}", with: source.tavilyCountry)
            .replacingOccurrences(of: "{query_group}", with: source.tavilyQueryGroup)
            .replacingOccurrences(of: "{source_profile}", with: source.tavilySourceProfile)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        let endpoint = source.searchEndpoint.nilIfBlank ?? source.url
        guard var components = URLComponents(string: endpoint) else {
            throw CollectorError.invalidURL(endpoint)
        }

        if endpoint.contains("{query}") {
            guard let encodedQuery = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else {
                throw CollectorError.invalidURL(endpoint)
            }
            guard let url = URL(string: endpoint.replacingOccurrences(of: "{query}", with: encodedQuery)) else {
                throw CollectorError.invalidURL(endpoint)
            }
            return try await requestSearch(url: url, source: source)
        }

        var queryItems = components.queryItems ?? []
        if !query.isEmpty, !queryItems.contains(where: { $0.name == "q" || $0.name == "query" }) {
            queryItems.append(URLQueryItem(name: "q", value: query))
        }
        components.queryItems = queryItems

        guard let url = components.url else {
            throw CollectorError.invalidURL(endpoint)
        }
        return try await requestSearch(url: url, source: source)
    }

    private func collectTavilySearch(source: IntelligenceSource, competitor: Competitor) async throws -> [RawCollectedItem] {
        let query = source.searchQueryTemplate
            .replacingOccurrences(of: "{competitor}", with: competitor.name)
            .replacingOccurrences(of: "{keywords}", with: source.keywords.joined(separator: " "))
            .trimmingCharacters(in: .whitespacesAndNewlines)

        let endpoint = source.searchEndpoint.nilIfBlank ?? source.url.nilIfBlank ?? "https://api.tavily.com/search"
        guard let url = URL(string: endpoint) else {
            throw CollectorError.invalidURL(endpoint)
        }
        guard let apiKey = source.searchAPIKey.nilIfBlank else {
            throw CollectorError.missingSearchAPIKey("Tavily Search")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = Self.externalRequestTimeout
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

        let body = TavilySearchRequest(
            query: query.isEmpty ? "\(competitor.name) \(source.keywords.joined(separator: " "))" : query,
            searchDepth: source.tavilySearchDepth.rawValue,
            topic: source.tavilyTopic.rawValue,
            timeRange: source.tavilyTimeRange.apiValue,
            maxResults: source.tavilyMaxResults,
            includeAnswer: false,
            includeRawContent: source.tavilyIncludeRawContent ? .text : .disabled,
            includeImages: false,
            includeUsage: true,
            includeDomains: source.tavilyIncludeDomains,
            excludeDomains: source.tavilyExcludeDomains,
            country: source.tavilyTopic == .general ? source.tavilyCountry.nilIfBlank : nil
        )
        request.httpBody = try JSONEncoder().encode(body)

        let (data, response) = try await URLSession.shared.data(for: request)
        if let httpResponse = response as? HTTPURLResponse,
           !(200...299).contains(httpResponse.statusCode) {
            throw CollectorError.apiHTTPError(
                service: "Tavily Search",
                statusCode: httpResponse.statusCode,
                body: apiErrorMessage(from: data)
            )
        }

        let decoded: TavilySearchResponse
        do {
            decoded = try JSONDecoder().decode(TavilySearchResponse.self, from: data)
        } catch {
            throw CollectorError.invalidSearchResponse(service: "Tavily Search", detail: error.localizedDescription)
        }
        return decoded.results.compactMap { result in
            guard let title = result.title.nilIfBlank,
                  let url = result.url.nilIfBlank else {
                return nil
            }
            return RawCollectedItem(
                title: title,
                url: url,
                content: (result.rawContent?.nilIfBlank ?? result.content?.nilIfBlank ?? title).clipped(to: 20_000),
                publishedAt: nil,
                sourceName: URLNormalizer.domain(from: url)
            )
        }
    }

    private func requestSearch(url: URL, source: IntelligenceSource) async throws -> [RawCollectedItem] {
        var request = URLRequest(url: url)
        request.timeoutInterval = Self.externalRequestTimeout
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let apiKey = source.searchAPIKey.nilIfBlank {
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        }

        let (data, response) = try await URLSession.shared.data(for: request)
        if let httpResponse = response as? HTTPURLResponse,
           !(200...299).contains(httpResponse.statusCode) {
            throw CollectorError.apiHTTPError(
                service: "通用搜索 API",
                statusCode: httpResponse.statusCode,
                body: apiErrorMessage(from: data)
            )
        }

        let json: Any
        do {
            json = try JSONSerialization.jsonObject(with: data)
        } catch {
            throw CollectorError.invalidSearchResponse(service: "通用搜索 API", detail: error.localizedDescription)
        }

        let dictionaries = JSONSearchExtractor.findCandidateDictionaries(in: json)
        let items = dictionaries.compactMap { dictionary -> RawCollectedItem? in
            let title = JSONSearchExtractor.string(at: source.searchTitlePath, in: dictionary)
                ?? JSONSearchExtractor.firstString(named: ["title", "name", "headline"], in: dictionary)
            let url = JSONSearchExtractor.string(at: source.searchURLPath, in: dictionary)
                ?? JSONSearchExtractor.firstString(named: ["url", "link", "href"], in: dictionary)
            let content = JSONSearchExtractor.firstString(named: ["snippet", "description", "summary", "content"], in: dictionary)
                ?? title

            guard let title = title?.nilIfBlank,
                  let url = url?.nilIfBlank else {
                return nil
            }

            return RawCollectedItem(
                title: title,
                url: url,
                content: content ?? title,
                publishedAt: DateParsing.parse(JSONSearchExtractor.firstString(named: ["publishedAt", "published", "date"], in: dictionary)),
                sourceName: URLNormalizer.domain(from: url)
            )
        }

        return items
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

    private func request(for url: URL, source: IntelligenceSource) throws -> URLRequest {
        var request = URLRequest(url: url)
        request.timeoutInterval = Self.externalRequestTimeout
        request.setValue("Mozilla/5.0 RivalRadar/1.0", forHTTPHeaderField: "User-Agent")

        if source.requiresLogin, let profilePath = source.chromeProfilePath.nilIfBlank {
            let cookieHeader = try chromeSessionReader.cookieHeader(for: url, profilePath: profilePath)
            if let cookieHeader {
                request.setValue(cookieHeader, forHTTPHeaderField: "Cookie")
            }
        }

        return request
    }
}

private struct TavilySearchRequest: Encodable {
    var query: String
    var searchDepth: String
    var topic: String
    var timeRange: String?
    var maxResults: Int
    var includeAnswer: Bool
    var includeRawContent: TavilyRawContentOption
    var includeImages: Bool
    var includeUsage: Bool
    var includeDomains: [String]
    var excludeDomains: [String]
    var country: String?

    enum CodingKeys: String, CodingKey {
        case query
        case searchDepth = "search_depth"
        case topic
        case timeRange = "time_range"
        case maxResults = "max_results"
        case includeAnswer = "include_answer"
        case includeRawContent = "include_raw_content"
        case includeImages = "include_images"
        case includeUsage = "include_usage"
        case includeDomains = "include_domains"
        case excludeDomains = "exclude_domains"
        case country
    }
}

private enum TavilyRawContentOption: Encodable {
    case disabled
    case text

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .disabled:
            try container.encode(false)
        case .text:
            try container.encode("text")
        }
    }
}

private struct TavilySearchResponse: Decodable {
    struct Result: Decodable {
        var title: String
        var url: String
        var content: String?
        var rawContent: String?

        enum CodingKeys: String, CodingKey {
            case title
            case url
            case content
            case rawContent = "raw_content"
        }
    }

    var results: [Result]
}

enum JSONSearchExtractor {
    static func findCandidateDictionaries(in value: Any) -> [[String: Any]] {
        if let array = value as? [[String: Any]] {
            return array
        }
        if let dictionary = value as? [String: Any] {
            let likelyArrays = ["items", "results", "data", "webPages", "organic_results"]
            for key in likelyArrays {
                if let nested = dictionary[key] {
                    let found = findCandidateDictionaries(in: nested)
                    if !found.isEmpty { return found }
                }
            }
            return dictionary.values.flatMap { findCandidateDictionaries(in: $0) }
        }
        if let array = value as? [Any] {
            return array.flatMap { findCandidateDictionaries(in: $0) }
        }
        return []
    }

    static func string(at path: String, in dictionary: [String: Any]) -> String? {
        let parts = path.split(separator: ".").map(String.init)
        guard !parts.isEmpty else { return nil }
        var current: Any? = dictionary
        for part in parts {
            if let dict = current as? [String: Any] {
                current = dict[part]
            } else {
                return nil
            }
        }
        return current as? String
    }

    static func firstString(named names: [String], in dictionary: [String: Any]) -> String? {
        for name in names {
            if let value = dictionary[name] as? String, !value.isEmpty {
                return value
            }
        }
        for value in dictionary.values {
            if let nested = value as? [String: Any],
               let found = firstString(named: names, in: nested) {
                return found
            }
        }
        return nil
    }
}
