import SwiftUI

struct SourcesView: View {
    @EnvironmentObject private var store: RivalRadarStore
    @State private var selectedID: UUID?
    @State private var competitorID = UUID()
    @State private var name = ""
    @State private var type = SourceType.webPage
    @State private var url = ""
    @State private var keywordsText = ""
    @State private var frequency = SourceFrequency.globalDefault
    @State private var customFrequencyMinutes = 60
    @State private var requiresLogin = false
    @State private var chromeProfilePath = ""
    @State private var searchEndpoint = ""
    @State private var searchAPIKey = ""
    @State private var searchQueryTemplate = "{competitor} {keywords}"
    @State private var searchTitlePath = "title"
    @State private var searchURLPath = "url"
    @State private var tavilyTopic = TavilyTopic.news
    @State private var tavilySearchDepth = TavilySearchDepth.basic
    @State private var tavilyMaxResults = 5
    @State private var tavilyTimeRange = TavilyTimeRange.week
    @State private var tavilyIncludeRawContent = true
    @State private var tavilyIncludeDomainsText = ""
    @State private var tavilyExcludeDomainsText = ""
    @State private var tavilyCountry = ""
    @State private var tavilyLanguageHintsText = ""
    @State private var tavilyQueryGroup = ""
    @State private var tavilySourceProfile = ""
    @State private var tavilyJSONText = ""
    @State private var tavilyJSONStatus = ""
    @State private var bulkTavilyJSONText = ""
    @State private var bulkTavilyImportStatus = ""
    @State private var businessRecommendationJSONText = ""
    @State private var businessRecommendationStatus = ""
    @State private var isEnabled = true

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            businessRecommendationCard
            bulkImportCard

            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top, spacing: 16) {
                    sourceListCard
                        .frame(width: 320)
                    sourceConfigCard
                }

                VStack(alignment: .leading, spacing: 16) {
                    sourceListCard
                    sourceConfigCard
                }
            }
        }
        .onAppear {
            if competitorID == UUID(), let first = store.competitors.first {
                competitorID = first.id
            }
            if selectedID == nil {
                selectedID = store.sources.first?.id
                loadSelected()
            }
        }
    }

    private var bulkImportCard: some View {
        TavilyGuidedImportView(
            tavilyAPIKey: $store.tavilyAPIKey,
            jsonText: $bulkTavilyJSONText,
            statusText: $bulkTavilyImportStatus,
            recommendationAction: recommendBulkTavilyJSON,
            importAction: importBulkTavilyJSON
        )
    }

    private var businessRecommendationCard: some View {
        BusinessSourceRecommendationView(
            jsonText: $businessRecommendationJSONText,
            statusText: $businessRecommendationStatus,
            recommendationAction: recommendBusinessSourceJSON,
            importAction: importBusinessSourceJSON,
            summaryAction: summarizeBusinessSourceJSON
        )
    }

    private var sourceListCard: some View {
        SectionCard(title: "数据源", systemImage: "antenna.radiowaves.left.and.right") {
            VStack(alignment: .leading, spacing: 10) {
                Button {
                    store.addSource()
                    selectedID = store.sources.first?.id
                    loadSelected()
                } label: {
                    Label("添加数据源", systemImage: "plus")
                }
                .disabled(store.competitors.isEmpty)

                ForEach(store.sources) { source in
                    Button {
                        selectedID = source.id
                        loadSelected()
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: source.type.systemImage)
                                .frame(width: 18)
                                .foregroundStyle(.secondary)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(source.name)
                                    .lineLimit(1)
                                Text("\(store.competitorName(for: source.competitorID)) · \(store.frequencyLabel(for: source))")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                            Spacer()
                            if selectedID == source.id {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                    .buttonStyle(.plain)
                    Divider()
                }
            }
        }
    }

    private var sourceConfigCard: some View {
        SectionCard(title: "数据源配置", systemImage: "slider.horizontal.3") {
            if store.competitors.isEmpty {
                Text("请先添加竞品，或使用上方 Tavily 批量 JSON 导入。")
                    .foregroundStyle(.secondary)
            } else if selectedID == nil {
                Text("选择或添加一个数据源。")
                    .foregroundStyle(.secondary)
            } else {
                form
            }
        }
    }

    private var form: some View {
        VStack(alignment: .leading, spacing: 12) {
            TextField("名称", text: $name)
                .textFieldStyle(.roundedBorder)

                Picker("所属竞品", selection: $competitorID) {
                ForEach(store.competitors) { competitor in
                    Text(competitor.name).tag(competitor.id)
                }
            }

            Picker("类型", selection: $type) {
                ForEach(SourceType.allCases) { type in
                    Label(type.label, systemImage: type.systemImage).tag(type)
                }
            }
            .pickerStyle(.segmented)

            if type != .tavilySearch {
                AdaptiveTextArea(
                    placeholder: type == .searchAPI ? "通用搜索 URL 或含 {query} 的模板" : "网址",
                    text: $url,
                    minLines: 1,
                    maxLines: 4
                )
            }

            AdaptiveTextArea(placeholder: "关键词，用逗号或换行分隔", text: $keywordsText, minLines: 2, maxLines: 10)

            Picker("频率", selection: $frequency) {
                ForEach(SourceFrequency.sourceOptions) { frequency in
                    Text(frequency.label).tag(frequency)
                }
            }
            .help("默认跟随设置页里的全局采集频率；也可以给单个数据源单独覆盖。")

            if frequency == .globalDefault {
                Text("当前全局频率：\(store.globalFrequencyLabel)。批量导入和新建数据源默认使用这个设置。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if frequency == .custom {
                HStack {
                    Stepper("自定义间隔 \(customFrequencyMinutes) 分钟", value: $customFrequencyMinutes, in: 1...43_200, step: 5)
                    TextField("分钟", value: $customFrequencyMinutes, format: .number)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 90)
                }
                .onChange(of: customFrequencyMinutes) { newValue in
                    customFrequencyMinutes = RivalRadarStore.clampedFrequencyMinutes(newValue)
                }
            }

            Toggle("启用", isOn: $isEnabled)
            Toggle("需要 Chrome 登录会话", isOn: $requiresLogin)

            if requiresLogin {
                Picker("Chrome 用户资料", selection: $chromeProfilePath) {
                    Text("不指定").tag("")
                    ForEach(store.chromeProfiles) { profile in
                        Text(profile.name).tag(profile.path)
                    }
                }
            }

            if type == .searchAPI {
                Divider()
                AdaptiveTextArea(placeholder: "搜索接口地址（可选，优先于 URL）", text: $searchEndpoint, minLines: 1, maxLines: 4)
                SecureField("搜索接口密钥（可选）", text: $searchAPIKey)
                    .textFieldStyle(.roundedBorder)
                AdaptiveTextArea(placeholder: "查询模板", text: $searchQueryTemplate, minLines: 1, maxLines: 5)
                HStack {
                    TextField("标题字段路径", text: $searchTitlePath)
                        .textFieldStyle(.roundedBorder)
                    TextField("URL 字段路径", text: $searchURLPath)
                        .textFieldStyle(.roundedBorder)
                }
            }

            if type == .tavilySearch {
                Divider()
                Label(
                    store.tavilyAPIKey.nilIfBlank == nil ? "Tavily 接口密钥未配置，请到“设置”页填写" : "Tavily 接口密钥已在“设置”页统一配置",
                    systemImage: store.tavilyAPIKey.nilIfBlank == nil ? "exclamationmark.triangle" : "checkmark.seal"
                )
                .foregroundStyle(store.tavilyAPIKey.nilIfBlank == nil ? Color.orange : Color.secondary)

                AdaptiveTextArea(placeholder: "查询模板", text: $searchQueryTemplate, minLines: 1, maxLines: 5)

                AdaptiveTextArea(placeholder: "Tavily 接口地址（默认 https://api.tavily.com/search）", text: $searchEndpoint, minLines: 1, maxLines: 4)

                HStack {
                    Picker("主题类型", selection: $tavilyTopic) {
                        ForEach(TavilyTopic.allCases) { topic in
                            Text(topic.label).tag(topic)
                        }
                    }

                    Picker("深度", selection: $tavilySearchDepth) {
                        ForEach(TavilySearchDepth.allCases) { depth in
                            Text(depth.label).tag(depth)
                        }
                    }
                }

                HStack {
                    Picker("时间范围", selection: $tavilyTimeRange) {
                        ForEach(TavilyTimeRange.allCases) { range in
                            Text(range.label).tag(range)
                        }
                    }

                    Stepper("结果数 \(tavilyMaxResults)", value: $tavilyMaxResults, in: 1...20)
                }

                Toggle("包含 Tavily raw_content 供 DeepSeek 分析", isOn: $tavilyIncludeRawContent)

                AdaptiveTextArea(placeholder: "包含域名，用逗号或换行分隔", text: $tavilyIncludeDomainsText, minLines: 2, maxLines: 12)

                AdaptiveTextArea(placeholder: "排除域名，用逗号或换行分隔", text: $tavilyExcludeDomainsText, minLines: 1, maxLines: 10)

                HStack {
                    TextField("重点市场/国家", text: $tavilyCountry)
                        .textFieldStyle(.roundedBorder)
                    TextField("语言提示", text: $tavilyLanguageHintsText)
                        .textFieldStyle(.roundedBorder)
                }

                HStack {
                    TextField("关注主题组", text: $tavilyQueryGroup)
                        .textFieldStyle(.roundedBorder)
                    TextField("信息来源组", text: $tavilySourceProfile)
                        .textFieldStyle(.roundedBorder)
                }

                DisclosureGroup("JSON 配置") {
                    VStack(alignment: .leading, spacing: 10) {
                        AdaptiveTextArea(placeholder: "JSON 配置", text: $tavilyJSONText, minLines: 10, maxLines: 28, monospaced: true)

                        HStack {
                            Button {
                                refreshTavilyJSON()
                            } label: {
                                Label("生成当前 JSON", systemImage: "arrow.clockwise")
                            }

                            Button {
                                applyTavilyJSONAndSave()
                            } label: {
                                Label("套用 JSON 并保存", systemImage: "checkmark")
                            }

                            if !tavilyJSONStatus.isEmpty {
                                Text(tavilyJSONStatus)
                                    .font(.caption)
                                    .foregroundStyle(tavilyJSONStatus.contains("失败") ? Color.red : Color.secondary)
                            }
                        }

                        Text("支持常见字段写法和 Tavily 原生字段名，例如 searchDepth/search_depth、maxResults/max_results、includeRawContent/include_raw_content。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            HStack {
                Button {
                    save()
                } label: {
                    Label("保存", systemImage: "checkmark")
                }
                .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                Button {
                    save()
                    if let source = store.sources.first(where: { $0.id == selectedID }) {
                        store.runNow(source: source)
                    }
                } label: {
                    Label("保存并运行", systemImage: "play")
                }
                .disabled(store.isRunning)

                Button(role: .destructive) {
                    delete()
                } label: {
                    Label("删除", systemImage: "trash")
                }
            }
        }
    }

    private func loadSelected() {
        guard let selectedID,
              let source = store.sources.first(where: { $0.id == selectedID }) else {
            if let first = store.competitors.first {
                competitorID = first.id
            }
            name = ""
            type = .webPage
            url = ""
            keywordsText = ""
            frequency = .globalDefault
            customFrequencyMinutes = 60
            requiresLogin = false
            chromeProfilePath = ""
            searchEndpoint = ""
            searchAPIKey = ""
            searchQueryTemplate = "{competitor} {keywords}"
            searchTitlePath = "title"
            searchURLPath = "url"
            tavilyTopic = .news
            tavilySearchDepth = .basic
            tavilyMaxResults = 5
            tavilyTimeRange = .week
            tavilyIncludeRawContent = true
            tavilyIncludeDomainsText = ""
            tavilyExcludeDomainsText = ""
            tavilyCountry = ""
            tavilyLanguageHintsText = ""
            tavilyQueryGroup = ""
            tavilySourceProfile = ""
            tavilyJSONText = defaultTavilyJSON()
            tavilyJSONStatus = ""
            isEnabled = true
            return
        }
        competitorID = source.competitorID
        name = source.name
        type = source.type
        url = source.url
        keywordsText = source.keywords.joined(separator: "\n")
        frequency = source.frequency
        customFrequencyMinutes = source.customFrequencyMinutes
        requiresLogin = source.requiresLogin
        chromeProfilePath = source.chromeProfilePath
        searchEndpoint = source.searchEndpoint
        searchAPIKey = source.searchAPIKey
        searchQueryTemplate = source.searchQueryTemplate
        searchTitlePath = source.searchTitlePath
        searchURLPath = source.searchURLPath
        tavilyTopic = source.tavilyTopic
        tavilySearchDepth = source.tavilySearchDepth
        tavilyMaxResults = source.tavilyMaxResults
        tavilyTimeRange = source.tavilyTimeRange
        tavilyIncludeRawContent = source.tavilyIncludeRawContent
        tavilyIncludeDomainsText = source.tavilyIncludeDomains.joined(separator: "\n")
        tavilyExcludeDomainsText = source.tavilyExcludeDomains.joined(separator: "\n")
        tavilyCountry = source.tavilyCountry
        tavilyLanguageHintsText = source.tavilyLanguageHints.joined(separator: "\n")
        tavilyQueryGroup = source.tavilyQueryGroup
        tavilySourceProfile = source.tavilySourceProfile
        refreshTavilyJSON()
        tavilyJSONStatus = ""
        isEnabled = source.isEnabled
    }

    private func save() {
        guard let selectedID else { return }
        let existing = store.sources.first(where: { $0.id == selectedID })
        store.saveSource(
            IntelligenceSource(
                id: selectedID,
                competitorID: competitorID,
                name: name.trimmingCharacters(in: .whitespacesAndNewlines),
                type: type,
                url: url.trimmingCharacters(in: .whitespacesAndNewlines),
                keywords: keywordsText.splitList(),
                frequency: frequency,
                customFrequencyMinutes: RivalRadarStore.clampedFrequencyMinutes(customFrequencyMinutes),
                requiresLogin: requiresLogin,
                chromeProfilePath: chromeProfilePath,
                searchEndpoint: searchEndpoint,
                searchAPIKey: type == .tavilySearch ? "" : searchAPIKey,
                searchQueryTemplate: searchQueryTemplate,
                searchTitlePath: searchTitlePath,
                searchURLPath: searchURLPath,
                tavilyTopic: tavilyTopic,
                tavilySearchDepth: tavilySearchDepth,
                tavilyMaxResults: tavilyMaxResults,
                tavilyTimeRange: tavilyTimeRange,
                tavilyIncludeRawContent: tavilyIncludeRawContent,
                tavilyIncludeDomains: tavilyIncludeDomainsText.splitList(),
                tavilyExcludeDomains: tavilyExcludeDomainsText.splitList(),
                tavilyCountry: tavilyCountry,
                tavilyLanguageHints: tavilyLanguageHintsText.splitList(),
                tavilyQueryGroup: tavilyQueryGroup,
                tavilySourceProfile: tavilySourceProfile,
                isEnabled: isEnabled,
                lastRunAt: existing?.lastRunAt
            )
        )
        refreshTavilyJSON()
    }

    private func delete() {
        guard let selectedID,
              let source = store.sources.first(where: { $0.id == selectedID }) else { return }
        store.deleteSource(source)
        self.selectedID = store.sources.first?.id
        loadSelected()
    }

    private func applyTavilyJSONAndSave() {
        guard let data = tavilyJSONText.data(using: .utf8) else {
            tavilyJSONStatus = "JSON 失败：文本编码无效"
            return
        }

        do {
            let config = try JSONDecoder().decode(TavilySourceJSONConfig.self, from: data)
            if let apiKey = config.apiKey {
                store.tavilyAPIKey = apiKey
            }
            if let endpoint = config.endpoint {
                searchEndpoint = endpoint
            }
            if let queryTemplate = config.queryTemplate {
                searchQueryTemplate = queryTemplate
            }
            if let topic = config.topic,
               let parsed = TavilyTopic(rawValue: topic) {
                tavilyTopic = parsed
            }
            if let searchDepth = config.searchDepth,
               let parsed = TavilySearchDepth(rawValue: searchDepth) {
                tavilySearchDepth = parsed
            }
            if let timeRange = config.timeRange {
                tavilyTimeRange = TavilyTimeRange(rawValue: timeRange) ?? TavilyTimeRange.allCases.first(where: { $0.apiValue == timeRange }) ?? tavilyTimeRange
            }
            if let maxResults = config.maxResults {
                tavilyMaxResults = max(1, min(20, maxResults))
            }
            if let includeRawContent = config.includeRawContent {
                tavilyIncludeRawContent = includeRawContent
            }

            type = .tavilySearch
            save()
            tavilyJSONStatus = "JSON 已保存"
        } catch {
            tavilyJSONStatus = "JSON 失败：\(error.localizedDescription)"
        }
    }

    private func refreshTavilyJSON() {
        tavilyJSONText = TavilySourceJSONConfig.jsonString(
            apiKey: store.tavilyAPIKey,
            endpoint: searchEndpoint,
            queryTemplate: searchQueryTemplate,
            topic: tavilyTopic,
            searchDepth: tavilySearchDepth,
            timeRange: tavilyTimeRange,
            maxResults: tavilyMaxResults,
            includeRawContent: tavilyIncludeRawContent
        )
    }

    private func defaultTavilyJSON() -> String {
        TavilySourceJSONConfig.jsonString(
            apiKey: "",
            endpoint: "https://api.tavily.com/search",
            queryTemplate: "{competitor} {keywords}",
            topic: .news,
            searchDepth: .basic,
            timeRange: .week,
            maxResults: 5,
            includeRawContent: true
        )
    }

    private func importBulkTavilyJSON() {
        do {
            let result = try store.importTavilyBulkConfiguration(
                jsonText: bulkTavilyJSONText
            )
            bulkTavilyImportStatus = "已导入 \(result.competitors) 个竞品，\(result.sources) 个数据源"
            selectedID = store.sources.first?.id
            loadSelected()
        } catch {
            bulkTavilyImportStatus = "导入失败：\(error.localizedDescription)"
        }
    }

    private func recommendBulkTavilyJSON(_ prompt: TavilyRecommendationPrompt) async throws -> String {
        try await store.recommendTavilyConfiguration(prompt: prompt)
    }

    private func recommendBusinessSourceJSON(_ businessDescription: String, _ competitorCount: Int) async throws -> String {
        try await store.recommendSourceConfiguration(
            businessDescription: businessDescription,
            competitorCount: competitorCount
        )
    }

    private func importBusinessSourceJSON() throws -> SourceRecommendationImportResult {
        let result = try store.importSourceRecommendationConfiguration(
            jsonText: businessRecommendationJSONText
        )
        selectedID = store.sources.first?.id
        loadSelected()
        return result
    }

    private func summarizeBusinessSourceJSON(_ jsonText: String) throws -> SourceRecommendationSummary {
        try store.summarizeSourceRecommendationConfiguration(jsonText: jsonText)
    }

}
