import Foundation

@MainActor
final class RivalRadarStore: ObservableObject {
    @Published private(set) var competitors: [Competitor] = []
    @Published private(set) var sources: [IntelligenceSource] = []
    @Published private(set) var items: [IntelligenceItem] = []
    @Published private(set) var runLogs: [RunLog] = []
    @Published private(set) var isRunning = false
    @Published private(set) var statusText = "就绪"
    @Published private(set) var lastGeneratedReports: [URL] = []

    @Published var apiKey: String {
        didSet { UserDefaults.standard.set(apiKey, forKey: Self.apiKeyKey) }
    }

    @Published var baseURL: String {
        didSet { UserDefaults.standard.set(baseURL, forKey: Self.baseURLKey) }
    }

    @Published var model: String {
        didSet { UserDefaults.standard.set(model, forKey: Self.modelKey) }
    }

    @Published var tavilyAPIKey: String {
        didSet { UserDefaults.standard.set(tavilyAPIKey, forKey: Self.tavilyAPIKeyKey) }
    }

    @Published var globalFrequency: SourceFrequency {
        didSet {
            let persisted = globalFrequency == .globalDefault ? SourceFrequency.daily : globalFrequency
            UserDefaults.standard.set(persisted.rawValue, forKey: Self.globalFrequencyKey)
        }
    }

    @Published var globalCustomFrequencyMinutes: Int {
        didSet {
            globalCustomFrequencyMinutes = Self.clampedFrequencyMinutes(globalCustomFrequencyMinutes)
            UserDefaults.standard.set(globalCustomFrequencyMinutes, forKey: Self.globalCustomFrequencyMinutesKey)
        }
    }

    @Published var reportsFolder: String {
        didSet { UserDefaults.standard.set(reportsFolder, forKey: Self.reportsFolderKey) }
    }

    @Published var notificationsEnabled: Bool {
        didSet {
            UserDefaults.standard.set(notificationsEnabled, forKey: Self.notificationsEnabledKey)
            if notificationsEnabled {
                notificationService.requestAuthorizationIfNeeded()
            }
        }
    }

    private static let apiKeyKey = "api.key"
    private static let baseURLKey = "api.baseURL"
    private static let modelKey = "api.model"
    private static let tavilyAPIKeyKey = "tavily.apiKey"
    private static let globalFrequencyKey = "scheduler.globalFrequency"
    private static let globalCustomFrequencyMinutesKey = "scheduler.globalCustomFrequencyMinutes"
    private static let reportsFolderKey = "reports.folder"
    private static let notificationsEnabledKey = "notifications.enabled"

    private let database: SQLiteDatabase
    private let collector = SourceCollector()
    private let analyzer = IntelligenceAnalyzer()
    private let tavilyAdvisor = TavilyConfigurationAdvisor()
    private let sourceRecommendationAdvisor = SourceRecommendationAdvisor()
    private let reportGenerator = ReportGenerator()
    private let notificationService = NotificationService()
    private var schedulerTimer: Timer?

    init(database: SQLiteDatabase? = nil) {
        do {
            self.database = try database ?? SQLiteDatabase()
        } catch {
            fatalError("无法初始化竞品雷达数据库：\(error.localizedDescription)")
        }

        apiKey = UserDefaults.standard.string(forKey: Self.apiKeyKey) ?? ""
        baseURL = UserDefaults.standard.string(forKey: Self.baseURLKey) ?? "https://api.deepseek.com"
        model = UserDefaults.standard.string(forKey: Self.modelKey) ?? "deepseek-v4-flash"
        tavilyAPIKey = UserDefaults.standard.string(forKey: Self.tavilyAPIKeyKey) ?? ""
        let savedGlobalFrequency = SourceFrequency(rawValue: UserDefaults.standard.string(forKey: Self.globalFrequencyKey) ?? "") ?? .daily
        globalFrequency = savedGlobalFrequency == .globalDefault ? .daily : savedGlobalFrequency
        globalCustomFrequencyMinutes = Self.clampedFrequencyMinutes(
            UserDefaults.standard.object(forKey: Self.globalCustomFrequencyMinutesKey) as? Int ?? 60
        )
        reportsFolder = UserDefaults.standard.string(forKey: Self.reportsFolderKey)
            ?? FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Documents/RivalRadar/Reports", isDirectory: true)
                .path
        notificationsEnabled = UserDefaults.standard.object(forKey: Self.notificationsEnabledKey) as? Bool ?? true

        reload()
        startScheduler()
        if notificationsEnabled {
            notificationService.requestAuthorizationIfNeeded()
        }
    }

