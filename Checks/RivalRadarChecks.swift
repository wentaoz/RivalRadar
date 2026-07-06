import Foundation

enum CheckFailure: Error, CustomStringConvertible {
    case failed(String)

    var description: String {
        switch self {
        case .failed(let message):
            return message
        }
    }
}

@main
struct RivalRadarChecks {
    static func main() async {
        do {
            try urlAndContentDedupePreventsDuplicateInsert()
            try tavilySourceConfigurationPersists()
            try tavilyJSONConfigAcceptsSnakeCase()
            try tavilyBulkConfigDecodesCompetitorProfiles()
            try tavilyBulkConfigDecodesListedCompetitors()
            try sourceRecommendationConfigDecodesAllSourceTypes()
            try sourceRecommendationMapperDisablesManualSetupSources()
            try sourceRecommendationConfigDecodesLegacyTavilyShape()
            try sourceRecommendationJSONRepairHandlesCommonModelOutput()
            try timeFilterPresetMatchesExpectedRanges()
            try aliyunBailianCompatibleEndpointUsesProvidedV1Path()
            try apiErrorsExposeDebuggableMessages()
            try titleSimilarityCatchesLikelyReposts()
            try reportGeneratorCreatesDailyAndCompetitorDocxFiles()
            try chromeSessionReaderFailsCleanlyWhenProfileHasNoCookiesDatabase()
            await analyzerFallsBackWithoutAPIKey()
            print("RivalRadar checks passed")
        } catch {
            fputs("RivalRadar checks failed: \(error)\n", stderr)
            exit(1)
        }
    }

    private static func urlAndContentDedupePreventsDuplicateInsert() throws {
        let db = try SQLiteDatabase(databaseURL: temporaryDatabaseURL())
        let competitor = Competitor(name: "Acme", keywords: ["pricing"])
        let source = IntelligenceSource(competitorID: competitor.id, name: "Acme Blog", url: "https://example.com/blog")
        db.upsertCompetitor(competitor)
        db.upsertSource(source)

        let raw = RawCollectedItem(
            title: "Acme launches new pricing",
            url: "https://example.com/post?utm_source=news",
            content: "Acme launched a new pricing plan.",
            publishedAt: nil,
            sourceName: "Example"
        )
        let fingerprints = DedupeService.fingerprints(for: raw, competitor: competitor)
        let item = IntelligenceItem(
            sourceID: source.id,
            competitorID: competitor.id,
            title: raw.title,
            url: raw.url,
            normalizedURL: fingerprints.normalizedURL,
            domain: fingerprints.domain,
            rawContent: raw.content,
            publishedAt: nil,
            category: .pricing,
            summary: "New pricing plan.",
            impact: "Review competitive pricing.",
            importance: 4,
            urlHash: fingerprints.urlHash,
            titleHash: fingerprints.titleHash,
            contentHash: fingerprints.contentHash
        )

        try expect(db.insertItemIfNew(item), "first item insert should succeed")
        try expect(!db.insertItemIfNew(item), "duplicate item insert should be rejected")
        try expect(db.loadItems().count == 1, "database should contain exactly one item")
    }

    private static func titleSimilarityCatchesLikelyReposts() throws {
        try expect(
            DedupeService.isSimilarTitle("Acme launches AI search for enterprise teams", "Acme launches AI search for enterprise team"),
            "similar repost titles should match"
        )
        try expect(
            !DedupeService.isSimilarTitle("Acme launches AI search", "BetaCorp opens new office in Tokyo"),
            "unrelated titles should not match"
        )
    }

