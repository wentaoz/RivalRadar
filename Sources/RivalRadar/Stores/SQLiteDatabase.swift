import Foundation
import SQLite3

final class SQLiteDatabase {
    private let db: OpaquePointer?
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(databaseURL: URL? = nil, fileManager: FileManager = .default) throws {
        let dbURL: URL
        if let databaseURL {
            dbURL = databaseURL
            try fileManager.createDirectory(at: databaseURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        } else {
            let supportURL = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)
                .first?
                .appendingPathComponent("RivalRadar", isDirectory: true)
            ?? fileManager.homeDirectoryForCurrentUser
                .appendingPathComponent("Library/Application Support/RivalRadar", isDirectory: true)
            try fileManager.createDirectory(at: supportURL, withIntermediateDirectories: true)
            dbURL = supportURL.appendingPathComponent("rivalradar.sqlite")
        }

        var pointer: OpaquePointer?
        guard sqlite3_open(dbURL.path, &pointer) == SQLITE_OK else {
            throw SQLiteStoreError.openFailed
        }

        db = pointer
        encoder.dateEncodingStrategy = .iso8601
        decoder.dateDecodingStrategy = .iso8601
        try createSchema()
    }

    deinit {
        sqlite3_close(db)
    }

    func loadCompetitors() -> [Competitor] {
        query(
            """
            SELECT id, name, aliases_json, keywords_json, notes, is_enabled, created_at
            FROM competitors
            ORDER BY created_at DESC
            """
        ) { statement in
            Competitor(
                id: UUID(uuidString: columnText(statement, 0) ?? "") ?? UUID(),
                name: columnText(statement, 1) ?? "",
                aliases: decodeStringArray(columnText(statement, 2), decoder: decoder),
                keywords: decodeStringArray(columnText(statement, 3), decoder: decoder),
                notes: columnText(statement, 4) ?? "",
                isEnabled: sqlite3_column_int(statement, 5) == 1,
                createdAt: Date(timeIntervalSince1970: sqlite3_column_double(statement, 6))
            )
        }
    }

    func upsertCompetitor(_ competitor: Competitor) {
        execute(
            """
            INSERT OR REPLACE INTO competitors (
                id, name, aliases_json, keywords_json, notes, is_enabled, created_at
            ) VALUES (?, ?, ?, ?, ?, ?, ?)
            """,
            [
                .text(competitor.id.uuidString),
                .text(competitor.name),
                .text(encodeStringArray(competitor.aliases)),
                .text(encodeStringArray(competitor.keywords)),
                .text(competitor.notes),
                .int(competitor.isEnabled ? 1 : 0),
                .double(competitor.createdAt.timeIntervalSince1970)
            ]
        )
    }

    func deleteCompetitor(id: UUID) {
        execute("DELETE FROM intelligence_items WHERE competitor_id = ?", [.text(id.uuidString)])
        execute("DELETE FROM sources WHERE competitor_id = ?", [.text(id.uuidString)])
        execute("DELETE FROM competitors WHERE id = ?", [.text(id.uuidString)])
    }

