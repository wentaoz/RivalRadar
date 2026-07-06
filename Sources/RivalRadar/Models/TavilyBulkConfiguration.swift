import Foundation

struct TavilyBulkConfiguration: Decodable {
    var tavily: TavilyBulkDefaults?
    var competitors: [String: TavilyCompetitorConfiguration]

    enum CodingKeys: String, CodingKey {
        case tavily
        case competitors
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        tavily = try container.decodeIfPresent(TavilyBulkDefaults.self, forKey: .tavily)

        if let keyedCompetitors = try? container.decode([String: TavilyCompetitorConfiguration].self, forKey: .competitors) {
            competitors = keyedCompetitors
            return
        }

        let listedCompetitors = try container.decode([TavilyListedCompetitorConfiguration].self, forKey: .competitors)
        var mappedCompetitors: [String: TavilyCompetitorConfiguration] = [:]
        for (index, value) in listedCompetitors.enumerated() {
            let rawKey = value.key(index: index)
            let uniqueKey = mappedCompetitors[rawKey] == nil ? rawKey : "\(rawKey)_\(index + 1)"
            mappedCompetitors[uniqueKey] = value.configuration
        }
        competitors = mappedCompetitors
    }
}

struct TavilyBulkDefaults: Decodable {
    var apiKey: String?
    var endpoint: String?
    var frequency: SourceFrequency?
    var customFrequencyMinutes: Int?
    var topic: TavilyTopic?
    var searchDepth: TavilySearchDepth?
    var timeRange: TavilyTimeRange?
    var maxResults: Int?
    var includeRawContent: Bool?

    enum CodingKeys: String, CodingKey {
        case apiKey
        case endpoint
        case frequency
        case customFrequencyMinutes
        case customFrequencyMinutesSnake = "custom_frequency_minutes"
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
        frequency: SourceFrequency? = nil,
        customFrequencyMinutes: Int? = nil,
        topic: TavilyTopic? = nil,
        searchDepth: TavilySearchDepth? = nil,
        timeRange: TavilyTimeRange? = nil,
        maxResults: Int? = nil,
        includeRawContent: Bool? = nil
    ) {
        self.apiKey = apiKey
        self.endpoint = endpoint
        self.frequency = frequency
        self.customFrequencyMinutes = customFrequencyMinutes
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
        frequency = try container.decodeIfPresent(SourceFrequency.self, forKey: .frequency)
        customFrequencyMinutes = try container.decodeIfPresent(Int.self, forKey: .customFrequencyMinutes)
            ?? container.decodeIfPresent(Int.self, forKey: .customFrequencyMinutesSnake)
        topic = try container.decodeIfPresent(TavilyTopic.self, forKey: .topic)
        searchDepth = try container.decodeIfPresent(TavilySearchDepth.self, forKey: .searchDepth)
            ?? container.decodeIfPresent(TavilySearchDepth.self, forKey: .searchDepthSnake)
        timeRange = try container.decodeIfPresent(TavilyTimeRange.self, forKey: .timeRange)
            ?? container.decodeIfPresent(TavilyTimeRange.self, forKey: .timeRangeSnake)
        maxResults = try container.decodeIfPresent(Int.self, forKey: .maxResults)
            ?? container.decodeIfPresent(Int.self, forKey: .maxResultsSnake)
        includeRawContent = try TavilyBulkDefaults.decodeRawContentFlag(from: container)
    }

    private static func decodeRawContentFlag(from container: KeyedDecodingContainer<CodingKeys>) throws -> Bool? {
        do {
            if let value = try container.decodeIfPresent(Bool.self, forKey: .includeRawContent) { return value }
        } catch {}
        do {
            if let value = try container.decodeIfPresent(Bool.self, forKey: .includeRawContentSnake) { return value }
        } catch {}
        do {
            if let value = try container.decodeIfPresent(String.self, forKey: .includeRawContent) {
                return ["true", "text", "markdown"].contains(value.lowercased())
            }
        } catch {}
        do {
            if let value = try container.decodeIfPresent(String.self, forKey: .includeRawContentSnake) {
                return ["true", "text", "markdown"].contains(value.lowercased())
            }
        } catch {}
        return nil
    }
}

struct TavilyCompetitorConfiguration: Decodable {
    var aliases: [String]
    var markets: [String]
    var focusMarket: String
    var languages: [String]
    var queryGroups: [String: [String]]
    var sourceProfiles: [String: TavilySourceProfileConfiguration]

    init(
        aliases: [String] = [],
        markets: [String] = [],
        focusMarket: String = "",
        languages: [String] = [],
        queryGroups: [String: [String]] = [:],
        sourceProfiles: [String: TavilySourceProfileConfiguration] = [:]
    ) {
        self.aliases = aliases
        self.markets = markets
        self.focusMarket = focusMarket
        self.languages = languages
        self.queryGroups = queryGroups
        self.sourceProfiles = sourceProfiles
    }

