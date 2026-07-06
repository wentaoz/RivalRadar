import Foundation

struct AnalysisResult {
    var category: IntelligenceCategory
    var summary: String
    var impact: String
    var importance: Int
    var isRelevant: Bool
    var relevanceReason: String
    var warning: String?
}

struct IntelligenceAnalyzer {
    private let client = OpenAIChatClient()

    func analyze(
        raw: RawCollectedItem,
        competitor: Competitor,
        source: IntelligenceSource? = nil,
        configuration: OpenAIConfiguration
    ) async -> AnalysisResult {
        guard !configuration.apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return fallback(raw: raw, reason: nil)
        }

        do {
            let response = try await client.complete(
                messages: [
                    ChatMessage(role: "system", content: systemPrompt),
                    ChatMessage(role: "user", content: userPrompt(raw: raw, competitor: competitor, source: source))
                ],
                configuration: configuration,
                temperature: 0.1,
                maxTokens: 900
            )
            return try parse(response)
        } catch {
            return fallback(raw: raw, reason: error.localizedDescription)
        }
    }

    private var systemPrompt: String {
        """
        你是严谨的竞品情报分析助手。只依据输入内容分析，不要编造。
        你必须输出 JSON 对象，字段：
        - is_relevant: boolean，只有内容明确与目标竞品、竞品别名、竞品产品、目标市场内业务动态相关时才为 true
        - relevance_reason: 中文，说明为什么相关或为什么不相关
        - category: product/pricing/marketing/customer/funding/hiring/partnership/risk/technology/other
        - summary: 中文，1-3 句话概括事实
        - impact: 中文，说明对我方可能影响或建议关注点
        - importance: 1 到 5 的整数
        如果文章只是泛泛出现同类关键词、讲的是无关公司/人物/行业、或无法确认和目标竞品有关，is_relevant 必须为 false。
        不要输出 Markdown，不要输出 JSON 以外的文字。
        """
    }

    private func userPrompt(raw: RawCollectedItem, competitor: Competitor, source: IntelligenceSource?) -> String {
        let aliases = competitor.aliases.joined(separator: ", ")
        let competitorKeywords = competitor.keywords.joined(separator: ", ")
        let sourceKeywords = source?.keywords.joined(separator: ", ") ?? ""
        let market = source?.tavilyCountry ?? ""
        let queryGroup = source?.tavilyQueryGroup ?? ""
        return """
        竞品：\(competitor.name)
        竞品别名：\(aliases)
        竞品关键词：\(competitorKeywords)
        本次搜索关键词：\(sourceKeywords)
        重点市场：\(market)
        查询主题组：\(queryGroup)
        标题：\(raw.title)
        链接：\(raw.url)
        正文：
        \(raw.content.clipped(to: 6_000))
        """
    }

    private func parse(_ response: String) throws -> AnalysisResult {
        let json = extractJSONObject(from: response)
        guard let data = json.data(using: .utf8) else {
            throw OpenAIChatClient.ClientError.invalidResponse
        }
        let payload = try JSONDecoder().decode(AnalysisPayload.self, from: data)
        let relevanceReason = payload.relevanceReasonValue.nilIfBlank ?? "模型未给出相关性原因"
        return AnalysisResult(
            category: IntelligenceCategory(rawValue: payload.category) ?? .other,
            summary: payload.summary.nilIfBlank ?? "已发现新情报。",
            impact: payload.impact.nilIfBlank ?? "建议人工复核其影响。",
            importance: max(1, min(5, payload.importance)),
            isRelevant: payload.isRelevantValue ?? true,
            relevanceReason: relevanceReason,
            warning: nil
        )
    }

    private func fallback(raw: RawCollectedItem, reason: String?) -> AnalysisResult {
        let prefix = reason.map { "AI 分析失败：\($0)。" } ?? ""
        return AnalysisResult(
            category: .other,
            summary: prefix + raw.content.clipped(to: 240),
            impact: "建议打开来源链接复核，并按业务相关性人工判断影响。",
            importance: 2,
            isRelevant: true,
            relevanceReason: reason == nil ? "未配置 API，保守保留待人工复核" : "AI 分析失败，保守保留待人工复核",
            warning: reason
        )
    }

    private func extractJSONObject(from value: String) -> String {
        guard let start = value.firstIndex(of: "{"),
              let end = value.lastIndex(of: "}"),
              start <= end else {
            return value
        }
        return String(value[start...end])
    }
}

private struct AnalysisPayload: Codable {
    var isRelevant: Bool?
    var isRelevantSnake: Bool?
    var relevanceReason: String?
    var relevanceReasonSnake: String?
    var category: String
    var summary: String
    var impact: String
    var importance: Int

    enum CodingKeys: String, CodingKey {
        case isRelevant
        case isRelevantSnake = "is_relevant"
        case relevanceReason
        case relevanceReasonSnake = "relevance_reason"
        case category
        case summary
        case impact
        case importance
    }

    var isRelevantValue: Bool? {
        isRelevantSnake ?? isRelevant
    }

    var relevanceReasonValue: String {
        relevanceReasonSnake ?? relevanceReason ?? ""
    }
}