    func loadSources() -> [IntelligenceSource] {
        query(
            """
            SELECT id, competitor_id, name, type, url, keywords_json, frequency,
                   custom_frequency_minutes,
                   requires_login, chrome_profile_path, search_endpoint, search_api_key,
                   search_query_template, search_title_path, search_url_path,
                   tavily_topic, tavily_search_depth, tavily_max_results,
                   tavily_time_range, tavily_include_raw_content,
                   tavily_include_domains_json, tavily_exclude_domains_json,
                   tavily_country, tavily_language_hints_json,
                   tavily_query_group, tavily_source_profile,
                   is_enabled, last_run_at
            FROM sources
            ORDER BY name ASC
            """
        ) { statement in
            let lastRunAt = sqlite3_column_type(statement, 27) == SQLITE_NULL
                ? nil
                : Date(timeIntervalSince1970: sqlite3_column_double(statement, 27))

            return IntelligenceSource(
                id: UUID(uuidString: columnText(statement, 0) ?? "") ?? UUID(),
                competitorID: UUID(uuidString: columnText(statement, 1) ?? "") ?? UUID(),
                name: columnText(statement, 2) ?? "",
                type: SourceType(rawValue: columnText(statement, 3) ?? "") ?? .webPage,
                url: columnText(statement, 4) ?? "",
                keywords: decodeStringArray(columnText(statement, 5), decoder: decoder),
                frequency: SourceFrequency(rawValue: columnText(statement, 6) ?? "") ?? .hourly,
                customFrequencyMinutes: max(1, Int(sqlite3_column_int(statement, 7))),
                requiresLogin: sqlite3_column_int(statement, 8) == 1,
                chromeProfilePath: columnText(statement, 9) ?? "",
                searchEndpoint: columnText(statement, 10) ?? "",
                searchAPIKey: columnText(statement, 11) ?? "",
                searchQueryTemplate: columnText(statement, 12) ?? "{competitor} {keywords}",
                searchTitlePath: columnText(statement, 13) ?? "title",
                searchURLPath: columnText(statement, 14) ?? "url",
                tavilyTopic: TavilyTopic(rawValue: columnText(statement, 15) ?? "") ?? .news,
                tavilySearchDepth: TavilySearchDepth(rawValue: columnText(statement, 16) ?? "") ?? .basic,
                tavilyMaxResults: Int(sqlite3_column_int(statement, 17)),
                tavilyTimeRange: TavilyTimeRange(rawValue: columnText(statement, 18) ?? "") ?? .week,
                tavilyIncludeRawContent: sqlite3_column_int(statement, 19) == 1,
                tavilyIncludeDomains: decodeStringArray(columnText(statement, 20), decoder: decoder),
                tavilyExcludeDomains: decodeStringArray(columnText(statement, 21), decoder: decoder),
                tavilyCountry: columnText(statement, 22) ?? "",
                tavilyLanguageHints: decodeStringArray(columnText(statement, 23), decoder: decoder),
                tavilyQueryGroup: columnText(statement, 24) ?? "",
                tavilySourceProfile: columnText(statement, 25) ?? "",
                isEnabled: sqlite3_column_int(statement, 26) == 1,
                lastRunAt: lastRunAt
            )
        }
    }

    func upsertSource(_ source: IntelligenceSource) {
        execute(
            """
            INSERT OR REPLACE INTO sources (
                id, competitor_id, name, type, url, keywords_json, frequency,
                custom_frequency_minutes,
                requires_login, chrome_profile_path, search_endpoint, search_api_key,
                search_query_template, search_title_path, search_url_path,
                tavily_topic, tavily_search_depth, tavily_max_results,
                tavily_time_range, tavily_include_raw_content,
                tavily_include_domains_json, tavily_exclude_domains_json,
                tavily_country, tavily_language_hints_json,
                tavily_query_group, tavily_source_profile,
                is_enabled, last_run_at
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            """,
            [
                .text(source.id.uuidString),
                .text(source.competitorID.uuidString),
                .text(source.name),
                .text(source.type.rawValue),
                .text(source.url),
                .text(encodeStringArray(source.keywords)),
                .text(source.frequency.rawValue),
                .int(source.customFrequencyMinutes),
                .int(source.requiresLogin ? 1 : 0),
                .text(source.chromeProfilePath),
                .text(source.searchEndpoint),
                .text(source.searchAPIKey),
                .text(source.searchQueryTemplate),
                .text(source.searchTitlePath),
                .text(source.searchURLPath),
                .text(source.tavilyTopic.rawValue),
                .text(source.tavilySearchDepth.rawValue),
                .int(source.tavilyMaxResults),
                .text(source.tavilyTimeRange.rawValue),
                .int(source.tavilyIncludeRawContent ? 1 : 0),
                .text(encodeStringArray(source.tavilyIncludeDomains)),
                .text(encodeStringArray(source.tavilyExcludeDomains)),
                .text(source.tavilyCountry),
                .text(encodeStringArray(source.tavilyLanguageHints)),
                .text(source.tavilyQueryGroup),
                .text(source.tavilySourceProfile),
                .int(source.isEnabled ? 1 : 0),
                .double(source.lastRunAt?.timeIntervalSince1970)
            ]
        )
    }