    enum CodingKeys: String, CodingKey {
        case aliases
        case markets
        case focusMarket
        case focusMarketSnake = "focus_market"
        case languages
        case queryGroups
        case queryGroupsSnake = "query_groups"
        case sourceProfiles
        case sourceProfilesSnake = "source_profiles"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        aliases = try container.decodeIfPresent([String].self, forKey: .aliases) ?? []
        markets = try container.decodeIfPresent([String].self, forKey: .markets) ?? []
        focusMarket = try container.decodeIfPresent(String.self, forKey: .focusMarket)
            ?? container.decodeIfPresent(String.self, forKey: .focusMarketSnake)
            ?? ""
        languages = try container.decodeIfPresent([String].self, forKey: .languages) ?? []
        queryGroups = try container.decodeIfPresent([String: [String]].self, forKey: .queryGroups)
            ?? container.decodeIfPresent([String: [String]].self, forKey: .queryGroupsSnake)
            ?? [:]
        sourceProfiles = try container.decodeIfPresent([String: TavilySourceProfileConfiguration].self, forKey: .sourceProfiles)
            ?? container.decodeIfPresent([String: TavilySourceProfileConfiguration].self, forKey: .sourceProfilesSnake)
            ?? [:]
    }
}

private struct TavilyListedCompetitorConfiguration: Decodable {
    var id: String?
    var key: String?
    var name: String?
    var configuration: TavilyCompetitorConfiguration

    enum CodingKeys: String, CodingKey {
        case id
        case key
        case name
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(String.self, forKey: .id)
        key = try container.decodeIfPresent(String.self, forKey: .key)
        name = try container.decodeIfPresent(String.self, forKey: .name)
        configuration = try TavilyCompetitorConfiguration(from: decoder)

        if configuration.aliases.isEmpty, let name = name?.nilIfBlank {
            configuration.aliases = [name]
        }
    }

    func key(index: Int) -> String {
        if let key = key?.nilIfBlank { return key }
        if let id = id?.nilIfBlank { return id }
        if let name = name?.nilIfBlank { return name.lowercased().replacingOccurrences(of: " ", with: "_") }
        if let alias = configuration.aliases.first?.nilIfBlank {
            return alias.lowercased().replacingOccurrences(of: " ", with: "_")
        }
        return "competitor_\(index + 1)"
    }
}

struct TavilySourceProfileConfiguration: Decodable {
    var includeDomains: [String]
    var excludeDomains: [String]
    var topic: TavilyTopic?
    var searchDepth: TavilySearchDepth?
    var timeRange: TavilyTimeRange?
    var maxResults: Int?

    enum CodingKeys: String, CodingKey {
        case includeDomains
        case includeDomainsSnake = "include_domains"
        case excludeDomains
        case excludeDomainsSnake = "exclude_domains"
        case topic
        case searchDepth
        case searchDepthSnake = "search_depth"
        case timeRange
        case timeRangeSnake = "time_range"
        case maxResults
        case maxResultsSnake = "max_results"
    }

    init(
        includeDomains: [String] = [],
        excludeDomains: [String] = [],
        topic: TavilyTopic? = nil,
        searchDepth: TavilySearchDepth? = nil,
        timeRange: TavilyTimeRange? = nil,
        maxResults: Int? = nil
    ) {
        self.includeDomains = includeDomains
        self.excludeDomains = excludeDomains
        self.topic = topic
        self.searchDepth = searchDepth
        self.timeRange = timeRange
        self.maxResults = maxResults
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        includeDomains = try container.decodeIfPresent([String].self, forKey: .includeDomains)
            ?? container.decodeIfPresent([String].self, forKey: .includeDomainsSnake)
            ?? []
        excludeDomains = try container.decodeIfPresent([String].self, forKey: .excludeDomains)
            ?? container.decodeIfPresent([String].self, forKey: .excludeDomainsSnake)
            ?? []
        topic = try container.decodeIfPresent(TavilyTopic.self, forKey: .topic)
        searchDepth = try container.decodeIfPresent(TavilySearchDepth.self, forKey: .searchDepth)
            ?? container.decodeIfPresent(TavilySearchDepth.self, forKey: .searchDepthSnake)
        timeRange = try container.decodeIfPresent(TavilyTimeRange.self, forKey: .timeRange)
            ?? container.decodeIfPresent(TavilyTimeRange.self, forKey: .timeRangeSnake)
        maxResults = try container.decodeIfPresent(Int.self, forKey: .maxResults)
            ?? container.decodeIfPresent(Int.self, forKey: .maxResultsSnake)
    }
}