    private static func tavilySourceConfigurationPersists() throws {
        let db = try SQLiteDatabase(databaseURL: temporaryDatabaseURL())
        let competitor = Competitor(name: "Acme", keywords: ["pricing"])
        db.upsertCompetitor(competitor)

        let source = IntelligenceSource(
            competitorID: competitor.id,
            name: "Acme Tavily",
            type: .tavilySearch,
            keywords: ["funding", "pricing"],
            frequency: .hourly,
            customFrequencyMinutes: 45,
            searchEndpoint: "https://api.tavily.com/search",
            searchAPIKey: "tvly-test",
            searchQueryTemplate: "\"{competitor}\" {keywords}",
            tavilyTopic: .news,
            tavilySearchDepth: .advanced,
            tavilyMaxResults: 7,
            tavilyTimeRange: .month,
            tavilyIncludeRawContent: true,
            tavilyIncludeDomains: ["reuters.com", "nu.com.mx"],
            tavilyCountry: "mexico",
            tavilyLanguageHints: ["es-MX", "en"],
            tavilyQueryGroup: "growth",
            tavilySourceProfile: "news"
        )
        db.upsertSource(source)

        guard let loaded = db.loadSources().first else {
            throw CheckFailure.failed("Tavily source should load from SQLite")
        }
        try expect(loaded.type == .tavilySearch, "Tavily source type should persist")
        try expect(loaded.frequency == .hourly, "source frequency should persist")
        try expect(loaded.customFrequencyMinutes == 45, "custom frequency minutes should persist")
        try expect(loaded.searchAPIKey == "tvly-test", "Tavily API key should persist")
        try expect(loaded.tavilySearchDepth == .advanced, "Tavily depth should persist")
        try expect(loaded.tavilyMaxResults == 7, "Tavily max results should persist")
        try expect(loaded.tavilyTimeRange == .month, "Tavily time range should persist")
        try expect(loaded.tavilyIncludeRawContent, "Tavily raw content flag should persist")
        try expect(loaded.tavilyIncludeDomains == ["reuters.com", "nu.com.mx"], "Tavily include domains should persist")
        try expect(loaded.tavilyCountry == "mexico", "Tavily country should persist")
        try expect(loaded.tavilyLanguageHints == ["es-MX", "en"], "Tavily languages should persist")
        try expect(loaded.tavilyQueryGroup == "growth", "Tavily query group should persist")
        try expect(loaded.tavilySourceProfile == "news", "Tavily source profile should persist")
    }

    private static func tavilyJSONConfigAcceptsSnakeCase() throws {
        let json = """
        {
          "apiKey": "tvly-test",
          "endpoint": "https://api.tavily.com/search",
          "queryTemplate": "\\"{competitor}\\" {keywords}",
          "topic": "news",
          "search_depth": "basic",
          "time_range": "week",
          "max_results": 8,
          "include_raw_content": "text"
        }
        """
        let config = try JSONDecoder().decode(TavilySourceJSONConfig.self, from: Data(json.utf8))
        try expect(config.apiKey == "tvly-test", "Tavily JSON apiKey should parse")
        try expect(config.searchDepth == "basic", "Tavily JSON search_depth should parse")
        try expect(config.timeRange == "week", "Tavily JSON time_range should parse")
        try expect(config.maxResults == 8, "Tavily JSON max_results should parse")
        try expect(config.includeRawContent == true, "Tavily JSON include_raw_content should parse")
    }

    private static func tavilyBulkConfigDecodesCompetitorProfiles() throws {
        let json = """
        {
          "tavily": {
            "frequency": "globalDefault",
            "custom_frequency_minutes": 90,
            "search_depth": "basic",
            "time_range": "week",
            "max_results": 5,
            "include_raw_content": true
          },
          "competitors": {
            "nubank": {
              "aliases": ["Nubank", "Nu México"],
              "markets": ["mexico", "brazil"],
              "focus_market": "mexico",
              "languages": ["es-MX", "en"],
              "query_groups": {
                "credit_card": ["tarjeta de crédito", "sin anualidad"]
              },
              "source_profiles": {
                "news": {
                  "include_domains": ["reuters.com", "elfinanciero.com.mx"],
                  "topic": "news"
                }
              }
            }
          }
        }
        """
        let config = try JSONDecoder().decode(TavilyBulkConfiguration.self, from: Data(json.utf8))
        try expect(config.tavily?.frequency == .globalDefault, "bulk config should allow global default frequency")
        try expect(config.tavily?.customFrequencyMinutes == 90, "bulk config custom frequency minutes should parse")
        guard let nubank = config.competitors["nubank"] else {
            throw CheckFailure.failed("bulk config should include nubank")
        }
        try expect(nubank.focusMarket == "mexico", "bulk config focus market should parse")
        try expect(nubank.languages == ["es-MX", "en"], "bulk config languages should parse")
        try expect(nubank.queryGroups["credit_card"]?.count == 2, "bulk config query groups should parse")
        try expect(nubank.sourceProfiles["news"]?.includeDomains == ["reuters.com", "elfinanciero.com.mx"], "bulk config source domains should parse")
    }