    deinit {
        schedulerTimer?.invalidate()
    }

    var enabledSources: [IntelligenceSource] {
        sources.filter { source in
            source.isEnabled && competitors.contains { $0.id == source.competitorID && $0.isEnabled }
        }
    }

    var todaysItems: [IntelligenceItem] {
        database.loadItems(on: Date())
    }

    var chromeProfiles: [ChromeProfile] {
        ChromeSessionReader().availableProfiles()
    }

    func competitorName(for id: UUID) -> String {
        competitors.first(where: { $0.id == id })?.name ?? "未知竞品"
    }

    func sourceName(for id: UUID) -> String {
        sources.first(where: { $0.id == id })?.name ?? "未知来源"
    }

    var globalFrequencyLabel: String {
        frequencyLabel(frequency: globalFrequency, customMinutes: globalCustomFrequencyMinutes)
    }

    func frequencyLabel(for source: IntelligenceSource) -> String {
        if source.frequency == .globalDefault {
            return "跟随全局：\(globalFrequencyLabel)"
        }
        return frequencyLabel(frequency: source.frequency, customMinutes: source.customFrequencyMinutes)
    }

    func reload() {
        competitors = database.loadCompetitors()
        sources = database.loadSources()
        items = database.loadItems()
        runLogs = database.loadRunLogs()
    }

    func saveCompetitor(_ competitor: Competitor) {
        database.upsertCompetitor(competitor)
        reload()
    }

    func addCompetitor() {
        let competitor = Competitor(name: "新竞品")
        database.upsertCompetitor(competitor)
        reload()
    }

    func deleteCompetitor(_ competitor: Competitor) {
        database.deleteCompetitor(id: competitor.id)
        reload()
    }

    func saveSource(_ source: IntelligenceSource) {
        database.upsertSource(source)
        reload()
    }

    func addSource() {
        guard let competitor = competitors.first else {
            statusText = "请先添加竞品"
            return
        }
        let source = IntelligenceSource(
            competitorID: competitor.id,
            name: "新数据源",
            type: .webPage,
            url: "https://"
        )
        database.upsertSource(source)
        reload()
    }

    func deleteSource(_ source: IntelligenceSource) {
        database.deleteSource(id: source.id)
        reload()
    }

    func runAllNow() {
        Task {
            await runSources(enabledSources, reason: "手动运行全部")
        }
    }

    func runNow(source: IntelligenceSource) {
        Task {
            await runSources([source], reason: "手动运行数据源")
        }
    }

    func generateTodayReports() {
        do {
            let today = database.loadItems(on: Date())
            let urls = try reportGenerator.generateReports(
                items: today,
                competitors: competitors,
                date: Date(),
                reportsFolder: reportsFolder
            )
            database.markReported(ids: today.map(\.id))
            lastGeneratedReports = urls
            statusText = urls.isEmpty ? "今天暂无情报可生成报告" : "已生成 \(urls.count) 份 Word 报告"
            reload()
        } catch {
            statusText = error.localizedDescription
        }
    }

    func recommendTavilyConfiguration(prompt: TavilyRecommendationPrompt) async throws -> String {
        try await tavilyAdvisor.recommendJSON(
            prompt: prompt,
            configuration: OpenAIConfiguration(apiKey: apiKey, baseURL: baseURL, model: model)
        )
    }

    func recommendSourceConfiguration(
        businessDescription: String,
        competitorCount: Int
    ) async throws -> String {
        try await sourceRecommendationAdvisor.recommendJSON(
            businessDescription: businessDescription,
            competitorCount: competitorCount,
            tavilyAPIKey: tavilyAPIKey,
            configuration: OpenAIConfiguration(apiKey: apiKey, baseURL: baseURL, model: model)
        )
    }

