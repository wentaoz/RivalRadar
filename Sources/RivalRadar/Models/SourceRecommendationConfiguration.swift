import Foundation

struct SourceRecommendationConfiguration: Decodable {
    var recommendationSummary: String
    var competitors: [String: RecommendedCompetitorConfiguration]

    enum CodingKeys: String, CodingKey {
        case recommendationSummary
        case recommendationSummarySnake = "recommendation_summary"
        case summary
        case competitors
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        recommendationSummary = try container.decodeIfPresent(String.self, forKey: .recommendationSummary)
            ?? container.decodeIfPresent(String.self, forKey: .recommendationSummarySnake)
            ?? container.decodeIfPresent(String.self, forKey: .summary)
            ?? ""

        if let keyedCompetitors = try? container.decode([String: RecommendedCompetitorConfiguration].self, forKey: .competitors) {
            competitors = keyedCompetitors
            return
        }

        let listedCompetitors = try container.decode([RecommendedListedCompetitorConfiguration].self, forKey: .competitors)
        var mappedCompetitors: [String: RecommendedCompetitorConfiguration] = [:]
        for (index, value) in listedCompetitors.enumerated() {
            let rawKey = value.key(index: index)
            let uniqueKey = mappedCompetitors[rawKey] == nil ? rawKey : "\(rawKey)_\(index + 1)"
            mappedCompetitors[uniqueKey] = value.configuration
        }
        competitors = mappedCompetitors
    }
}

struct RecommendedCompetitorConfiguration: Decodable {
    var name: String?
    var aliases: [String]
    var markets: [String]
    var focusMarket: String
    var languages: [String]
    var keywords: [String]
    var notes: String
    var sources: [RecommendedSourceConfiguration]

    enum CodingKeys: String, CodingKey {
        case name
        case aliases
        case markets
        case focusMarket
        case focusMarketSnake = "focus_market"
        case languages
        case keywords
        case notes
        case sources
        case dataSources
        case dataSourcesSnake = "data_sources"
        case queryGroups
        case queryGroupsSnake = "query_groups"
        case sourceProfiles
        case sourceProfilesSnake = "source_profiles"
    }

    init(
        name: String? = nil,
        aliases: [String] = [],
        markets: [String] = [],
        focusMarket: String = "",
        languages: [String] = [],
        keywords: [String] = [],
        notes: String = "",
        sources: [RecommendedSourceConfiguration] = []
    ) {
        self.name = name
        self.aliases = aliases
        self.markets = markets
        self.focusMarket = focusMarket
        self.languages = languages
        self.keywords = keywords
        self.notes = notes
        self.sources = sources
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try FlexibleJSON.string(from: container, keys: [.name])
        aliases = try FlexibleJSON.stringList(from: container, keys: [.aliases])
        markets = try FlexibleJSON.stringList(from: container, keys: [.markets])
        focusMarket = try FlexibleJSON.string(from: container, keys: [.focusMarket, .focusMarketSnake]) ?? ""
        languages = try FlexibleJSON.stringList(from: container, keys: [.languages])
        keywords = try FlexibleJSON.stringList(from: container, keys: [.keywords])
        notes = try FlexibleJSON.string(from: container, keys: [.notes]) ?? ""

        let providedSources = try container.decodeIfPresent([RecommendedSourceConfiguration].self, forKey: .sources)
            ?? container.decodeIfPresent([RecommendedSourceConfiguration].self, forKey: .dataSources)
            ?? container.decodeIfPresent([RecommendedSourceConfiguration].self, forKey: .dataSourcesSnake)
            ?? []
        if !providedSources.isEmpty {
            sources = providedSources
            return
        }

        let queryGroups = try container.decodeIfPresent([String: [String]].self, forKey: .queryGroups)
            ?? container.decodeIfPresent([String: [String]].self, forKey: .queryGroupsSnake)
            ?? [:]
        let sourceProfiles = try container.decodeIfPresent([String: TavilySourceProfileConfiguration].self, forKey: .sourceProfiles)
            ?? container.decodeIfPresent([String: TavilySourceProfileConfiguration].self, forKey: .sourceProfilesSnake)
            ?? [:]
        sources = Self.tavilySourcesFromLegacyShape(queryGroups: queryGroups, sourceProfiles: sourceProfiles)
    }

