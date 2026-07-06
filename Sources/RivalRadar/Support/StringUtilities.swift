import Foundation

extension String {
    var nilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    func clipped(to limit: Int) -> String {
        guard count > limit else { return self }
        let index = self.index(startIndex, offsetBy: limit)
        return String(self[..<index]) + "..."
    }

    func splitList() -> [String] {
        components(separatedBy: CharacterSet(charactersIn: ",，\n"))
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    var xmlEscaped: String {
        replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&apos;")
    }

    var fileNameSafe: String {
        let invalid = CharacterSet(charactersIn: "/\\?%*|\"<>:")
        let clean = components(separatedBy: invalid).joined(separator: "-")
        return clean.trimmingCharacters(in: .whitespacesAndNewlines).nilIfBlank ?? "未命名"
    }
}

enum AppDateFormatting {
    static let dateTime: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()

    static let shortDate: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()
}
