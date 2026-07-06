import Foundation

enum HTMLExtractor {
    static func extract(from data: Data, sourceURL: URL) -> RawCollectedItem {
        let html = String(data: data, encoding: .utf8)
            ?? String(data: data, encoding: .isoLatin1)
            ?? ""
        return extract(fromHTML: html, sourceURL: sourceURL)
    }

    static func extract(fromHTML html: String, sourceURL: URL) -> RawCollectedItem {
        let title = firstMatch(
            in: html,
            pattern: "<title[^>]*>(.*?)</title>"
        )
        .map(cleanText)
        .flatMap(\.nilIfBlank)
        ?? sourceURL.absoluteString

        let withoutScripts = html
            .replacingOccurrences(of: "<script[\\s\\S]*?</script>", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "<style[\\s\\S]*?</style>", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "<noscript[\\s\\S]*?</noscript>", with: " ", options: .regularExpression)

        let text = cleanText(
            withoutScripts
                .replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
                .replacingOccurrences(of: "&nbsp;", with: " ")
                .replacingOccurrences(of: "&amp;", with: "&")
                .replacingOccurrences(of: "&lt;", with: "<")
                .replacingOccurrences(of: "&gt;", with: ">")
                .replacingOccurrences(of: "&quot;", with: "\"")
        )

        return RawCollectedItem(
            title: title,
            url: sourceURL.absoluteString,
            content: text.clipped(to: 20_000),
            publishedAt: nil,
            sourceName: sourceURL.host ?? "Web"
        )
    }

    private static func firstMatch(in value: String, pattern: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive, .dotMatchesLineSeparators]) else {
            return nil
        }
        let range = NSRange(value.startIndex..<value.endIndex, in: value)
        guard let match = regex.firstMatch(in: value, range: range),
              match.numberOfRanges > 1,
              let matchRange = Range(match.range(at: 1), in: value) else {
            return nil
        }
        return String(value[matchRange])
    }

    private static func cleanText(_ value: String) -> String {
        value.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
