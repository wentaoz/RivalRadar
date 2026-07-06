import Foundation

enum IntelligenceCategory: String, CaseIterable, Codable, Identifiable {
    case product
    case pricing
    case marketing
    case customer
    case funding
    case hiring
    case partnership
    case risk
    case technology
    case other

    var id: String { rawValue }

    var label: String {
        switch self {
        case .product:
            return "产品更新"
        case .pricing:
            return "价格变化"
        case .marketing:
            return "市场活动"
        case .customer:
            return "客户案例"
        case .funding:
            return "融资财务"
        case .hiring:
            return "招聘组织"
        case .partnership:
            return "合作生态"
        case .risk:
            return "风险舆情"
        case .technology:
            return "技术动态"
        case .other:
            return "其他"
        }
    }
}

struct RawCollectedItem: Hashable {
    var title: String
    var url: String
    var content: String
    var publishedAt: Date?
    var sourceName: String
}

struct IntelligenceItem: Identifiable, Codable, Hashable {
    var id: UUID
    var sourceID: UUID
    var competitorID: UUID
    var title: String
    var url: String
    var normalizedURL: String
    var domain: String
    var rawContent: String
    var publishedAt: Date?
    var discoveredAt: Date
    var category: IntelligenceCategory
    var summary: String
    var impact: String
    var importance: Int
    var urlHash: String
    var titleHash: String
    var contentHash: String
    var isNotified: Bool
    var isReported: Bool

    init(
        id: UUID = UUID(),
        sourceID: UUID,
        competitorID: UUID,
        title: String,
        url: String,
        normalizedURL: String,
        domain: String,
        rawContent: String,
        publishedAt: Date?,
        discoveredAt: Date = Date(),
        category: IntelligenceCategory,
        summary: String,
        impact: String,
        importance: Int,
        urlHash: String,
        titleHash: String,
        contentHash: String,
        isNotified: Bool = false,
        isReported: Bool = false
    ) {
        self.id = id
        self.sourceID = sourceID
        self.competitorID = competitorID
        self.title = title
        self.url = url
        self.normalizedURL = normalizedURL
        self.domain = domain
        self.rawContent = rawContent
        self.publishedAt = publishedAt
        self.discoveredAt = discoveredAt
        self.category = category
        self.summary = summary
        self.impact = impact
        self.importance = max(1, min(5, importance))
        self.urlHash = urlHash
        self.titleHash = titleHash
        self.contentHash = contentHash
        self.isNotified = isNotified
        self.isReported = isReported
    }
}
