import Foundation

enum DedupeService {
    static func fingerprints(for raw: RawCollectedItem, competitor: Competitor) -> (normalizedURL: String, domain: String, urlHash: String, titleHash: String, contentHash: String) {
        let normalizedURL = URLNormalizer.normalize(raw.url)
        let domain = URLNormalizer.domain(from: normalizedURL)
        let compactTitle = normalizeText(raw.title)
        let compactContent = normalizeText(raw.content.clipped(to: 4_000))
        let competitorKey = competitor.name.lowercased()

        return (
            normalizedURL,
            domain,
            Hashing.sha256(normalizedURL),
            Hashing.sha256("\(competitorKey)|\(domain)|\(compactTitle)"),
            Hashing.sha256("\(competitorKey)|\(compactContent)")
        )
    }

    static func isSimilarTitle(_ lhs: String, _ rhs: String, threshold: Double = 0.72) -> Bool {
        similarity(lhs, rhs) >= threshold
    }

    static func similarity(_ lhs: String, _ rhs: String) -> Double {
        let left = Set(tokens(lhs))
        let right = Set(tokens(rhs))
        guard !left.isEmpty, !right.isEmpty else { return 0 }
        let intersection = left.intersection(right).count
        let union = left.union(right).count
        return Double(intersection) / Double(union)
    }

    private static func tokens(_ value: String) -> [String] {
        normalizeText(value)
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { $0.count > 1 }
    }

    private static func normalizeText(_ value: String) -> String {
        value.lowercased()
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