    private static func tavilySourcesFromLegacyShape(
        queryGroups: [String: [String]],
        sourceProfiles: [String: TavilySourceProfileConfiguration]
    ) -> [RecommendedSourceConfiguration] {
        guard !queryGroups.isEmpty else { return [] }
        let profiles = sourceProfiles.isEmpty
            ? ["default": TavilySourceProfileConfiguration()]
            : sourceProfiles

        var result: [RecommendedSourceConfiguration] = []
        for (groupName, groupKeywords) in queryGroups.sorted(by: { $0.key < $1.key }) {
            for (profileName, profile) in profiles.sorted(by: { $0.key < $1.key }) {
                result.append(
                    RecommendedSourceConfiguration(
                        name: nil,
                        type: .tavilySearch,
                        url: "https://api.tavily.com/search",
                        keywords: groupKeywords,
                        frequency: .globalDefault,
                        customFrequencyMinutes: nil,
                        requiresLogin: false,
                        isEnabled: true,
                        reason: "由旧版 Tavily query_groups/source_profiles 自动转换",
                        searchEndpoint: "https://api.tavily.com/search",
                        searchQueryTemplate: nil,
                        searchTitlePath: nil,
                        searchURLPath: nil,
                        tavilyTopic: profile.topic,
                        tavilySearchDepth: profile.searchDepth,
                        tavilyMaxResults: profile.maxResults,
                        tavilyTimeRange: profile.timeRange,
                        tavilyIncludeRawContent: nil,
                        includeDomains: profile.includeDomains,
                        excludeDomains: profile.excludeDomains,
                        country: nil,
                        languageHints: [],
                        queryGroup: groupName,
                        sourceProfile: profileName
                    )
                )
            }
        }
        return result
    }
}

struct RecommendedSourceConfiguration: Decodable {
    var name: String?
    var type: SourceType
    var url: String?
    var keywords: [String]
    var frequency: SourceFrequency?
    var customFrequencyMinutes: Int?
    var requiresLogin: Bool
    var isEnabled: Bool?
    var reason: String
    var searchEndpoint: String?
    var searchQueryTemplate: String?
    var searchTitlePath: String?
    var searchURLPath: String?
    var tavilyTopic: TavilyTopic?
    var tavilySearchDepth: TavilySearchDepth?
    var tavilyMaxResults: Int?
    var tavilyTimeRange: TavilyTimeRange?
    var tavilyIncludeRawContent: Bool?
    var includeDomains: [String]
    var excludeDomains: [String]
    var country: String?
    var languageHints: [String]
    var queryGroup: String?
    var sourceProfile: String?

    enum CodingKeys: String, CodingKey {
        case name
        case type
        case sourceType
        case sourceTypeSnake = "source_type"
        case url
        case endpoint
        case keywords
        case frequency
        case customFrequencyMinutes
        case customFrequencyMinutesSnake = "custom_frequency_minutes"
        case requiresLogin
        case requiresLoginSnake = "requires_login"
        case isEnabled
        case isEnabledSnake = "is_enabled"
        case enabled
        case reason
        case searchEndpoint
        case searchEndpointSnake = "search_endpoint"
        case searchQueryTemplate
        case searchQueryTemplateSnake = "search_query_template"
        case searchTitlePath
        case searchTitlePathSnake = "search_title_path"
        case searchURLPath
        case searchURLPathSnake = "search_url_path"
        case tavilyTopic
        case tavilyTopicSnake = "tavily_topic"
        case topic
        case tavilySearchDepth
        case tavilySearchDepthSnake = "tavily_search_depth"
        case searchDepth
        case searchDepthSnake = "search_depth"
        case tavilyMaxResults
        case tavilyMaxResultsSnake = "tavily_max_results"
        case maxResults
        case maxResultsSnake = "max_results"
        case tavilyTimeRange
        case tavilyTimeRangeSnake = "tavily_time_range"
        case timeRange
        case timeRangeSnake = "time_range"
        case tavilyIncludeRawContent
        case tavilyIncludeRawContentSnake = "tavily_include_raw_content"
        case includeRawContent
        case includeRawContentSnake = "include_raw_content"
        case includeDomains
        case includeDomainsSnake = "include_domains"
        case excludeDomains
        case excludeDomainsSnake = "exclude_domains"
        case country
        case market
        case languageHints
        case languageHintsSnake = "language_hints"
        case languages
        case queryGroup
        case queryGroupSnake = "query_group"
        case sourceProfile
        case sourceProfileSnake = "source_profile"
    }