    private static func tavilyBulkConfigDecodesListedCompetitors() throws {
        let json = """
        {
          "tavily": {
            "frequency": "globalDefault",
            "search_depth": "basic",
            "time_range": "week",
            "max_results": 3,
            "include_raw_content": true
          },
          "competitors": [
            {
              "key": "nubank_mexico",
              "name": "Nu México",
              "markets": ["mexico"],
              "focus_market": "mexico",
              "languages": ["es-MX", "en"],
              "query_groups": {
                "credit_card": ["tarjeta de crédito", "sin anualidad"]
              },
              "source_profiles": {
                "news": {
                  "include_domains": ["reuters.com"],
                  "topic": "news"
                }
              }
            }
          ]
        }
        """
        let config = try JSONDecoder().decode(TavilyBulkConfiguration.self, from: Data(json.utf8))
        guard let nubank = config.competitors["nubank_mexico"] else {
            throw CheckFailure.failed("bulk config should decode listed competitor using key")
        }
        try expect(nubank.aliases == ["Nu México"], "listed competitor should use name as fallback alias")
        try expect(nubank.focusMarket == "mexico", "listed competitor focus market should parse")
        try expect(nubank.sourceProfiles["news"]?.topic == .news, "listed competitor source profile should parse")
    }

    private static func sourceRecommendationConfigDecodesAllSourceTypes() throws {
        let config = try JSONDecoder().decode(SourceRecommendationConfiguration.self, from: Data(sourceRecommendationSampleJSON.utf8))
        let summary = SourceRecommendationImportMapper.summary(for: config)

        try expect(summary.competitorCount == 1, "source recommendation should include one competitor")
        try expect(summary.sourceCount == 5, "source recommendation should decode all five source rows")
        try expect(summary.disabledSourceCount == 2, "login and search API rows should be marked as manual setup")
        try expect(summary.typeCounts.contains { $0.0 == .tavilySearch && $0.1 == 1 }, "summary should count Tavily source")
        try expect(summary.typeCounts.contains { $0.0 == .webPage && $0.1 == 2 }, "summary should count public and login web sources")
        try expect(summary.typeCounts.contains { $0.0 == .rss && $0.1 == 1 }, "summary should count RSS source")
        try expect(summary.typeCounts.contains { $0.0 == .searchAPI && $0.1 == 1 }, "summary should count search API source")
    }

    private static func sourceRecommendationMapperDisablesManualSetupSources() throws {
        let config = try JSONDecoder().decode(SourceRecommendationConfiguration.self, from: Data(sourceRecommendationSampleJSON.utf8))
        guard let competitorConfig = config.competitors["maya_ph"] else {
            throw CheckFailure.failed("sample recommendation should include maya_ph")
        }

        let competitor = SourceRecommendationImportMapper.competitor(
            key: "maya_ph",
            config: competitorConfig,
            existing: nil
        )
        let sources = competitorConfig.sources.enumerated().compactMap { index, sourceConfig in
            SourceRecommendationImportMapper.source(
                from: sourceConfig,
                competitor: competitor,
                competitorConfig: competitorConfig,
                existing: nil,
                index: index
            )
        }

        try expect(sources.count == 5, "mapper should create all source records when URL/endpoint exists")
        try expect(sources.first(where: { $0.type == .tavilySearch })?.searchAPIKey == "", "Tavily source should rely on global API key")
        try expect(sources.first(where: { $0.type == .searchAPI })?.isEnabled == false, "generic Search API should import disabled")
        try expect(sources.first(where: { $0.requiresLogin })?.isEnabled == false, "login source should import disabled")
        try expect(sources.first(where: { $0.requiresLogin })?.chromeProfilePath == "", "login source should not store a Chrome profile path from JSON")
    }

    private static func sourceRecommendationConfigDecodesLegacyTavilyShape() throws {
        let json = """
        {
          "competitors": {
            "nubank": {
              "aliases": ["Nubank"],
              "markets": ["mexico"],
              "focus_market": "mexico",
              "languages": ["es-MX"],
              "query_groups": {
                "regulation": ["CNBV", "licencia bancaria"]
              },
              "source_profiles": {
                "news": {
                  "include_domains": ["reuters.com"],
                  "topic": "news"
                }
              }
            }
          }
        }
        """
        let config = try JSONDecoder().decode(SourceRecommendationConfiguration.self, from: Data(json.utf8))
        let summary = SourceRecommendationImportMapper.summary(for: config)
        try expect(summary.sourceCount == 1, "legacy Tavily shape should be converted into a Tavily source")
        try expect(config.competitors["nubank"]?.sources.first?.type == .tavilySearch, "legacy source should map to Tavily")
        try expect(config.competitors["nubank"]?.sources.first?.includeDomains == ["reuters.com"], "legacy include domains should be preserved")
    }