    func summarizeSourceRecommendationConfiguration(jsonText: String) throws -> SourceRecommendationSummary {
        let configuration = try decodeSourceRecommendationConfiguration(jsonText: jsonText)
        return SourceRecommendationImportMapper.summary(for: configuration)
    }

    func importSourceRecommendationConfiguration(jsonText: String) throws -> SourceRecommendationImportResult {
        let configuration = try decodeSourceRecommendationConfiguration(jsonText: jsonText)

        var importedCompetitors = 0
        var importedSources = 0
        var disabledSources = 0
        var skippedSources = 0
        var currentCompetitors = database.loadCompetitors()
        var currentSources = database.loadSources()

        for (key, config) in configuration.competitors.sorted(by: { $0.key < $1.key }) {
            let displayName = SourceRecommendationImportMapper.displayName(key: key, config: config)
            let existingCompetitor = currentCompetitors.first { candidate in
                candidate.name.caseInsensitiveCompare(displayName) == .orderedSame ||
                candidate.name.caseInsensitiveCompare(key) == .orderedSame ||
                candidate.aliases.contains { alias in
                    alias.caseInsensitiveCompare(key) == .orderedSame ||
                    alias.caseInsensitiveCompare(displayName) == .orderedSame
                }
            }

            let competitor = SourceRecommendationImportMapper.competitor(
                key: key,
                config: config,
                existing: existingCompetitor
            )
            database.upsertCompetitor(competitor)
            importedCompetitors += 1

            for (index, sourceConfig) in config.sources.enumerated() {
                let sourceName = SourceRecommendationImportMapper.sourceName(
                    for: sourceConfig,
                    competitorName: competitor.name,
                    index: index
                )
                let existingSource = currentSources.first {
                    $0.competitorID == competitor.id &&
                    $0.name.caseInsensitiveCompare(sourceName) == .orderedSame
                }
                guard let source = SourceRecommendationImportMapper.source(
                    from: sourceConfig,
                    competitor: competitor,
                    competitorConfig: config,
                    existing: existingSource,
                    index: index
                ) else {
                    skippedSources += 1
                    continue
                }
                database.upsertSource(source)
                importedSources += 1
                if !source.isEnabled {
                    disabledSources += 1
                }
                currentSources = database.loadSources()
            }

            currentCompetitors = database.loadCompetitors()
        }

        reload()
        return SourceRecommendationImportResult(
            competitors: importedCompetitors,
            sources: importedSources,
            disabledSources: disabledSources,
            skippedSources: skippedSources
        )
    }

