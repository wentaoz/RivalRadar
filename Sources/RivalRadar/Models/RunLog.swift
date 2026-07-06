import Foundation

enum RunStatus: String, Codable, CaseIterable {
    case running
    case success
    case failed
    case skipped

    var label: String {
        switch self {
        case .running:
            return "运行中"
        case .success:
            return "成功"
        case .failed:
            return "失败"
        case .skipped:
            return "跳过"
        }
    }
}

struct RunLog: Identifiable, Codable, Hashable {
    var id: UUID
    var sourceID: UUID?
    var sourceName: String
    var startedAt: Date
    var finishedAt: Date?
    var status: RunStatus
    var message: String
    var newCount: Int

    init(
        id: UUID = UUID(),
        sourceID: UUID?,
        sourceName: String,
        startedAt: Date = Date(),
        finishedAt: Date? = nil,
        status: RunStatus = .running,
        message: String = "",
        newCount: Int = 0
    ) {
        self.id = id
        self.sourceID = sourceID
        self.sourceName = sourceName
        self.startedAt = startedAt
        self.finishedAt = finishedAt
        self.status = status
        self.message = message
        self.newCount = newCount
    }
}
