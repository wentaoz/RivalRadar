import Foundation

struct TavilyConfigurationAdvisor {
    private let client = OpenAIChatClient()

    func recommendJSON(
        prompt: TavilyRecommendationPrompt,
        configuration: OpenAIConfiguration
    ) async throws -> String {
        let response = try await client.complete(
            messages: [
                ChatMessage(role: "system", content: systemPrompt),
                ChatMessage(role: "user", content: userPrompt(prompt))
            ],
            configuration: configuration,
            temperature: 0.25,
            maxTokens: 2_400
        )
        return extractJSONObject(from: response)
    }

    private var systemPrompt: String {
        """
        你是竞品情报搜索配置专家。你的任务是为 Tavily Search 生成适合竞品监控的 JSON 配置。
        必须只输出 JSON 对象，不要 Markdown，不要解释。
        JSON 结构必须是：
        {
          "tavily": {
            "endpoint": "https://api.tavily.com/search",
            "frequency": "globalDefault",
            "search_depth": "basic",
            "time_range": "week",
            "max_results": 5,
            "include_raw_content": true
          },
          "competitors": {
            "<competitor_key>": {
              "aliases": [],
              "markets": [],
              "focus_market": "",
              "languages": [],
              "query_groups": {
                "<group_name>": []
              },
              "source_profiles": {
                "official": { "include_domains": [] },
                "news": { "include_domains": [], "topic": "news" },
                "social_voice": { "include_domains": [] }
              }
            }
          }
        }
        要求：
        - query_groups 给 5-8 组，每组 5-9 个关键词。
        - 关键词应包含当地语言、英文行业词、产品词、监管词和用户投诉词。
        - source_profiles 中的域名要尽量是高质量、可公开搜索的域名。
        - 不要编造过度具体的内部资料来源。
        - 如果不确定域名，优先使用官方域名、监管/证券披露、主流财经媒体和大型社区平台。
        - frequency 默认使用 "globalDefault"，让应用设置里的全局采集频率统一生效；只有用户明确要求单独频率时才改成 "hourly"、"daily"、"custom" 等。
        """
    }

    private func userPrompt(_ prompt: TavilyRecommendationPrompt) -> String {
        """
        请为以下竞品生成 Tavily Search 批量配置 JSON。

        竞品显示名：\(prompt.competitorName)
        竞品标识：\(prompt.competitorKey)
        监控市场：\(prompt.markets.joined(separator: ", "))
        重点市场：\(prompt.focusMarket)
        语言：\(prompt.languages.joined(separator: ", "))
        业务描述/监控目标：
        \(prompt.businessDescription)
        """
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