    func deleteSource(id: UUID) {
        execute("DELETE FROM sources WHERE id = ?", [.text(id.uuidString)])
    }

    func updateSourceLastRun(id: UUID, date: Date) {
        execute("UPDATE sources SET last_run_at = ? WHERE id = ?", [
            .double(date.timeIntervalSince1970),
            .text(id.uuidString)
        ])
    }

    func loadItems(limit: Int = 300) -> [IntelligenceItem] {
        query(
            """
            SELECT id, source_id, competitor_id, title, url, normalized_url, domain,
                   raw_content, published_at, discovered_at, category, summary, impact,
                   importance, url_hash, title_hash, content_hash, is_notified, is_reported
            FROM intelligence_items
            ORDER BY discovered_at DESC
            LIMIT ?
            """,
            [.int(limit)]
        ) { statement in
            decodeItem(statement: statement)
        }
    }

    func loadItems(on day: Date, calendar: Calendar = .current) -> [IntelligenceItem] {
        let start = calendar.startOfDay(for: day)
        let end = calendar.date(byAdding: .day, value: 1, to: start) ?? day
        return query(
            """
            SELECT id, source_id, competitor_id, title, url, normalized_url, domain,
                   raw_content, published_at, discovered_at, category, summary, impact,
                   importance, url_hash, title_hash, content_hash, is_notified, is_reported
            FROM intelligence_items
            WHERE discovered_at >= ? AND discovered_at < ?
            ORDER BY discovered_at DESC
            """,
            [.double(start.timeIntervalSince1970), .double(end.timeIntervalSince1970)]
        ) { statement in
            decodeItem(statement: statement)
        }
    }

    func isDuplicate(urlHash: String, titleHash: String, contentHash: String) -> Bool {
        let matches = query(
            """
            SELECT id
            FROM intelligence_items
            WHERE url_hash = ? OR title_hash = ? OR content_hash = ?
            LIMIT 1
            """,
            [.text(urlHash), .text(titleHash), .text(contentHash)]
        ) { statement in
            columnText(statement, 0)
        }
        return !matches.isEmpty
    }

    @discardableResult
    func insertItemIfNew(_ item: IntelligenceItem) -> Bool {
        guard !isDuplicate(urlHash: item.urlHash, titleHash: item.titleHash, contentHash: item.contentHash) else {
            return false
        }

        execute(
            """
            INSERT INTO intelligence_items (
                id, source_id, competitor_id, title, url, normalized_url, domain,
                raw_content, published_at, discovered_at, category, summary, impact,
                importance, url_hash, title_hash, content_hash, is_notified, is_reported
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            """,
            [
                .text(item.id.uuidString),
                .text(item.sourceID.uuidString),
                .text(item.competitorID.uuidString),
                .text(item.title),
                .text(item.url),
                .text(item.normalizedURL),
                .text(item.domain),
                .text(item.rawContent),
                .double(item.publishedAt?.timeIntervalSince1970),
                .double(item.discoveredAt.timeIntervalSince1970),
                .text(item.category.rawValue),
                .text(item.summary),
                .text(item.impact),
                .int(item.importance),
                .text(item.urlHash),
                .text(item.titleHash),
                .text(item.contentHash),
                .int(item.isNotified ? 1 : 0),
                .int(item.isReported ? 1 : 0)
            ]
        )
        return true
    }

    func markNotified(ids: [UUID]) {
        guard !ids.isEmpty else { return }
        ids.forEach { id in
            execute("UPDATE intelligence_items SET is_notified = 1 WHERE id = ?", [.text(id.uuidString)])
        }
    }

    func markReported(ids: [UUID]) {
        guard !ids.isEmpty else { return }
        ids.forEach { id in
            execute("UPDATE intelligence_items SET is_reported = 1 WHERE id = ?", [.text(id.uuidString)])
        }
    }

