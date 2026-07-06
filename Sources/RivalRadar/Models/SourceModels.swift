import Foundation

enum SourceType: String, CaseIterable, Codable, Identifiable {
    case webPage
    case rss
    case searchAPI
    case tavilySearch

    var id: String { rawValue }

    var label: String {
        switch self {
        case .webPage:
            return "网页"
        case .rss:
            return "RSS/订阅"
        case .searchAPI:
            return "通用搜索接口"
        case .tavilySearch:
            return "Tavily 搜索"
        }
    }

    var systemImage: String {
        switch self {
        case .webPage:
            return "globe"
        case .rss:
            return "dot.radiowaves.left.and.right"
        case .searchAPI:
            return "magnifyingglass"
        case .tavilySearch:
            return "sparkle.magnifyingglass"
        }
    }
}

enum TavilyTopic: String, CaseIterable, Codable, Identifiable {
    case general
    case news
    case finance

    var id: String { rawValue }

    var label: String {
        switch self {
        case .general:
            return "综合"
        case .news:
            return "新闻"
        case .finance:
            return "金融"
        }
    }
}

enum TavilySearchDepth: String, CaseIterable, Codable, Identifiable {
    case basic
    case advanced
    case fast
    case ultraFast = "ultra-fast"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .basic:
            return "基础"
        case .advanced:
            return "深度"
        case .fast:
            return "快速"
        case .ultraFast:
            return "极速"
        }
    }
}

enum TavilyTimeRange: String, CaseIterable, Codable, Identifiable {
    case none
    case day
    case week
    case month
    case year

    var id: String { rawValue }

    var label: String {
        switch self {
        case .none:
            return "不限"
        case .day:
            return "最近一天"
        case .week:
            return "最近一周"
        case .month:
            return "最近一月"
        case .year:
            return "最近一年"
        }
    }

    var apiValue: String? {
        switch self {
        case .none:
            return nil
        case .day:
            return "day"
        case .week:
            return "week"
        case .month:
            return "month"
        case .year:
            return "year"
        }
    }
}

enum SourceFrequency: String, CaseIterable, Codable, Identifiable {
    case globalDefault
    case manual
    case fifteenMinutes
    case hourly
    case sixHours
    case daily
    case weekly
    case custom

    var id: String { rawValue }

    static var allCases: [SourceFrequency] {
        sourceOptions
    }

    static let sourceOptions: [SourceFrequency] = [
        .globalDefault,
        .fifteenMinutes,
        .hourly,
        .sixHours,
        .daily,
        .weekly,
        .custom,
        .manual
    ]

    static let globalOptions: [SourceFrequency] = [
        .fifteenMinutes,
        .hourly,
        .sixHours,
        .daily,
        .weekly,
        .custom,
        .manual
    ]

    var label: String {
        switch self {
        case .globalDefault:
            return "跟随全局"
        case .manual:
            return "手动"
        case .fifteenMinutes:
            return "15 分钟"
        case .hourly:
            return "1 小时"
        case .sixHours:
            return "6 小时"
        case .daily:
            return "每天"
        case .weekly:
            return "每周"
        case .custom:
            return "自定义"
        }
    }

