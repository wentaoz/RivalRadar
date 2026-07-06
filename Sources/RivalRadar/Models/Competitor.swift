import Foundation

struct Competitor: Identifiable, Codable, Hashable {
    var id: UUID
    var name: String
    var aliases: [String]
    var keywords: [String]
    var notes: String
    var isEnabled: Bool
    var createdAt: Date

    init(
        id: UUID = UUID(),
        name: String,
        aliases: [String] = [],
        keywords: [String] = [],
        notes: String = "",
        isEnabled: Bool = true,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.aliases = aliases
        self.keywords = keywords
        self.notes = notes
        self.isEnabled = isEnabled
        self.createdAt = createdAt
    }
}