    func loadRunLogs(limit: Int = 200) -> [RunLog] {
        query(
            """
            SELECT id, source_id, source_name, started_at, finished_at, status, message, new_count
            FROM run_logs
            ORDER BY started_at DESC
            LIMIT ?
            """,
            [.int(limit)]
        ) { statement in
            let finishedAt = sqlite3_column_type(statement, 4) == SQLITE_NULL
                ? nil
                : Date(timeIntervalSince1970: sqlite3_column_double(statement, 4))
            return RunLog(
                id: UUID(uuidString: columnText(statement, 0) ?? "") ?? UUID(),
                sourceID: columnText(statement, 1).flatMap(UUID.init(uuidString:)),
                sourceName: columnText(statement, 2) ?? "",
                startedAt: Date(timeIntervalSince1970: sqlite3_column_double(statement, 3)),
                finishedAt: finishedAt,
                status: RunStatus(rawValue: columnText(statement, 5) ?? "") ?? .failed,
                message: columnText(statement, 6) ?? "",
                newCount: Int(sqlite3_column_int(statement, 7))
            )
        }
    }

    func upsertRunLog(_ log: RunLog) {
        execute(
            """
            INSERT OR REPLACE INTO run_logs (
                id, source_id, source_name, started_at, finished_at, status, message, new_count
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?)
            """,
            [
                .text(log.id.uuidString),
                .text(log.sourceID?.uuidString),
                .text(log.sourceName),
                .double(log.startedAt.timeIntervalSince1970),
                .double(log.finishedAt?.timeIntervalSince1970),
                .text(log.status.rawValue),
                .text(log.message),
                .int(log.newCount)
            ]
        )
    }

