import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct TavilyGuidedImportView: View {
    @Binding var tavilyAPIKey: String
    @Binding var jsonText: String
    @Binding var statusText: String
    var recommendationAction: (TavilyRecommendationPrompt) async throws -> String
    var importAction: () -> Void

    @State private var competitorKey = "nubank"
    @State private var displayName = "Nubank"
    @State private var aliasesText = "Nubank\nNu Mexico\nNu México\nNu Holdings\nTarjeta Nu\nCuenta Nu"
    @State private var marketsText = "mexico\nbrazil\ncolombia"
    @State private var focusMarket = "mexico"
    @State private var languagesText = "es-MX\nen\npt-BR"
    @State private var selectedGroups: Set<String> = ["credit_card", "deposit_account", "growth", "regulation", "marketing"]
    @State private var customGroupName = ""
    @State private var customKeywordsText = ""
    @State private var selectedProfiles: Set<String> = ["official", "news"]
    @State private var officialDomainsText = "nu.com.mx\ninternational.nubank.com.br\ninvestidores.nu\ninvestors.nu\nsec.gov"
    @State private var newsDomainsText = "reuters.com\nbloomberg.com\nbusinesswire.com\nelfinanciero.com.mx\neleconomista.com.mx\nexpansion.mx\nforbes.com.mx"
    @State private var socialDomainsText = "reddit.com\nyoutube.com\nx.com\nfacebook.com"
    @State private var searchDepth = TavilySearchDepth.basic
    @State private var timeRange = TavilyTimeRange.week
    @State private var maxResults = 5
    @State private var includeRawContent = true
    @State private var showJSONEditor = true
    @State private var businessDescription = "我想持续跟踪这个竞品的产品功能、定价/权益、用户增长、监管动态、营销活动、风险表现和用户投诉。"
    @State private var isGeneratingRecommendation = false

    var body: some View {
        SectionCard(title: "Tavily 智能配置向导", systemImage: "wand.and.stars") {
            VStack(alignment: .leading, spacing: 16) {
                intro
                competitorStep
                aiRecommendationStep
                topicsStep
                sourcesStep
                optionsStep
                actions

                DisclosureGroup("高级：查看和修改 JSON", isExpanded: $showJSONEditor) {
                    VStack(alignment: .leading, spacing: 10) {
                        AdaptiveTextArea(placeholder: "Tavily 批量配置 JSON", text: $jsonText, minLines: 14, maxLines: 36, monospaced: true)

                        HStack {
                            Button {
                                loadJSONFile(shouldImport: false)
                            } label: {
                                Label("选择 JSON 文件", systemImage: "doc")
                            }

                            Button {
                                loadJSONFile(shouldImport: true)
                            } label: {
                                Label("选择文件并导入", systemImage: "square.and.arrow.down.on.square")
                            }

                            Divider()

                            Button {
                                importAction()
                            } label: {
                                Label("按当前 JSON 导入", systemImage: "square.and.arrow.down")
                            }
                            .disabled(jsonText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                            if !statusText.isEmpty {
                                Text(statusText)
                                    .font(.caption)
                                    .foregroundStyle(statusText.contains("失败") ? Color.red : Color.secondary)
                            }
                        }

                        Text("你可以先用上面的表单生成 JSON，再在这里增删关键词、域名或竞品。JSON 导入会自动创建竞品和对应 Tavily 数据源。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.top, 8)
                }
            }
        }
    }

    private var intro: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("不需要理解搜索语法。可以先让 AI 推荐关键词、来源和 JSON，再按表单微调；系统会把每个“关注主题 × 信息来源”变成一个定时搜索任务。")
                .foregroundStyle(.secondary)
            Text("建议：第一版先选 4-6 个关注主题、2 类来源，避免一次生成太多噪音。后续可以在 JSON 里细调。")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var aiRecommendationStep: some View {
        GroupBox("第 2 步：让 AI 推荐关键词和来源") {
            VStack(alignment: .leading, spacing: 10) {
                AdaptiveTextArea(placeholder: "告诉 AI 你想监控什么", text: $businessDescription, minLines: 3, maxLines: 12)

                HStack {
                    Button {
                        Task {
                            await generateAIRecommendation()
                        }
                    } label: {
                        Label(isGeneratingRecommendation ? "AI 正在推荐..." : "让 AI 生成推荐 JSON", systemImage: "sparkles")
                    }
                    .disabled(isGeneratingRecommendation)

                    Text("AI 会根据竞品、市场、语言和业务目标推荐别名、关键词组、来源域名和搜索强度。生成后你仍可手动修改 JSON。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.vertical, 6)
        }
    }

    private var competitorStep: some View {
        GroupBox("第 1 步：竞品和市场") {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    TextField("竞品英文标识，例如 nubank", text: $competitorKey)
                        .textFieldStyle(.roundedBorder)
                    TextField("显示名称，例如 Nubank", text: $displayName)
                        .textFieldStyle(.roundedBorder)
                }
                AdaptiveTextArea(placeholder: "别名：品牌名、产品名、常见昵称，每行一个", text: $aliasesText, minLines: 3, maxLines: 12)
                HStack {
                    AdaptiveTextArea(placeholder: "监控市场，每行一个", text: $marketsText, minLines: 2, maxLines: 8)
                    TextField("重点市场", text: $focusMarket)
                        .textFieldStyle(.roundedBorder)
                    AdaptiveTextArea(placeholder: "语言，每行一个", text: $languagesText, minLines: 2, maxLines: 8)
                }
                Text("建议：别名越全，越容易搜到不同媒体和用户对同一竞品的叫法；重点市场建议用英文国家名，如 mexico。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 6)
        }
    }

    private var topicsStep: some View {
        GroupBox("第 3 步：选择关注主题") {
            VStack(alignment: .leading, spacing: 10) {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 180), spacing: 10)], alignment: .leading, spacing: 10) {
                    ForEach(Self.topicGroups) { group in
                        Toggle(isOn: binding(for: group.id, in: $selectedGroups)) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(group.title)
                                Text(group.hint)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .toggleStyle(.checkbox)
                    }
                }

                HStack {
                    TextField("自定义主题名，例如 merchant", text: $customGroupName)
                        .textFieldStyle(.roundedBorder)
                    AdaptiveTextArea(placeholder: "自定义关键词，每行一个", text: $customKeywordsText, minLines: 2, maxLines: 8)
                }
                Text("建议：产品、价格、增长、监管和营销通常最有价值；社媒/评价类主题噪音会更高。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 6)
        }
    }

    private var sourcesStep: some View {
        GroupBox("第 4 步：选择信息来源") {
            VStack(alignment: .leading, spacing: 10) {
                Toggle(isOn: binding(for: "official", in: $selectedProfiles)) {
                    Label("官方来源：官网、投资者关系、监管披露", systemImage: "checkmark.seal")
                }
                .toggleStyle(.checkbox)
                AdaptiveTextArea(placeholder: "官方域名，每行一个", text: $officialDomainsText, minLines: 2, maxLines: 12)
                    .disabled(!selectedProfiles.contains("official"))

                Toggle(isOn: binding(for: "news", in: $selectedProfiles)) {
                    Label("新闻媒体：财经新闻、行业报道、新闻稿", systemImage: "newspaper")
                }
                .toggleStyle(.checkbox)
                AdaptiveTextArea(placeholder: "新闻域名，每行一个", text: $newsDomainsText, minLines: 2, maxLines: 14)
                    .disabled(!selectedProfiles.contains("news"))

                Toggle(isOn: binding(for: "social_voice", in: $selectedProfiles)) {
                    Label("用户声音：社区、视频、社交平台", systemImage: "person.2.wave.2")
                }
                .toggleStyle(.checkbox)
                AdaptiveTextArea(placeholder: "用户声音域名，每行一个", text: $socialDomainsText, minLines: 2, maxLines: 12)
                    .disabled(!selectedProfiles.contains("social_voice"))

                Text("建议：先启用官方来源和新闻媒体。用户声音适合发现投诉和口碑，但需要更多人工复核。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 6)
        }
    }

    private var optionsStep: some View {
        GroupBox("第 5 步：接口和搜索强度") {
            VStack(alignment: .leading, spacing: 10) {
                SecureField("Tavily 接口密钥", text: $tavilyAPIKey)
                    .textFieldStyle(.roundedBorder)

                HStack {
                    Picker("搜索深度", selection: $searchDepth) {
                        ForEach(TavilySearchDepth.allCases) { value in
                            Text(value.label).tag(value)
                        }
                    }

                    Picker("时间范围", selection: $timeRange) {
                        ForEach(TavilyTimeRange.allCases) { value in
                            Text(value.label).tag(value)
                        }
                    }

                    Stepper("每组最多 \(maxResults) 条", value: $maxResults, in: 1...20)
                }

                Toggle("抓取更多正文给 DeepSeek 分析", isOn: $includeRawContent)
                    .toggleStyle(.checkbox)

                Text("频率在“设置 > 全局采集频率”里统一管理。此向导导入的数据源默认跟随全局，后续也可以在单个数据源里覆盖。建议日常监控用“基础 + 最近一周 + 5 条”，需要深挖时再改为“深度”或增加结果数。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 6)
        }
    }

    private var actions: some View {
        HStack(spacing: 10) {
            Button {
                loadJSONFile(shouldImport: true)
            } label: {
                Label("选择 JSON 文件导入", systemImage: "folder")
            }

            Button {
                jsonText = makeJSON()
                showJSONEditor = true
                statusText = "已生成 JSON 草稿，可继续编辑"
            } label: {
                Label("生成 JSON 草稿", systemImage: "doc.badge.gearshape")
            }

            Button {
                jsonText = makeJSON()
                importAction()
            } label: {
                Label("生成并导入", systemImage: "square.and.arrow.down")
            }

            Button {
                resetDefaults()
            } label: {
                Label("恢复示例", systemImage: "arrow.counterclockwise")
            }

            Spacer()

            Text("预计生成 \(sourceEstimate) 个数据源")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func loadJSONFile(shouldImport: Bool) {
        let panel = NSOpenPanel()
        panel.title = "选择 Tavily 批量配置 JSON"
        panel.prompt = shouldImport ? "导入" : "读取"
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.json]

        guard panel.runModal() == .OK, let url = panel.url else { return }

        do {
            jsonText = try String(contentsOf: url, encoding: .utf8)
            showJSONEditor = true
            statusText = "已读取 JSON 文件：\(url.lastPathComponent)"
            if shouldImport {
                importAction()
            }
        } catch {
            statusText = "读取 JSON 文件失败：\(error.localizedDescription)"
        }
    }

    private var sourceEstimate: Int {
        max(1, selectedGroups.count + (customKeywordsText.splitList().isEmpty ? 0 : 1)) * max(1, selectedProfiles.count)
    }

    private func binding(for id: String, in set: Binding<Set<String>>) -> Binding<Bool> {
        Binding(
            get: { set.wrappedValue.contains(id) },
            set: { isEnabled in
                if isEnabled {
                    set.wrappedValue.insert(id)
                } else {
                    set.wrappedValue.remove(id)
                }
            }
        )
    }

    private func makeJSON() -> String {
        var groups: [String: [String]] = [:]
        for group in Self.topicGroups where selectedGroups.contains(group.id) {
            groups[group.id] = group.keywords
        }
        let customKeywords = customKeywordsText.splitList()
        if let customName = customGroupName.nilIfBlank, !customKeywords.isEmpty {
            groups[customName] = customKeywords
        }

        var profiles: [String: [String: Any]] = [:]
        if selectedProfiles.contains("official") {
            profiles["official"] = ["include_domains": officialDomainsText.splitList()]
        }
        if selectedProfiles.contains("news") {
            profiles["news"] = ["include_domains": newsDomainsText.splitList(), "topic": "news"]
        }
        if selectedProfiles.contains("social_voice") {
            profiles["social_voice"] = ["include_domains": socialDomainsText.splitList()]
        }

        let competitorID = competitorKey.nilIfBlank ?? displayName.lowercased().replacingOccurrences(of: " ", with: "_")
        let aliases = aliasesText.splitList()
        let payload: [String: Any] = [
            "tavily": [
                "endpoint": "https://api.tavily.com/search",
                "frequency": SourceFrequency.globalDefault.rawValue,
                "search_depth": searchDepth.rawValue,
                "time_range": timeRange.rawValue,
                "max_results": maxResults,
                "include_raw_content": includeRawContent
            ],
            "competitors": [
                competitorID: [
                    "aliases": aliases.isEmpty ? [displayName] : aliases,
                    "markets": marketsText.splitList(),
                    "focus_market": focusMarket,
                    "languages": languagesText.splitList(),
                    "query_groups": groups,
                    "source_profiles": profiles
                ]
            ]
        ]

        guard JSONSerialization.isValidJSONObject(payload),
              let data = try? JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]),
              let value = String(data: data, encoding: .utf8) else {
            return "{}"
        }
        return value
    }

    private func generateAIRecommendation() async {
        isGeneratingRecommendation = true
        statusText = "AI 正在生成推荐..."
        defer { isGeneratingRecommendation = false }

        do {
            let prompt = TavilyRecommendationPrompt(
                competitorName: displayName.nilIfBlank ?? competitorKey,
                competitorKey: competitorKey.nilIfBlank ?? displayName.lowercased().replacingOccurrences(of: " ", with: "_"),
                markets: marketsText.splitList(),
                focusMarket: focusMarket,
                languages: languagesText.splitList(),
                businessDescription: businessDescription
            )
            jsonText = try await recommendationAction(prompt)
            showJSONEditor = true
            statusText = "AI 已生成推荐 JSON，可继续修改"
        } catch {
            statusText = "AI 推荐失败：\(error.localizedDescription)"
        }
    }

    private func resetDefaults() {
        competitorKey = "nubank"
        displayName = "Nubank"
        aliasesText = "Nubank\nNu Mexico\nNu México\nNu Holdings\nTarjeta Nu\nCuenta Nu"
        marketsText = "mexico\nbrazil\ncolombia"
        focusMarket = "mexico"
        languagesText = "es-MX\nen\npt-BR"
        selectedGroups = ["credit_card", "deposit_account", "growth", "regulation", "marketing"]
        customGroupName = ""
        customKeywordsText = ""
        selectedProfiles = ["official", "news"]
        officialDomainsText = "nu.com.mx\ninternational.nubank.com.br\ninvestidores.nu\ninvestors.nu\nsec.gov"
        newsDomainsText = "reuters.com\nbloomberg.com\nbusinesswire.com\nelfinanciero.com.mx\neleconomista.com.mx\nexpansion.mx\nforbes.com.mx"
        socialDomainsText = "reddit.com\nyoutube.com\nx.com\nfacebook.com"
        searchDepth = .basic
        timeRange = .week
        maxResults = 5
        includeRawContent = true
        jsonText = makeJSON()
        statusText = "已恢复示例"
    }

    private static let topicGroups: [SuggestedTopicGroup] = [
        SuggestedTopicGroup(id: "credit_card", title: "信用卡产品", hint: "额度、免年费、分期、还款", keywords: ["tarjeta de crédito", "sin anualidad", "MSI", "compras diferidas", "plan de pagos fijos", "límite de crédito", "fecha límite de pago"]),
        SuggestedTopicGroup(id: "deposit_account", title: "存款账户", hint: "账户、收益、借记、牌照", keywords: ["Cuenta Nu", "Cajitas", "rendimiento", "cuenta de débito", "Sofipo"]),
        SuggestedTopicGroup(id: "growth", title: "增长和份额", hint: "客户数、活跃、市场份额", keywords: ["clientes", "usuarios activos", "crecimiento", "market share", "issuer", "credit card issuer"]),
        SuggestedTopicGroup(id: "risk", title: "风控和资产质量", hint: "逾期、坏账、模型、审批", keywords: ["underwriting", "credit risk", "morosidad", "delinquency", "NPL", "NuFormer"]),
        SuggestedTopicGroup(id: "regulation", title: "监管和牌照", hint: "银行牌照、监管审批", keywords: ["licencia bancaria", "CNBV", "autorización", "Sofipo", "banco"]),
        SuggestedTopicGroup(id: "marketing", title: "营销活动", hint: "促销、返现、推荐、权益", keywords: ["promoción", "referidos", "campaña", "cashback", "beneficios"]),
        SuggestedTopicGroup(id: "app_reviews", title: "应用评价", hint: "评论、投诉、客服问题", keywords: ["opiniones", "reseñas", "quejas", "problemas", "atención al cliente"])
    ]
}

private struct SuggestedTopicGroup: Identifiable {
    var id: String
    var title: String
    var hint: String
    var keywords: [String]
}