    func importTavilyBulkConfiguration(jsonText: String, fallbackAPIKey: String? = nil) throws -> (competitors: Int, sources: Int) {
        guard let data = jsonText.data(using: .utf8) else {
            throw ImportError.invalidEncoding
        }
        let configuration: TavilyBulkConfiguration
        do {
            configuration = try JSONDecoder().decode(TavilyBulkConfiguration.self, from: data)
        } catch {
            throw ImportError.invalidJSON(Self.describeImportDecodeError(error))
        }
        let defaults = configuration.tavily ?? TavilyBulkDefaults()
        if let configuredKey = defaults.apiKey?.nilIfBlank {
            tavilyAPIKey = configuredKey
        }
        if tavilyAPIKey.nilIfBlank == nil, let fallbackAPIKey = fallbackAPIKey?.nilIfBlank {
            tavilyAPIKey = fallbackAPIKey
        }

        var importedCompetitors = 0
        var importedSources = 0
        var currentCompetitors = database.loadCompetitors()
        var currentSources = database.loadSources()

        for (key, config) in configuration.competitors.sorted(by: { $0.key < $1.key }) {
            let displayName = config.aliases.first?.nilIfBlank ?? key
            let keywords = unique(config.queryGroups.values.flatMap { $0 })
            let aliases = unique(config.aliases + [key]).filter { $0.caseInsensitiveCompare(displayName) != .orderedSame }
            let notes = [
                config.markets.isEmpty ? nil : "监控市场：\(config.markets.joined(separator: ", "))",
                config.focusMarket.nilIfBlank.map { "重点市场：\($0)" },
                config.languages.isEmpty ? nil : "语言：\(config.languages.joined(separator: ", "))",
                "由 Tavily 批量 JSON 导入。"
            ]
            .compactMap { $0 }
            .joined(separator: "\n")

            let existing = currentCompetitors.first { candidate in
                candidate.name.caseInsensitiveCompare(displayName) == .orderedSame ||
                candidate.name.caseInsensitiveCompare(key) == .orderedSame ||
                candidate.aliases.contains { alias in
                    alias.caseInsensitiveCompare(key) == .orderedSame ||
                    alias.caseInsensitiveCompare(displayName) == .orderedSame
                }
            }

            let competitor = Competitor(
                id: existing?.id ?? UUID(),
                name: displayName,
                aliases: aliases,
                keywords: keywords,
                notes: notes,
                isEnabled: true,
                createdAt: existing?.createdAt ?? Date()
            )
            database.upsertCompetitor(competitor)
            importedCompetitors += 1

            let sourceProfiles = config.sourceProfiles.isEmpty
                ? ["default": TavilySourceProfileConfiguration(includeDomains: [], excludeDomains: [], topic: nil, searchDepth: nil, timeRange: nil, maxResults: nil)]
                : config.sourceProfiles

            for (groupName, groupKeywords) in config.queryGroups.sorted(by: { $0.key < $1.key }) {
                for (profileName, profile) in sourceProfiles.sorted(by: { $0.key < $1.key }) {
                    let sourceName = "\(displayName) · \(groupName) · \(profileName)"
                    let existingSource = currentSources.first {
                        $0.competitorID == competitor.id && $0.name.caseInsensitiveCompare(sourceName) == .orderedSame
                    }
                    let topic = profile.topic ?? defaults.topic ?? defaultTopic(for: profileName)
                    let country = config.focusMarket.nilIfBlank ?? config.markets.first ?? ""
                    let source = IntelligenceSource(
                        id: existingSource?.id ?? UUID(),
                        competitorID: competitor.id,
                        name: sourceName,
                        type: .tavilySearch,
                        url: "https://api.tavily.com/search",
                        keywords: groupKeywords,
                        frequency: defaults.frequency ?? .globalDefault,
                        customFrequencyMinutes: defaults.customFrequencyMinutes ?? 60,
                        searchEndpoint: defaults.endpoint ?? "https://api.tavily.com/search",
                        searchAPIKey: "",
                        searchQueryTemplate: "\"{competitor}\" {aliases} {keywords} {focus_market} {languages}",
                        tavilyTopic: topic,
                        tavilySearchDepth: profile.searchDepth ?? defaults.searchDepth ?? .basic,
                        tavilyMaxResults: profile.maxResults ?? defaults.maxResults ?? 5,
                        tavilyTimeRange: profile.timeRange ?? defaults.timeRange ?? .week,
                        tavilyIncludeRawContent: defaults.includeRawContent ?? true,
                        tavilyIncludeDomains: profile.includeDomains,
                        tavilyExcludeDomains: profile.excludeDomains,
                        tavilyCountry: country,
                        tavilyLanguageHints: config.languages,
                        tavilyQueryGroup: groupName,
                        tavilySourceProfile: profileName,
                        isEnabled: true,
                        lastRunAt: existingSource?.lastRunAt
                    )
                    database.upsertSource(source)
                    importedSources += 1
                }
            }

            currentCompetitors = database.loadCompetitors()
            currentSources = database.loadSources()
        }

        reload()
        return (importedCompetitors, importedSources)
    }

    private func decodeSourceRecommendationConfiguration(jsonText: String) throws -> SourceRecommendationConfiguration {
        guard let data = jsonText.data(using: .utf8) else {
            throw ImportError.invalidEncoding
        }
        do {
            return try JSONDecoder().decode(SourceRecommendationConfiguration.self, from: data)
        } catch {
            throw ImportError.invalidSourceRecommendationJSON(Self.describeImportDecodeError(error))
        }
    }