    private func createSchema() throws {
        try executeThrowing("PRAGMA journal_mode = WAL")
        try executeThrowing("PRAGMA foreign_keys = ON")
        try executeThrowing(
            """
            CREATE TABLE IF NOT EXISTS competitors (
                id TEXT PRIMARY KEY,
                name TEXT NOT NULL,
                aliases_json TEXT NOT NULL,
                keywords_json TEXT NOT NULL,
                notes TEXT NOT NULL,
                is_enabled INTEGER NOT NULL,
                created_at REAL NOT NULL
            )
            """
        )
        try executeThrowing(
            """
            CREATE TABLE IF NOT EXISTS sources (
                id TEXT PRIMARY KEY,
                competitor_id TEXT NOT NULL,
                name TEXT NOT NULL,
                type TEXT NOT NULL,
                url TEXT NOT NULL,
                keywords_json TEXT NOT NULL,
                frequency TEXT NOT NULL,
                custom_frequency_minutes INTEGER NOT NULL DEFAULT 60,
                requires_login INTEGER NOT NULL,
                chrome_profile_path TEXT NOT NULL,
                search_endpoint TEXT NOT NULL,
                search_api_key TEXT NOT NULL,
                search_query_template TEXT NOT NULL,
                search_title_path TEXT NOT NULL,
                search_url_path TEXT NOT NULL,
                tavily_topic TEXT NOT NULL DEFAULT 'news',
                tavily_search_depth TEXT NOT NULL DEFAULT 'basic',
                tavily_max_results INTEGER NOT NULL DEFAULT 5,
                tavily_time_range TEXT NOT NULL DEFAULT 'week',
                tavily_include_raw_content INTEGER NOT NULL DEFAULT 1,
                tavily_include_domains_json TEXT NOT NULL DEFAULT '[]',
                tavily_exclude_domains_json TEXT NOT NULL DEFAULT '[]',
                tavily_country TEXT NOT NULL DEFAULT '',
                tavily_language_hints_json TEXT NOT NULL DEFAULT '[]',
                tavily_query_group TEXT NOT NULL DEFAULT '',
                tavily_source_profile TEXT NOT NULL DEFAULT '',
                is_enabled INTEGER NOT NULL,
                last_run_at REAL,
                FOREIGN KEY (competitor_id) REFERENCES competitors(id) ON DELETE CASCADE
            )
            """
        )
        try addColumnIfMissing(table: "sources", name: "custom_frequency_minutes", definition: "INTEGER NOT NULL DEFAULT 60")
        try addColumnIfMissing(table: "sources", name: "tavily_topic", definition: "TEXT NOT NULL DEFAULT 'news'")
        try addColumnIfMissing(table: "sources", name: "tavily_search_depth", definition: "TEXT NOT NULL DEFAULT 'basic'")
        try addColumnIfMissing(table: "sources", name: "tavily_max_results", definition: "INTEGER NOT NULL DEFAULT 5")
        try addColumnIfMissing(table: "sources", name: "tavily_time_range", definition: "TEXT NOT NULL DEFAULT 'week'")
        try addColumnIfMissing(table: "sources", name: "tavily_include_raw_content", definition: "INTEGER NOT NULL DEFAULT 1")
        try addColumnIfMissing(table: "sources", name: "tavily_include_domains_json", definition: "TEXT NOT NULL DEFAULT '[]'")
        try addColumnIfMissing(table: "sources", name: "tavily_exclude_domains_json", definition: "TEXT NOT NULL DEFAULT '[]'")
        try addColumnIfMissing(table: "sources", name: "tavily_country", definition: "TEXT NOT NULL DEFAULT ''")
        try addColumnIfMissing(table: "sources", name: "tavily_language_hints_json", definition: "TEXT NOT NULL DEFAULT '[]'")
        try addColumnIfMissing(table: "sources", name: "tavily_query_group", definition: "TEXT NOT NULL DEFAULT ''")
        try addColumnIfMissing(table: "sources", name: "tavily_source_profile", definition: "TEXT NOT NULL DEFAULT ''")
        try executeThrowing(
            """
            CREATE TABLE IF NOT EXISTS intelligence_items (
                id TEXT PRIMARY KEY,
                source_id TEXT NOT NULL,
                competitor_id TEXT NOT NULL,
                title TEXT NOT NULL,
                url TEXT NOT NULL,
                normalized_url TEXT NOT NULL,
                domain TEXT NOT NULL,
                raw_content TEXT NOT NULL,
                published_at REAL,
                discovered_at REAL NOT NULL,
                category TEXT NOT NULL,
                summary TEXT NOT NULL,
                impact TEXT NOT NULL,
                importance INTEGER NOT NULL,
                url_hash TEXT NOT NULL,
                title_hash TEXT NOT NULL,
                content_hash TEXT NOT NULL,
                is_notified INTEGER NOT NULL,
                is_reported INTEGER NOT NULL,
                FOREIGN KEY (source_id) REFERENCES sources(id) ON DELETE CASCADE,
                FOREIGN KEY (competitor_id) REFERENCES competitors(id) ON DELETE CASCADE
            )
            """
        )
        try executeThrowing("CREATE INDEX IF NOT EXISTS idx_sources_competitor ON sources(competitor_id)")
        try executeThrowing("CREATE INDEX IF NOT EXISTS idx_items_discovered ON intelligence_items(discovered_at)")
        try executeThrowing("CREATE INDEX IF NOT EXISTS idx_items_competitor ON intelligence_items(competitor_id)")
        try executeThrowing("CREATE UNIQUE INDEX IF NOT EXISTS idx_items_url_hash ON intelligence_items(url_hash)")
        try executeThrowing("CREATE INDEX IF NOT EXISTS idx_items_title_hash ON intelligence_items(title_hash)")
        try executeThrowing("CREATE INDEX IF NOT EXISTS idx_items_content_hash ON intelligence_items(content_hash)")
        try executeThrowing(
            """
            CREATE TABLE IF NOT EXISTS run_logs (
                id TEXT PRIMARY KEY,
                source_id TEXT,
                source_name TEXT NOT NULL,
                started_at REAL NOT NULL,
                finished_at REAL,
                status TEXT NOT NULL,
                message TEXT NOT NULL,
                new_count INTEGER NOT NULL
            )
            """
        )
        try executeThrowing("CREATE INDEX IF NOT EXISTS idx_run_logs_started ON run_logs(started_at)")
    }

    private func addColumnIfMissing(table: String, name: String, definition: String) throws {
        let columns = query("PRAGMA table_info(\(table))") { statement in
            columnText(statement, 1) ?? ""
        }
        guard !columns.contains(name) else { return }
        try executeThrowing("ALTER TABLE \(table) ADD COLUMN \(name) \(definition)")
    }