    private static func sourceRecommendationJSONRepairHandlesCommonModelOutput() throws {
        let modelOutput = """
        下面是推荐 JSON：
        ```json
        {
          recommendation_summary: "Mexico small-loan monitor",
          "competitors": {
            "kueski": {
              "name": "Kueski",
              "aliases": ["Kueski",],
              "markets": ["mexico"],
              "focus_market": "mexico",
              "languages": ["es-MX"],
              "keywords": ["prestamo personal"],
              "sources": [
                {
                  "name": "Kueski Tavily",
                  "type": "tavilySearch",
                  "keywords": ["prestamo", "quejas"],
                  // 模型偶尔会输出解释性注释
                  "include_domains": ["kueski.com",],
                },
              ],
            },
          },
        }
        ```
        """

        let decoded = SourceRecommendationJSONRepair.candidates(from: modelOutput).lazy.compactMap { candidate in
            try? JSONDecoder().decode(SourceRecommendationConfiguration.self, from: Data(candidate.utf8))
        }.first

        guard let decoded else {
            throw CheckFailure.failed("source recommendation JSON repair should produce decodable JSON")
        }
        try expect(decoded.competitors["kueski"]?.sources.first?.type == .tavilySearch, "repaired JSON should preserve Tavily source")
        try expect(decoded.recommendationSummary == "Mexico small-loan monitor", "repaired JSON should preserve summary")
    }

    private static func timeFilterPresetMatchesExpectedRanges() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let yesterday = calendar.date(byAdding: .day, value: -1, to: now)!
        let fortyDaysAgo = calendar.date(byAdding: .day, value: -40, to: now)!
        let customStart = Date(timeIntervalSince1970: 1_699_920_000)
        let customEnd = Date(timeIntervalSince1970: 1_699_920_000)
        let customSameDayNoon = calendar.date(bySettingHour: 12, minute: 0, second: 0, of: customStart)!