    init(
        name: String? = nil,
        type: SourceType,
        url: String? = nil,
        keywords: [String] = [],
        frequency: SourceFrequency? = nil,
        customFrequencyMinutes: Int? = nil,
        requiresLogin: Bool = false,
        isEnabled: Bool? = nil,
        reason: String = "",
        searchEndpoint: String? = nil,
        searchQueryTemplate: String? = nil,
        searchTitlePath: String? = nil,
        searchURLPath: String? = nil,
        tavilyTopic: TavilyTopic? = nil,
        tavilySearchDepth: TavilySearchDepth? = nil,
        tavilyMaxResults: Int? = nil,
        tavilyTimeRange: TavilyTimeRange? = nil,
        tavilyIncludeRawContent: Bool? = nil,
        includeDomains: [String] = [],
        excludeDomains: [String] = [],
        country: String? = nil,
        languageHints: [String] = [],
        queryGroup: String? = nil,
        sourceProfile: String? = nil
    ) {
        self.name = name
        self.type = type
        self.url = url
        self.keywords = keywords
        self.frequency = frequency
        self.customFrequencyMinutes = customFrequencyMinutes
        self.requiresLogin = requiresLogin
        self.isEnabled = isEnabled
        self.reason = reason
        self.searchEndpoint = searchEndpoint
        self.searchQueryTemplate = searchQueryTemplate
        self.searchTitlePath = searchTitlePath
        self.searchURLPath = searchURLPath
        self.tavilyTopic = tavilyTopic
        self.tavilySearchDepth = tavilySearchDepth
        self.tavilyMaxResults = tavilyMaxResults
        self.tavilyTimeRange = tavilyTimeRange
        self.tavilyIncludeRawContent = tavilyIncludeRawContent
        self.includeDomains = includeDomains
        self.excludeDomains = excludeDomains
        self.country = country
        self.languageHints = languageHints
        self.queryGroup = queryGroup
        self.sourceProfile = sourceProfile
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try FlexibleJSON.string(from: container, keys: [.name])
        url = try FlexibleJSON.string(from: container, keys: [.url, .endpoint])
        keywords = try FlexibleJSON.stringList(from: container, keys: [.keywords])
        frequency = try FlexibleJSON.decoded(SourceFrequency.self, from: container, keys: [.frequency])
        customFrequencyMinutes = try FlexibleJSON.int(from: container, keys: [.customFrequencyMinutes, .customFrequencyMinutesSnake])
        let rawRequiresLogin = try FlexibleJSON.bool(from: container, keys: [.requiresLogin, .requiresLoginSnake]) ?? false
        isEnabled = try FlexibleJSON.bool(from: container, keys: [.isEnabled, .isEnabledSnake, .enabled])
        reason = try FlexibleJSON.string(from: container, keys: [.reason]) ?? ""
        searchEndpoint = try FlexibleJSON.string(from: container, keys: [.searchEndpoint, .searchEndpointSnake])
        searchQueryTemplate = try FlexibleJSON.string(from: container, keys: [.searchQueryTemplate, .searchQueryTemplateSnake])
        searchTitlePath = try FlexibleJSON.string(from: container, keys: [.searchTitlePath, .searchTitlePathSnake])
        searchURLPath = try FlexibleJSON.string(from: container, keys: [.searchURLPath, .searchURLPathSnake])
        tavilyTopic = try FlexibleJSON.decoded(TavilyTopic.self, from: container, keys: [.tavilyTopic, .tavilyTopicSnake, .topic])
        tavilySearchDepth = try FlexibleJSON.decoded(TavilySearchDepth.self, from: container, keys: [.tavilySearchDepth, .tavilySearchDepthSnake, .searchDepth, .searchDepthSnake])
        tavilyMaxResults = try FlexibleJSON.int(from: container, keys: [.tavilyMaxResults, .tavilyMaxResultsSnake, .maxResults, .maxResultsSnake])
        tavilyTimeRange = try FlexibleJSON.decoded(TavilyTimeRange.self, from: container, keys: [.tavilyTimeRange, .tavilyTimeRangeSnake, .timeRange, .timeRangeSnake])
        tavilyIncludeRawContent = try FlexibleJSON.bool(from: container, keys: [.tavilyIncludeRawContent, .tavilyIncludeRawContentSnake, .includeRawContent, .includeRawContentSnake])
        includeDomains = try FlexibleJSON.stringList(from: container, keys: [.includeDomains, .includeDomainsSnake])
        excludeDomains = try FlexibleJSON.stringList(from: container, keys: [.excludeDomains, .excludeDomainsSnake])
        country = try FlexibleJSON.string(from: container, keys: [.country, .market])
        languageHints = try FlexibleJSON.stringList(from: container, keys: [.languageHints, .languageHintsSnake, .languages])
        queryGroup = try FlexibleJSON.string(from: container, keys: [.queryGroup, .queryGroupSnake])
        sourceProfile = try FlexibleJSON.string(from: container, keys: [.sourceProfile, .sourceProfileSnake])

        let rawType = try FlexibleJSON.string(from: container, keys: [.type, .sourceType, .sourceTypeSnake])
        let resolved = Self.resolveType(
            rawType: rawType,
            requiresLogin: rawRequiresLogin,
            url: url,
            searchEndpoint: searchEndpoint,
            includeDomains: includeDomains
        )
        type = resolved.type
        requiresLogin = rawRequiresLogin || resolved.requiresLogin
    }