    private func decodeItem(statement: OpaquePointer?) -> IntelligenceItem {
        let publishedAt = sqlite3_column_type(statement, 8) == SQLITE_NULL
            ? nil
            : Date(timeIntervalSince1970: sqlite3_column_double(statement, 8))
        return IntelligenceItem(
            id: UUID(uuidString: columnText(statement, 0) ?? "") ?? UUID(),
            sourceID: UUID(uuidString: columnText(statement, 1) ?? "") ?? UUID(),
            competitorID: UUID(uuidString: columnText(statement, 2) ?? "") ?? UUID(),
            title: columnText(statement, 3) ?? "",
            url: columnText(statement, 4) ?? "",
            normalizedURL: columnText(statement, 5) ?? "",
            domain: columnText(statement, 6) ?? "",
            rawContent: columnText(statement, 7) ?? "",
            publishedAt: publishedAt,
            discoveredAt: Date(timeIntervalSince1970: sqlite3_column_double(statement, 9)),
            category: IntelligenceCategory(rawValue: columnText(statement, 10) ?? "") ?? .other,
            summary: columnText(statement, 11) ?? "",
            impact: columnText(statement, 12) ?? "",
            importance: Int(sqlite3_column_int(statement, 13)),
            urlHash: columnText(statement, 14) ?? "",
            titleHash: columnText(statement, 15) ?? "",
            contentHash: columnText(statement, 16) ?? "",
            isNotified: sqlite3_column_int(statement, 17) == 1,
            isReported: sqlite3_column_int(statement, 18) == 1
        )
    }

    private func encodeStringArray(_ array: [String]) -> String {
        guard let data = try? encoder.encode(array),
              let value = String(data: data, encoding: .utf8) else {
            return "[]"
        }
        return value
    }

    private func execute(_ sql: String, _ values: [SQLiteValue] = []) {
        try? executeThrowing(sql, values)
    }

    private func executeThrowing(_ sql: String, _ values: [SQLiteValue] = []) throws {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            throw SQLiteStoreError.prepareFailed(message)
        }
        defer { sqlite3_finalize(statement) }

        bind(values, to: statement)

        let result = sqlite3_step(statement)
        guard result == SQLITE_DONE || result == SQLITE_ROW else {
            throw SQLiteStoreError.stepFailed(message)
        }
    }

    private func query<T>(_ sql: String, _ values: [SQLiteValue] = [], map: (OpaquePointer?) -> T) -> [T] {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            return []
        }
        defer { sqlite3_finalize(statement) }

        bind(values, to: statement)

        var result: [T] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            result.append(map(statement))
        }
        return result
    }

    private func bind(_ values: [SQLiteValue], to statement: OpaquePointer?) {
        for (index, value) in values.enumerated() {
            let position = Int32(index + 1)
            switch value {
            case .text(let string):
                guard let string else {
                    sqlite3_bind_null(statement, position)
                    continue
                }
                sqlite3_bind_text(statement, position, string, -1, SQLiteDatabase.transient)
            case .double(let double):
                guard let double else {
                    sqlite3_bind_null(statement, position)
                    continue
                }
                sqlite3_bind_double(statement, position, double)
            case .int(let int):
                sqlite3_bind_int(statement, position, Int32(int))
            }
        }
    }

    private var message: String {
        guard let message = sqlite3_errmsg(db) else { return "Unknown SQLite error" }
        return String(cString: message)
    }

    private static let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
}

enum SQLiteValue {
    case text(String?)
    case double(Double?)
    case int(Int)
}

enum SQLiteStoreError: LocalizedError {
    case openFailed
    case prepareFailed(String)
    case stepFailed(String)

    var errorDescription: String? {
        switch self {
        case .openFailed:
            return "无法打开 SQLite 数据库"
        case .prepareFailed(let message):
            return "SQLite prepare failed: \(message)"
        case .stepFailed(let message):
            return "SQLite step failed: \(message)"
        }
    }
}

private func columnText(_ statement: OpaquePointer?, _ index: Int32) -> String? {
    guard sqlite3_column_type(statement, index) != SQLITE_NULL,
          let text = sqlite3_column_text(statement, index) else {
        return nil
    }
    return String(cString: text)
}

private func decodeStringArray(_ rawValue: String?, decoder: JSONDecoder) -> [String] {
    guard let rawValue,
          let data = rawValue.data(using: .utf8),
          let items = try? decoder.decode([String].self, from: data) else {
        return []
    }
    return items
}