        try expect(TimeFilterPreset.all.contains(fortyDaysAgo, startDate: customStart, endDate: customEnd, calendar: calendar, now: now), "all filter should include any date")
        try expect(TimeFilterPreset.last7Days.contains(yesterday, startDate: customStart, endDate: customEnd, calendar: calendar, now: now), "last 7 days should include yesterday")
        try expect(!TimeFilterPreset.last30Days.contains(fortyDaysAgo, startDate: customStart, endDate: customEnd, calendar: calendar, now: now), "last 30 days should exclude older dates")
        try expect(TimeFilterPreset.custom.contains(customSameDayNoon, startDate: customEnd, endDate: customStart, calendar: calendar, now: now), "custom filter should include the whole selected day even when dates are reversed")
    }

    private static func aliyunBailianCompatibleEndpointUsesProvidedV1Path() throws {
        let url = try OpenAIChatClient().chatCompletionsURL(baseURL: "https://dashscope.aliyuncs.com/compatible-mode/v1")
        try expect(
            url.absoluteString == "https://dashscope.aliyuncs.com/compatible-mode/v1/chat/completions",
            "Aliyun Bailian compatible endpoint should preserve compatible-mode/v1"
        )
    }

    private static func apiErrorsExposeDebuggableMessages() throws {
        let searchError = CollectorError.apiHTTPError(
            service: "Tavily Search",
            statusCode: 401,
            body: #"{"error":{"message":"Invalid API key"}}"#
        )
        try expect(
            searchError.localizedDescription.contains("Tavily Search") &&
            searchError.localizedDescription.contains("HTTP 401") &&
            searchError.localizedDescription.contains("Invalid API key"),
            "search API errors should include service, status, and response body"
        )

        let missingKey = CollectorError.missingSearchAPIKey("Tavily Search")
        try expect(
            missingKey.localizedDescription.contains("接口密钥未配置"),
            "missing search API key should be explicit"
        )
    }

    private static func reportGeneratorCreatesDailyAndCompetitorDocxFiles() throws {
        let competitor = Competitor(name: "Acme")
        let item = IntelligenceItem(
            sourceID: UUID(),
            competitorID: competitor.id,
            title: "Acme releases new feature",
            url: "https://example.com/feature",
            normalizedURL: "https://example.com/feature",
            domain: "example.com",
            rawContent: "Acme released a new feature.",
            publishedAt: nil,
            category: .product,
            summary: "Acme released a new feature.",
            impact: "Track adoption and messaging.",
            importance: 3,
            urlHash: "url",
            titleHash: "title",
            contentHash: "content"
        )

        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("RivalRadarChecks-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: folder) }

        let urls = try ReportGenerator().generateReports(
            items: [item],
            competitors: [competitor],
            date: Date(timeIntervalSince1970: 1_700_000_000),
            reportsFolder: folder.path
        )

        try expect(urls.count == 2, "report generator should create daily and competitor docx files")
        for url in urls {
            try expect(FileManager.default.fileExists(atPath: url.path), "report file should exist: \(url.path)")
            let data = try Data(contentsOf: url)
            try expect(Array(data.prefix(2)) == [0x50, 0x4B], "docx should be a zip package")
            let documentXML = try unzipText(url: url, entry: "word/document.xml")
            let stylesXML = try unzipText(url: url, entry: "word/styles.xml")
            try expect(documentXML.contains("<w:tbl>"), "report should include readable tables")
            try expect(documentXML.contains("竞品概览"), "report should include competitor summary section")
            try expect(stylesXML.contains("Heading 1"), "report should include Word styles")
        }
    }

    private static func chromeSessionReaderFailsCleanlyWhenProfileHasNoCookiesDatabase() throws {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("RivalRadarChrome-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }

        do {
            _ = try ChromeSessionReader().cookieHeader(for: URL(string: "https://example.com")!, profilePath: folder.path)
            throw CheckFailure.failed("ChromeSessionReader should throw for a profile without Cookies database")
        } catch ChromeSessionError.cookiesDatabaseMissing {
            return
        } catch {
            throw error
        }
    }

    private static func analyzerFallsBackWithoutAPIKey() async {
        let raw = RawCollectedItem(
            title: "Acme update",
            url: "https://example.com",
            content: "Acme shipped a product update.",
            publishedAt: nil,
            sourceName: "Example"
        )
        let result = await IntelligenceAnalyzer().analyze(
            raw: raw,
            competitor: Competitor(name: "Acme"),
            configuration: OpenAIConfiguration(apiKey: "", baseURL: "https://api.deepseek.com", model: "deepseek-v4-flash")
        )

        if result.category != .other || !result.summary.contains("Acme shipped") || result.importance != 2 || !result.isRelevant {
            fputs("Analyzer fallback check failed\n", stderr)
            exit(1)
        }
    }

    private static func expect(_ condition: Bool, _ message: String) throws {
        guard condition else { throw CheckFailure.failed(message) }
    }

    private static func temporaryDatabaseURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("RivalRadarChecks-\(UUID().uuidString)", isDirectory: true)
            .appendingPathComponent("test.sqlite")
    }

    private static func unzipText(url: URL, entry: String) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        process.arguments = ["-p", url.path, entry]
        let pipe = Pipe()
        process.standardOutput = pipe
        try process.run()
        process.waitUntilExit()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        guard process.terminationStatus == 0,
              let value = String(data: data, encoding: .utf8) else {
            throw CheckFailure.failed("could not unzip \(entry) from \(url.path)")
        }
        return value
    }

    private static let sourceRecommendationSampleJSON = """
    {
      "recommendation_summary": "Philippines digital lending competitor monitor.",
      "competitors": {
        "maya_ph": {
          "name": "Maya Philippines",
          "aliases": ["Maya", "Maya Credit"],
          "markets": ["philippines"],
          "focus_market": "philippines",
          "languages": ["en", "fil"],
          "keywords": ["personal loan", "cash loan", "loan app"],
          "sources": [
            {
              "name": "Maya Tavily News",
              "type": "tavilySearch",
              "keywords": ["digital lending", "credit line"],
              "include_domains": ["maya.ph", "bsp.gov.ph"],
              "query_group": "product_regulation",
              "source_profile": "official_news",
              "topic": "news"
            },
            {
              "name": "Maya Official",
              "type": "webPage",
              "url": "https://www.maya.ph/",
              "keywords": ["Maya Credit"],
              "is_enabled": true
            },
            {
              "name": "Maya Blog RSS",
              "type": "rss",
              "url": "https://www.maya.ph/feed.xml",
              "keywords": ["announcement"]
            },
            {
              "name": "Maya Custom Search API",
              "type": "searchAPI",
              "search_endpoint": "https://search.example.com/api",
              "search_query_template": "{competitor} {keywords}",
              "search_title_path": "title",
              "search_url_path": "url",
              "is_enabled": true
            },
            {
              "name": "Maya Logged Portal",
              "type": "webPage",
              "url": "https://app.maya.ph/private",
              "requires_login": true,
              "is_enabled": true
            }
          ]
        }
      }
    }
    """
}