    func interval(customMinutes: Int = 60) -> TimeInterval? {
        switch self {
        case .globalDefault:
            return nil
        case .manual:
            return nil
        case .fifteenMinutes:
            return 15 * 60
        case .hourly:
            return 60 * 60
        case .sixHours:
            return 6 * 60 * 60
        case .daily:
            return 24 * 60 * 60
        case .weekly:
            return 7 * 24 * 60 * 60
        case .custom:
            return TimeInterval(max(1, customMinutes) * 60)
        }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let value = try container.decode(String.self)
        let normalized = value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: "-", with: "_")
        switch normalized {
        case "globaldefault", "global_default", "global", "follow_global", "followglobal":
            self = .globalDefault
        case "manual", "手动":
            self = .manual
        case "fifteenminutes", "fifteen_minutes", "15_minutes", "15minutes", "15_min", "15min":
            self = .fifteenMinutes
        case "hourly", "hour", "1_hour", "1hour":
            self = .hourly
        case "sixhours", "six_hours", "6_hours", "6hours", "6h":
            self = .sixHours
        case "daily", "day", "1_day", "1day":
            self = .daily
        case "weekly", "week", "1_week", "1week":
            self = .weekly
        case "custom", "自定义":
            self = .custom
        default:
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Unsupported source frequency: \(value)"
            )
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

struct IntelligenceSource: Identifiable, Codable, Hashable {
    var id: UUID
    var competitorID: UUID
    var name: String
    var type: SourceType
    var url: String
    var keywords: [String]
    var frequency: SourceFrequency
    var customFrequencyMinutes: Int
    var requiresLogin: Bool
    var chromeProfilePath: String
    var searchEndpoint: String
    var searchAPIKey: String
    var searchQueryTemplate: String
    var searchTitlePath: String
    var searchURLPath: String
    var tavilyTopic: TavilyTopic
    var tavilySearchDepth: TavilySearchDepth
    var tavilyMaxResults: Int
    var tavilyTimeRange: TavilyTimeRange
    var tavilyIncludeRawContent: Bool
    var tavilyIncludeDomains: [String]
    var tavilyExcludeDomains: [String]
    var tavilyCountry: String
    var tavilyLanguageHints: [String]
    var tavilyQueryGroup: String
    var tavilySourceProfile: String
    var isEnabled: Bool
    var lastRunAt: Date?

    init(
        id: UUID = UUID(),
        competitorID: UUID,
        name: String,
        type: SourceType = .webPage,
        url: String = "",
        keywords: [String] = [],
        frequency: SourceFrequency = .globalDefault,
        customFrequencyMinutes: Int = 60,
        requiresLogin: Bool = false,
        chromeProfilePath: String = "",
        searchEndpoint: String = "",
        searchAPIKey: String = "",
        searchQueryTemplate: String = "{competitor} {keywords}",
        searchTitlePath: String = "title",
        searchURLPath: String = "url",
        tavilyTopic: TavilyTopic = .news,
        tavilySearchDepth: TavilySearchDepth = .basic,
        tavilyMaxResults: Int = 5,
        tavilyTimeRange: TavilyTimeRange = .week,
        tavilyIncludeRawContent: Bool = true,
        tavilyIncludeDomains: [String] = [],
        tavilyExcludeDomains: [String] = [],
        tavilyCountry: String = "",
        tavilyLanguageHints: [String] = [],
        tavilyQueryGroup: String = "",
        tavilySourceProfile: String = "",
        isEnabled: Bool = true,
        lastRunAt: Date? = nil
    ) {
        self.id = id
        self.competitorID = competitorID
        self.name = name
        self.type = type
        self.url = url
        self.keywords = keywords
        self.frequency = frequency
        self.customFrequencyMinutes = customFrequencyMinutes
        self.requiresLogin = requiresLogin
        self.chromeProfilePath = chromeProfilePath
        self.searchEndpoint = searchEndpoint
        self.searchAPIKey = searchAPIKey
        self.searchQueryTemplate = searchQueryTemplate
        self.searchTitlePath = searchTitlePath
        self.searchURLPath = searchURLPath
        self.tavilyTopic = tavilyTopic
        self.tavilySearchDepth = tavilySearchDepth
        self.tavilyMaxResults = max(1, min(20, tavilyMaxResults))
        self.tavilyTimeRange = tavilyTimeRange
        self.tavilyIncludeRawContent = tavilyIncludeRawContent
        self.tavilyIncludeDomains = tavilyIncludeDomains
        self.tavilyExcludeDomains = tavilyExcludeDomains
        self.tavilyCountry = tavilyCountry
        self.tavilyLanguageHints = tavilyLanguageHints
        self.tavilyQueryGroup = tavilyQueryGroup
        self.tavilySourceProfile = tavilySourceProfile
        self.isEnabled = isEnabled
        self.lastRunAt = lastRunAt
    }
}