    var effectiveIsEnabled: Bool {
        guard !requiresLogin, type != .searchAPI else { return false }
        return isEnabled ?? true
    }

    private static func resolveType(
        rawType: String?,
        requiresLogin: Bool,
        url: String?,
        searchEndpoint: String?,
        includeDomains: [String]
    ) -> (type: SourceType, requiresLogin: Bool) {
        let normalized = rawType?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: "-", with: "_")
            .replacingOccurrences(of: " ", with: "_")

        switch normalized {
        case "webpage", "web_page", "web", "url", "official_page", "official":
            return (.webPage, requiresLogin)
        case "login", "login_page", "login_web_page", "authenticated", "authenticated_web_page":
            return (.webPage, true)
        case "rss", "atom", "feed":
            return (.rss, requiresLogin)
        case "searchapi", "search_api", "api", "custom_search_api", "generic_search_api":
            return (.searchAPI, requiresLogin)
        case "tavily", "tavilysearch", "tavily_search":
            return (.tavilySearch, requiresLogin)
        default:
            if searchEndpoint?.nilIfBlank != nil {
                return (.searchAPI, requiresLogin)
            }
            if url?.lowercased().contains("rss") == true || url?.lowercased().contains("feed") == true {
                return (.rss, requiresLogin)
            }
            if !includeDomains.isEmpty || url?.nilIfBlank == nil {
                return (.tavilySearch, requiresLogin)
            }
            return (.webPage, requiresLogin)
        }
    }
}

struct SourceRecommendationSummary {
    var recommendationSummary: String
    var competitorCount: Int
    var sourceCount: Int
    var disabledSourceCount: Int
    var rows: [SourceRecommendationPreviewRow]

    var typeCounts: [(SourceType, Int)] {
        SourceType.allCases.compactMap { type in
            let count = rows.filter { $0.type == type }.count
            return count > 0 ? (type, count) : nil
        }
    }
}

struct SourceRecommendationPreviewRow: Identifiable {
    var competitorName: String
    var market: String
    var sourceName: String
    var type: SourceType
    var isEnabled: Bool
    var reason: String

    var id: String {
        "\(competitorName)|\(sourceName)|\(type.rawValue)|\(reason)"
    }
}

struct SourceRecommendationImportResult {
    var competitors: Int
    var sources: Int
    var disabledSources: Int
    var skippedSources: Int
}

enum SourceRecommendationImportMapper {
    static func summary(for configuration: SourceRecommendationConfiguration) -> SourceRecommendationSummary {
        let rows = configuration.competitors.sorted(by: { $0.key < $1.key }).flatMap { key, competitorConfig in
            let name = displayName(key: key, config: competitorConfig)
            let market = competitorConfig.focusMarket.nilIfBlank ?? competitorConfig.markets.first ?? ""
            return competitorConfig.sources.enumerated().map { index, sourceConfig in
                SourceRecommendationPreviewRow(
                    competitorName: name,
                    market: market,
                    sourceName: sourceName(for: sourceConfig, competitorName: name, index: index),
                    type: sourceConfig.type,
                    isEnabled: sourceConfig.effectiveIsEnabled,
                    reason: setupReason(for: sourceConfig)
                )
            }
        }

        return SourceRecommendationSummary(
            recommendationSummary: configuration.recommendationSummary,
            competitorCount: configuration.competitors.count,
            sourceCount: rows.count,
            disabledSourceCount: rows.filter { !$0.isEnabled }.count,
            rows: rows
        )
    }