    private func startScheduler() {
        schedulerTimer?.invalidate()
        schedulerTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor in
                await self?.runDueSources()
            }
        }
    }

    private func runDueSources() async {
        let due = enabledSources.filter(isDue)
        guard !due.isEmpty else { return }
        await runSources(due, reason: "定时运行")
    }

    private func isDue(_ source: IntelligenceSource) -> Bool {
        guard let interval = effectiveInterval(for: source) else { return false }
        guard let lastRunAt = source.lastRunAt else { return true }
        return Date().timeIntervalSince(lastRunAt) >= interval
    }

    private func effectiveInterval(for source: IntelligenceSource) -> TimeInterval? {
        if source.frequency == .globalDefault {
            return globalFrequency.interval(customMinutes: globalCustomFrequencyMinutes)
        }
        return source.frequency.interval(customMinutes: source.customFrequencyMinutes)
    }

    private func frequencyLabel(frequency: SourceFrequency, customMinutes: Int) -> String {
        switch frequency {
        case .custom:
            return "每 \(Self.clampedFrequencyMinutes(customMinutes)) 分钟"
        default:
            return frequency.label
        }
    }

    static func clampedFrequencyMinutes(_ value: Int) -> Int {
        min(max(value, 1), 30 * 24 * 60)
    }

    private func runSources(_ targetSources: [IntelligenceSource], reason: String) async {
        guard !isRunning else {
            statusText = "已有采集任务运行中"
            return
        }
        guard !targetSources.isEmpty else {
            statusText = "没有可运行的数据源"
            return
        }

        isRunning = true
        statusText = "\(reason)：\(targetSources.count) 个数据源"

        var allNewItems: [IntelligenceItem] = []
        for source in targetSources {
            let newItems = await run(source: source)
            allNewItems.append(contentsOf: newItems)
        }

        if !allNewItems.isEmpty {
            do {
                let today = database.loadItems(on: Date())
                let urls = try reportGenerator.generateReports(
                    items: today,
                    competitors: competitors,
                    date: Date(),
                    reportsFolder: reportsFolder
                )
                database.markReported(ids: today.map(\.id))
                lastGeneratedReports = urls
            } catch {
                statusText = "情报已保存，但报告生成失败：\(error.localizedDescription)"
            }

            if notificationsEnabled {
                notificationService.notifyNewItems(allNewItems, competitors: competitors)
                database.markNotified(ids: allNewItems.map(\.id))
            }
        }

        reload()
        statusText = allNewItems.isEmpty ? "采集完成：无新增" : "采集完成：新增 \(allNewItems.count) 条"
        isRunning = false
    }

    private func unique(_ values: [String]) -> [String] {
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

    private func defaultTopic(for profileName: String) -> TavilyTopic {
        let normalized = profileName.lowercased()
        if normalized.contains("news") { return .news }
        if normalized.contains("finance") || normalized.contains("invest") { return .finance }
        return .general
    }

    private func run(source: IntelligenceSource) async -> [IntelligenceItem] {
        guard let competitor = competitors.first(where: { $0.id == source.competitorID }) else {
            return []
        }

        var log = RunLog(sourceID: source.id, sourceName: source.name, message: "开始采集")
        database.upsertRunLog(log)
        runLogs = database.loadRunLogs()

        do {
            let rawItems = try await collector.collect(source: effectiveSourceForRun(source), competitor: competitor)
            var newItems: [IntelligenceItem] = []
            var analysisWarnings: [String] = []
            var irrelevantItems: [String] = []
            let existingItems = database.loadItems(limit: 1_000)

            for rawItem in rawItems {
                let fingerprints = DedupeService.fingerprints(for: rawItem, competitor: competitor)
                if database.isDuplicate(
                    urlHash: fingerprints.urlHash,
                    titleHash: fingerprints.titleHash,
                    contentHash: fingerprints.contentHash
                ) {
                    continue
                }
                if existingItems.contains(where: { $0.competitorID == competitor.id && DedupeService.isSimilarTitle($0.title, rawItem.title) }) ||
                    newItems.contains(where: { DedupeService.isSimilarTitle($0.title, rawItem.title) }) {
                    continue
                }

                let analysis = await analyzer.analyze(
                    raw: rawItem,
                    competitor: competitor,
                    source: source,
                    configuration: OpenAIConfiguration(apiKey: apiKey, baseURL: baseURL, model: model)
                )
                if let warning = analysis.warning?.nilIfBlank {
                    analysisWarnings.append("\(rawItem.title.nilIfBlank ?? rawItem.url)：\(warning)")
                }
                guard analysis.isRelevant else {
                    irrelevantItems.append("\(rawItem.title.nilIfBlank ?? rawItem.url)：\(analysis.relevanceReason)")
                    continue
                }

                let item = IntelligenceItem(
                    sourceID: source.id,
                    competitorID: competitor.id,
                    title: rawItem.title.nilIfBlank ?? rawItem.url,
                    url: rawItem.url,
                    normalizedURL: fingerprints.normalizedURL,
                    domain: fingerprints.domain,
                    rawContent: rawItem.content,
                    publishedAt: rawItem.publishedAt,
                    category: analysis.category,
                    summary: analysis.summary,
                    impact: analysis.impact,
                    importance: analysis.importance,
                    urlHash: fingerprints.urlHash,
                    titleHash: fingerprints.titleHash,
                    contentHash: fingerprints.contentHash
                )

                if database.insertItemIfNew(item) {
                    newItems.append(item)
                }
            }

            database.updateSourceLastRun(id: source.id, date: Date())
            log.finishedAt = Date()
            log.status = .success
            log.message = runLogMessage(
                rawCount: rawItems.count,
                newCount: newItems.count,
                irrelevantItems: irrelevantItems,
                analysisWarnings: analysisWarnings
            )
            log.newCount = newItems.count
            database.upsertRunLog(log)
            return newItems
        } catch {
            log.finishedAt = Date()
            log.status = .failed
            log.message = error.localizedDescription
            log.newCount = 0
            database.upsertRunLog(log)
            return []
        }
    }

    private func effectiveSourceForRun(_ source: IntelligenceSource) -> IntelligenceSource {
        guard source.type == .tavilySearch else { return source }
        var effective = source
        effective.searchAPIKey = source.searchAPIKey.nilIfBlank ?? tavilyAPIKey
        return effective
    }

    private func runLogMessage(
        rawCount: Int,
        newCount: Int,
        irrelevantItems: [String],
        analysisWarnings: [String]
    ) -> String {
        var parts = [rawCount == 0 ? "未发现可解析内容" : "采集 \(rawCount) 条，新增 \(newCount) 条，过滤无关 \(irrelevantItems.count) 条"]
        let uniqueIrrelevantItems = unique(irrelevantItems).prefix(5)
        if !uniqueIrrelevantItems.isEmpty {
            parts.append("相关性过滤 \(irrelevantItems.count) 条：\n" + uniqueIrrelevantItems.map { "- \($0.clipped(to: 260))" }.joined(separator: "\n"))
        }
        let uniqueWarnings = unique(analysisWarnings).prefix(5)
        if !uniqueWarnings.isEmpty {
            parts.append("模型分析警告 \(analysisWarnings.count) 条：\n" + uniqueWarnings.map { "- \($0.clipped(to: 260))" }.joined(separator: "\n"))
        }
        return parts.joined(separator: "\n")
    }

    private static func describeImportDecodeError(_ error: Error) -> String {
        func path(_ codingPath: [CodingKey]) -> String {
            let value = codingPath.map(\.stringValue).joined(separator: ".")
            return value.isEmpty ? "JSON 根节点" : value
        }

        switch error {
        case let DecodingError.dataCorrupted(context):
            return "\(path(context.codingPath))：\(context.debugDescription)"
        case let DecodingError.typeMismatch(type, context):
            return "\(path(context.codingPath))：字段类型不匹配，期望 \(type)。\(context.debugDescription)"
        case let DecodingError.valueNotFound(type, context):
            return "\(path(context.codingPath))：缺少必填值，期望 \(type)。\(context.debugDescription)"
        case let DecodingError.keyNotFound(key, context):
            return "\(path(context.codingPath))：缺少字段 \(key.stringValue)。\(context.debugDescription)"
        default:
            return error.localizedDescription
        }
    }
}

enum ImportError: LocalizedError {
    case invalidEncoding
    case invalidJSON(String)
    case invalidSourceRecommendationJSON(String)

    var errorDescription: String? {
        switch self {
        case .invalidEncoding:
            return "JSON 文本编码无效"
        case .invalidJSON(let message):
            return "JSON 格式不符合 Tavily 批量导入结构：\(message)"
        case .invalidSourceRecommendationJSON(let message):
            return "JSON 格式不符合通用数据源推荐结构：\(message)"
        }
    }
}
