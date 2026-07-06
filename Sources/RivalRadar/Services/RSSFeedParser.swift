import Foundation

final class RSSFeedParser: NSObject, XMLParserDelegate {
    private var items: [RawCollectedItem] = []
    private var currentItem: [String: String] = [:]
    private var currentElement = ""
    private var buffer = ""
    private var isInsideItem = false
    private let feedURL: URL

    init(feedURL: URL) {
        self.feedURL = feedURL
    }

    func parse(data: Data) -> [RawCollectedItem] {
        items = []
        let parser = XMLParser(data: data)
        parser.delegate = self
        parser.parse()
        return items
    }

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String: String] = [:]) {
        currentElement = elementName.lowercased()
        buffer = ""
        if currentElement == "item" || currentElement == "entry" {
            isInsideItem = true
            currentItem = [:]
        }
        if isInsideItem, currentElement == "link", let href = attributeDict["href"] {
            currentItem["link"] = href
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        buffer += string
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        let name = elementName.lowercased()
        defer {
            buffer = ""
            currentElement = ""
        }

        guard isInsideItem else { return }

        if name == "item" || name == "entry" {
            let title = currentItem["title"]?.nilIfBlank ?? feedURL.absoluteString
            let link = currentItem["link"]?.nilIfBlank ?? feedURL.absoluteString
            let content = currentItem["content"]?.nilIfBlank
                ?? currentItem["summary"]?.nilIfBlank
                ?? currentItem["description"]?.nilIfBlank
                ?? title
            let published = currentItem["published"] ?? currentItem["updated"] ?? currentItem["pubdate"]
            items.append(
                RawCollectedItem(
                    title: title,
                    url: absoluteURL(link),
                    content: HTMLExtractor.extract(fromHTML: content, sourceURL: feedURL).content,
                    publishedAt: DateParsing.parse(published),
                    sourceName: feedURL.host ?? "RSS"
                )
            )
            currentItem = [:]
            isInsideItem = false
            return
        }

        let value = buffer.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return }
        switch name {
        case "title":
            currentItem["title"] = value
        case "link":
            if currentItem["link"] == nil {
                currentItem["link"] = value
            }
        case "description":
            currentItem["description"] = value
        case "summary":
            currentItem["summary"] = value
        case "content", "content:encoded":
            currentItem["content"] = value
        case "published", "updated", "pubdate":
            currentItem[name] = value
        default:
            break
        }
    }

    private func absoluteURL(_ value: String) -> String {
        guard let url = URL(string: value, relativeTo: feedURL) else { return value }
        return url.absoluteURL.absoluteString
    }
}

enum DateParsing {
    static func parse(_ rawValue: String?) -> Date? {
        guard let rawValue = rawValue?.nilIfBlank else { return nil }
        if let date = ISO8601DateFormatter().date(from: rawValue) {
            return date
        }

        let formats = [
            "EEE, dd MMM yyyy HH:mm:ss Z",
            "EEE, d MMM yyyy HH:mm:ss Z",
            "yyyy-MM-dd HH:mm:ss",
            "yyyy-MM-dd"
        ]
        for format in formats {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.dateFormat = format
            if let date = formatter.date(from: rawValue) {
                return date
            }
        }
        return nil
    }
}