    static func competitor(
        key: String,
        config: RecommendedCompetitorConfiguration,
        existing: Competitor?
    ) -> Competitor {
        let name = displayName(key: key, config: config)
        let sourceKeywords = config.sources.flatMap(\.keywords)
        let keywords = unique((existing?.keywords ?? []) + config.keywords + sourceKeywords)
        let aliases = unique((existing?.aliases ?? []) + config.aliases + [key])
            .filter { $0.caseInsensitiveCompare(name) != .orderedSame }
        let importedNotes = [
            config.markets.isEmpty ? nil : "监控市场：\(config.markets.joined(separator: ", "))",
            config.focusMarket.nilIfBlank.map { "重点市场：\($0)" },
            config.languages.isEmpty ? nil : "语言：\(config.languages.joined(separator: ", "))",
            config.notes.nilIfBlank,
            "由业务描述智能推荐导入。"
        ]
        .compactMap { $0 }
        .joined(separator: "\n")
        let notes = mergeNotes(existing?.notes ?? "", importedNotes)

        return Competitor(
            id: existing?.id ?? UUID(),
            name: name,
            aliases: aliases,
            keywords: keywords,
            notes: notes,
            isEnabled: true,
            createdAt: existing?.createdAt ?? Date()
        )
    }

    static func source(
        from config: RecommendedSourceConfiguration,
        competitor: Competitor,
        competitorConfig: RecommendedCompetitorConfiguration,
        existing: IntelligenceSource?,
        index: Int
    ) -> IntelligenceSource? {
        let type = config.type
        let endpoint = config.searchEndpoint?.nilIfBlank ?? (type == .searchAPI ? config.url?.nilIfBlank : nil)
        let url: String
        switch type {
        case .tavilySearch:
            url = config.url?.nilIfBlank ?? endpoint ?? "https://api.tavily.com/search"
        case .searchAPI:
            guard let endpoint else { return nil }
            url = endpoint
        case .webPage, .rss:
            guard let sourceURL = config.url?.nilIfBlank else { return nil }
            url = sourceURL
        }

        let country = config.country?.nilIfBlank
            ?? competitorConfig.focusMarket.nilIfBlank
            ?? competitorConfig.markets.first
            ?? ""
        let languageHints = unique(config.languageHints + competitorConfig.languages)
        let queryTemplate = config.searchQueryTemplate?.nilIfBlank
            ?? (type == .tavilySearch ? "\"{competitor}\" {aliases} {keywords} {focus_market} {languages}" : "{competitor} {keywords}")

        return IntelligenceSource(
            id: existing?.id ?? UUID(),
            competitorID: competitor.id,
            name: sourceName(for: config, competitorName: competitor.name, index: index),
            type: type,
            url: url,
            keywords: unique(config.keywords + competitorConfig.keywords),
            frequency: config.frequency ?? .globalDefault,
            customFrequencyMinutes: clampMinutes(config.customFrequencyMinutes ?? 60),
            requiresLogin: config.requiresLogin,
            chromeProfilePath: "",
            searchEndpoint: endpoint ?? (type == .tavilySearch ? "https://api.tavily.com/search" : ""),
            searchAPIKey: "",
            searchQueryTemplate: queryTemplate,
            searchTitlePath: config.searchTitlePath?.nilIfBlank ?? "title",
            searchURLPath: config.searchURLPath?.nilIfBlank ?? "url",
            tavilyTopic: config.tavilyTopic ?? defaultTopic(for: config.sourceProfile ?? sourceName(for: config, competitorName: competitor.name, index: index)),
            tavilySearchDepth: config.tavilySearchDepth ?? .basic,
            tavilyMaxResults: config.tavilyMaxResults ?? 5,
            tavilyTimeRange: config.tavilyTimeRange ?? .week,
            tavilyIncludeRawContent: config.tavilyIncludeRawContent ?? true,
            tavilyIncludeDomains: config.includeDomains,
            tavilyExcludeDomains: config.excludeDomains,
            tavilyCountry: country,
            tavilyLanguageHints: languageHints,
            tavilyQueryGroup: config.queryGroup?.nilIfBlank ?? "",
            tavilySourceProfile: config.sourceProfile?.nilIfBlank ?? "",
            isEnabled: config.effectiveIsEnabled,
            lastRunAt: existing?.lastRunAt
        )
    }

