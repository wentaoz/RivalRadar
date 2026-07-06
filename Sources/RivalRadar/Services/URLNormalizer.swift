import Foundation

enum URLNormalizer {
    static func normalize(_ rawURL: String) -> String {
        guard var components = URLComponents(string: rawURL.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            return rawURL.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        }

        components.scheme = components.scheme?.lowercased()
        components.host = components.host?.lowercased()
        components.fragment = nil

        let ignoredQueryNames: Set<String> = [
            "utm_source", "utm_medium", "utm_campaign", "utm_term", "utm_content",
            "fbclid", "gclid", "mc_cid", "mc_eid"
        ]

        let filteredItems = components.queryItems?
            .filter { !ignoredQueryNames.contains($0.name.lowercased()) }
            .sorted { lhs, rhs in
                lhs.name == rhs.name ? (lhs.value ?? "") < (rhs.value ?? "") : lhs.name < rhs.name
            }

        components.queryItems = filteredItems?.isEmpty == true ? nil : filteredItems

        var normalized = components.url?.absoluteString ?? rawURL
        if normalized.hasSuffix("/") {
            normalized.removeLast()
        }
        return normalized
    }

    static func domain(from rawURL: String) -> String {
        URLComponents(string: rawURL)?.host?.lowercased() ?? ""
    }
}