    static func displayName(key: String, config: RecommendedCompetitorConfiguration) -> String {
        config.name?.nilIfBlank
            ?? config.aliases.first?.nilIfBlank
            ?? key
    }

    static func sourceName(for config: RecommendedSourceConfiguration, competitorName: String, index: Int) -> String {
        if let name = config.name?.nilIfBlank {
            return name
        }
        let suffix = [
            config.queryGroup?.nilIfBlank,
            config.sourceProfile?.nilIfBlank
        ]
        .compactMap { $0 }
        .joined(separator: " · ")
        if !suffix.isEmpty {
            return "\(competitorName) · \(suffix)"
        }
        return "\(competitorName) · \(config.type.label) \(index + 1)"
    }

    static func setupReason(for config: RecommendedSourceConfiguration) -> String {
        if config.requiresLogin {
            return "需选择 Chrome 用户资料后启用"
        }
        if config.type == .searchAPI {
            return "需确认接口密钥和字段映射后启用"
        }
        return config.reason.nilIfBlank ?? "公开来源，导入后可直接运行"
    }

    private static func defaultTopic(for profileName: String) -> TavilyTopic {
        let normalized = profileName.lowercased()
        if normalized.contains("news") || normalized.contains("媒体") || normalized.contains("press") {
            return .news
        }
        if normalized.contains("finance") || normalized.contains("invest") || normalized.contains("证券") {
            return .finance
        }
        return .general
    }

    private static func unique(_ values: [String]) -> [String] {
        var seen = Set<String>()
        return values.compactMap { value in
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return nil }
            let key = trimmed.lowercased()
            guard !seen.contains(key) else { return nil }
            seen.insert(key)
            return trimmed
        }
    }

    private static func mergeNotes(_ existing: String, _ imported: String) -> String {
        let existingLines = existing.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        let importedLines = imported.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        return unique(existingLines + importedLines).joined(separator: "\n")
    }

    private static func clampMinutes(_ value: Int) -> Int {
        min(max(value, 1), 30 * 24 * 60)
    }
}

private struct RecommendedListedCompetitorConfiguration: Decodable {
    var id: String?
    var key: String?
    var name: String?
    var configuration: RecommendedCompetitorConfiguration

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
        configuration = try RecommendedCompetitorConfiguration(from: decoder)

        if configuration.name == nil, let name = name?.nilIfBlank {
            configuration.name = name
        }
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

private enum FlexibleJSON {
    static func string<K: CodingKey>(from container: KeyedDecodingContainer<K>, keys: [K]) throws -> String? {
        for key in keys {
            if let value = try? container.decodeIfPresent(String.self, forKey: key),
               let value = value.nilIfBlank {
                return value
            }
        }
        return nil
    }

    static func stringList<K: CodingKey>(from container: KeyedDecodingContainer<K>, keys: [K]) throws -> [String] {
        for key in keys {
            if let values = try? container.decodeIfPresent([String].self, forKey: key) {
                return values.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
            }
            if let value = try? container.decodeIfPresent(String.self, forKey: key) {
                let values = value.splitList()
                if !values.isEmpty {
                    return values
                }
            }
        }
        return []
    }

    static func int<K: CodingKey>(from container: KeyedDecodingContainer<K>, keys: [K]) throws -> Int? {
        for key in keys {
            if let value = try? container.decodeIfPresent(Int.self, forKey: key) {
                return value
            }
            if let value = try? container.decodeIfPresent(String.self, forKey: key), let parsed = Int(value) {
                return parsed
            }
        }
        return nil
    }

    static func bool<K: CodingKey>(from container: KeyedDecodingContainer<K>, keys: [K]) throws -> Bool? {
        for key in keys {
            if let value = try? container.decodeIfPresent(Bool.self, forKey: key) {
                return value
            }
            if let value = try? container.decodeIfPresent(String.self, forKey: key), let raw = value.nilIfBlank {
                switch raw.lowercased() {
                case "true", "yes", "1", "enabled", "enable", "text", "markdown":
                    return true
                case "false", "no", "0", "disabled", "disable":
                    return false
                default:
                    break
                }
            }
        }
        return nil
    }

    static func decoded<T: Decodable, K: CodingKey>(_ type: T.Type, from container: KeyedDecodingContainer<K>, keys: [K]) throws -> T? {
        for key in keys {
            if let value = try? container.decodeIfPresent(type, forKey: key) {
                return value
            }
        }
        return nil
    }
}
