import Foundation

enum ReportGeneratorError: LocalizedError {
    case zipFailed

    var errorDescription: String? {
        switch self {
        case .zipFailed:
            return "生成 Word 文档失败"
        }
    }
}

struct ReportGenerator {
    func generateReports(
        items: [IntelligenceItem],
        competitors: [Competitor],
        date: Date = Date(),
        reportsFolder: String
    ) throws -> [URL] {
        guard !items.isEmpty else { return [] }
        let fileManager = FileManager.default
        let dateString = AppDateFormatting.shortDate.string(from: date)
        let root = URL(fileURLWithPath: reportsFolder, isDirectory: true)
            .appendingPathComponent(dateString, isDirectory: true)
        try fileManager.createDirectory(at: root, withIntermediateDirectories: true)

        var generated: [URL] = []
        let allURL = root.appendingPathComponent("竞品雷达-\(dateString).docx")
        try writeDocx(
            title: "竞品雷达情报日报 \(dateString)",
            items: items,
            competitors: competitors,
            reportDate: date,
            outputURL: allURL
        )
        generated.append(allURL)

        let grouped = Dictionary(grouping: items, by: \.competitorID)
        for (competitorID, competitorItems) in grouped {
            let name = competitors.first(where: { $0.id == competitorID })?.name ?? "未知竞品"
            let outputURL = root.appendingPathComponent("\(name.fileNameSafe)-\(dateString).docx")
            try writeDocx(
                title: "\(name) 情报档案 \(dateString)",
                items: competitorItems,
                competitors: competitors,
                reportDate: date,
                outputURL: outputURL
            )
            generated.append(outputURL)
        }

        return generated
    }

    private func writeDocx(
        title: String,
        items: [IntelligenceItem],
        competitors: [Competitor],
        reportDate: Date,
        outputURL: URL
    ) throws {
        let fileManager = FileManager.default
        let tempRoot = fileManager.temporaryDirectory.appendingPathComponent("RivalRadarDocx-\(UUID().uuidString)", isDirectory: true)
        let rels = tempRoot.appendingPathComponent("_rels", isDirectory: true)
        let word = tempRoot.appendingPathComponent("word", isDirectory: true)
        let wordRels = word.appendingPathComponent("_rels", isDirectory: true)

        try fileManager.createDirectory(at: rels, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: wordRels, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: tempRoot) }

        try contentTypesXML.write(to: tempRoot.appendingPathComponent("[Content_Types].xml"), atomically: true, encoding: .utf8)
        try relsXML.write(to: rels.appendingPathComponent(".rels"), atomically: true, encoding: .utf8)
        try documentRelsXML.write(to: wordRels.appendingPathComponent("document.xml.rels"), atomically: true, encoding: .utf8)
        try stylesXML.write(to: word.appendingPathComponent("styles.xml"), atomically: true, encoding: .utf8)
        try documentXML(title: title, items: items, competitors: competitors, reportDate: reportDate)
            .write(to: word.appendingPathComponent("document.xml"), atomically: true, encoding: .utf8)

        try? fileManager.removeItem(at: outputURL)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/zip")
        process.arguments = ["-qr", outputURL.path, "[Content_Types].xml", "_rels", "word"]
        process.currentDirectoryURL = tempRoot
        try process.run()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            throw ReportGeneratorError.zipFailed
        }
    }

    private func documentXML(
        title: String,
        items: [IntelligenceItem],
        competitors: [Competitor],
        reportDate: Date
    ) -> String {
        let sortedItems = items.sorted { $0.discoveredAt > $1.discoveredAt }
        let grouped = Dictionary(grouping: sortedItems) { item in
            competitorName(for: item, competitors: competitors)
        }
        let competitorNames = grouped.keys.sorted()

        var blocks: [String] = [
            paragraph(title, style: "Title"),
            paragraph("生成时间：\(AppDateFormatting.dateTime.string(from: Date()))", style: "Subtitle"),
            metadataTable(items: sortedItems, competitorNames: competitorNames, reportDate: reportDate),
            paragraph("竞品概览", style: "Heading1"),
            competitorSummaryTable(grouped: grouped),
            paragraph("重点情报清单", style: "Heading1"),
            itemListTable(items: sortedItems, competitors: competitors)
        ]

        for competitorName in competitorNames {
            let competitorItems = grouped[competitorName] ?? []
            blocks.append(paragraph(competitorName, style: "Heading1"))
            blocks.append(itemListTable(items: competitorItems, competitors: competitors))
            blocks.append(paragraph("情报明细", style: "Heading2"))
            blocks.append(contentsOf: competitorItems.flatMap { detailBlocks(for: $0, competitors: competitors) })
        }

        return """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">
          <w:body>
            \(blocks.joined(separator: "\n"))
            <w:sectPr>
              <w:pgSz w:w="11906" w:h="16838"/>
              <w:pgMar w:top="1080" w:right="1080" w:bottom="1080" w:left="1080"/>
            </w:sectPr>
          </w:body>
        </w:document>
        """
    }

    private func metadataTable(items: [IntelligenceItem], competitorNames: [String], reportDate: Date) -> String {
        let highPriorityCount = items.filter { $0.importance >= 4 }.count
        let topCategories = categorySummary(items)
        return keyValueTable(rows: [
            ("报告日期", AppDateFormatting.shortDate.string(from: reportDate)),
            ("情报总数", "\(items.count) 条"),
            ("涉及竞品", competitorNames.joined(separator: "、")),
            ("高优先级", "\(highPriorityCount) 条（重要性 4-5）"),
            ("主要分类", topCategories.nilIfBlank ?? "暂无分类")
        ])
    }

    private func competitorSummaryTable(grouped: [String: [IntelligenceItem]]) -> String {
        let rows = grouped.keys.sorted().map { name -> [ReportCell] in
            let items = grouped[name] ?? []
            let latest = items.sorted { $0.discoveredAt > $1.discoveredAt }.first
            let maxImportance = items.map(\.importance).max() ?? 0
            return [
                ReportCell(name),
                ReportCell("\(items.count)", alignment: "center"),
                ReportCell("\(maxImportance)/5", alignment: "center"),
                ReportCell(categorySummary(items)),
                ReportCell(latest?.title.clipped(to: 80) ?? "-")
            ]
        }

        return table(
            headers: ["竞品", "数量", "最高重要性", "主要分类", "最新发现"],
            rows: rows,
            widths: [1600, 800, 1100, 2100, 3400]
        )
    }

    private func itemListTable(items: [IntelligenceItem], competitors: [Competitor]) -> String {
        let rows = items.sorted { $0.discoveredAt > $1.discoveredAt }.map { item in
            [
                ReportCell(AppDateFormatting.dateTime.string(from: item.discoveredAt), alignment: "center"),
                ReportCell("\(item.importance)/5", alignment: "center"),
                ReportCell(item.category.label, alignment: "center"),
                ReportCell(item.title.clipped(to: 120)),
                ReportCell("\(item.summary.clipped(to: 220))\n\(item.impact.clipped(to: 180))"),
                ReportCell(item.domain.nilIfBlank ?? competitorName(for: item, competitors: competitors), alignment: "center")
            ]
        }

        return table(
            headers: ["发现时间", "重要性", "分类", "标题", "摘要 / 影响", "来源"],
            rows: rows,
            widths: [1300, 700, 900, 2200, 2900, 1000]
        )
    }

    private func detailBlocks(for item: IntelligenceItem, competitors: [Competitor]) -> [String] {
        [
            paragraph(item.title, style: "Heading3"),
            keyValueTable(rows: [
                ("竞品", competitorName(for: item, competitors: competitors)),
                ("分类/重要性", "\(item.category.label) · \(item.importance)/5"),
                ("发现时间", AppDateFormatting.dateTime.string(from: item.discoveredAt)),
                ("来源域名", item.domain),
                ("来源链接", item.url),
                ("摘要", item.summary),
                ("影响/建议", item.impact),
                ("原文片段", item.rawContent.clipped(to: 700))
            ])
        ]
    }

    private func categorySummary(_ items: [IntelligenceItem]) -> String {
        let counts = Dictionary(grouping: items, by: { $0.category.label })
            .mapValues(\.count)
            .sorted {
                if $0.value == $1.value { return $0.key < $1.key }
                return $0.value > $1.value
            }
            .prefix(3)
        return counts.map { "\($0.key) \($0.value)" }.joined(separator: "、")
    }

    private func competitorName(for item: IntelligenceItem, competitors: [Competitor]) -> String {
        competitors.first(where: { $0.id == item.competitorID })?.name ?? "未知竞品"
    }

    private func keyValueTable(rows: [(String, String)]) -> String {
        table(
            headers: [],
            rows: rows.map { [ReportCell($0.0, isEmphasis: true), ReportCell($0.1)] },
            widths: [1600, 7400],
            showHeader: false
        )
    }

    private func table(
        headers: [String],
        rows: [[ReportCell]],
        widths: [Int],
        showHeader: Bool = true
    ) -> String {
        let tableWidth = widths.reduce(0, +)
        let grid = widths.map { "<w:gridCol w:w=\"\($0)\"/>" }.joined()
        let headerRow: String
        if showHeader {
            headerRow = row(
                headers.enumerated().map { index, value in
                    ReportCell(value, alignment: "center", isEmphasis: true, fill: "D9EAF7", width: widths[index])
                },
                widths: widths,
                isHeader: true
            )
        } else {
            headerRow = ""
        }
        let bodyRows = rows.map { row($0, widths: widths) }.joined(separator: "\n")

        return """
        <w:tbl>
          <w:tblPr>
            <w:tblW w:w="\(tableWidth)" w:type="dxa"/>
            <w:tblInd w:w="120" w:type="dxa"/>
            <w:tblBorders>
              <w:top w:val="single" w:sz="6" w:space="0" w:color="B7C7D8"/>
              <w:left w:val="single" w:sz="6" w:space="0" w:color="B7C7D8"/>
              <w:bottom w:val="single" w:sz="6" w:space="0" w:color="B7C7D8"/>
              <w:right w:val="single" w:sz="6" w:space="0" w:color="B7C7D8"/>
              <w:insideH w:val="single" w:sz="4" w:space="0" w:color="D7E0EA"/>
              <w:insideV w:val="single" w:sz="4" w:space="0" w:color="D7E0EA"/>
            </w:tblBorders>
            <w:tblCellMar>
              <w:top w:w="100" w:type="dxa"/>
              <w:left w:w="120" w:type="dxa"/>
              <w:bottom w:w="100" w:type="dxa"/>
              <w:right w:w="120" w:type="dxa"/>
            </w:tblCellMar>
          </w:tblPr>
          <w:tblGrid>\(grid)</w:tblGrid>
          \(headerRow)
          \(bodyRows)
        </w:tbl>
        \(paragraph("", spacingAfter: 160))
        """
    }

    private func row(_ cells: [ReportCell], widths: [Int], isHeader: Bool = false) -> String {
        let headerPr = isHeader ? "<w:trPr><w:tblHeader/></w:trPr>" : ""
        let cellsXML = cells.enumerated().map { index, cell in
            let width = index < widths.count ? widths[index] : cell.width
            return cellXML(cell, width: width)
        }.joined()
        return "<w:tr>\(headerPr)\(cellsXML)</w:tr>"
    }

    private func cellXML(_ cell: ReportCell, width: Int) -> String {
        let fillXML = cell.fill.map { "<w:shd w:fill=\"\($0)\"/>" } ?? ""
        let paragraphs = cell.text
            .components(separatedBy: .newlines)
            .map { cellParagraph($0, alignment: cell.alignment, isEmphasis: cell.isEmphasis) }
            .joined()
        return """
        <w:tc>
          <w:tcPr>
            <w:tcW w:w="\(width)" w:type="dxa"/>
            \(fillXML)
            <w:vAlign w:val="center"/>
          </w:tcPr>
          \(paragraphs)
        </w:tc>
        """
    }

    private func cellParagraph(_ text: String, alignment: String, isEmphasis: Bool) -> String {
        let boldXML = isEmphasis ? "<w:b/>" : ""
        return """
        <w:p>
          <w:pPr>
            <w:spacing w:after="40" w:line="260" w:lineRule="auto"/>
            <w:jc w:val="\(alignment)"/>
          </w:pPr>
          <w:r>
            <w:rPr>\(boldXML)<w:sz w:val="18"/><w:szCs w:val="18"/></w:rPr>
            <w:t>\(text.xmlEscaped)</w:t>
          </w:r>
        </w:p>
        """
    }

    private func paragraph(
        _ text: String,
        style: String? = nil,
        spacingAfter: Int? = nil
    ) -> String {
        var properties: [String] = []
        if let style {
            properties.append("<w:pStyle w:val=\"\(style)\"/>")
        }
        if let spacingAfter {
            properties.append("<w:spacing w:after=\"\(spacingAfter)\"/>")
        }
        let propertiesXML = properties.isEmpty ? "" : "<w:pPr>\(properties.joined())</w:pPr>"
        return "<w:p>\(propertiesXML)<w:r><w:t>\(text.xmlEscaped)</w:t></w:r></w:p>"
    }

    private var contentTypesXML: String {
        """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">
          <Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>
          <Default Extension="xml" ContentType="application/xml"/>
          <Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/>
          <Override PartName="/word/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.styles+xml"/>
        </Types>
        """
    }

    private var relsXML: String {
        """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
          <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="word/document.xml"/>
        </Relationships>
        """
    }

    private var documentRelsXML: String {
        """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
          <Relationship Id="rIdStyles" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/>
        </Relationships>
        """
    }

    private var stylesXML: String {
        """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <w:styles xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">
          <w:style w:type="paragraph" w:default="1" w:styleId="Normal">
            <w:name w:val="Normal"/>
            <w:qFormat/>
            <w:pPr><w:spacing w:after="120" w:line="300" w:lineRule="auto"/></w:pPr>
            <w:rPr>
              <w:rFonts w:ascii="Arial" w:hAnsi="Arial" w:eastAsia="PingFang SC"/>
              <w:sz w:val="21"/><w:szCs w:val="21"/>
              <w:color w:val="1F2937"/>
            </w:rPr>
          </w:style>
          <w:style w:type="paragraph" w:styleId="Title">
            <w:name w:val="Title"/>
            <w:basedOn w:val="Normal"/>
            <w:qFormat/>
            <w:pPr><w:spacing w:before="0" w:after="160"/></w:pPr>
            <w:rPr>
              <w:rFonts w:ascii="Arial" w:hAnsi="Arial" w:eastAsia="PingFang SC"/>
              <w:b/><w:sz w:val="34"/><w:szCs w:val="34"/><w:color w:val="0F3A5F"/>
            </w:rPr>
          </w:style>
          <w:style w:type="paragraph" w:styleId="Subtitle">
            <w:name w:val="Subtitle"/>
            <w:basedOn w:val="Normal"/>
            <w:qFormat/>
            <w:pPr><w:spacing w:after="220"/></w:pPr>
            <w:rPr><w:color w:val="667085"/><w:sz w:val="20"/><w:szCs w:val="20"/></w:rPr>
          </w:style>
          <w:style w:type="paragraph" w:styleId="Heading1">
            <w:name w:val="Heading 1"/>
            <w:basedOn w:val="Normal"/>
            <w:qFormat/>
            <w:pPr><w:keepNext/><w:spacing w:before="260" w:after="120"/></w:pPr>
            <w:rPr><w:b/><w:sz w:val="27"/><w:szCs w:val="27"/><w:color w:val="145388"/></w:rPr>
          </w:style>
          <w:style w:type="paragraph" w:styleId="Heading2">
            <w:name w:val="Heading 2"/>
            <w:basedOn w:val="Normal"/>
            <w:qFormat/>
            <w:pPr><w:keepNext/><w:spacing w:before="180" w:after="100"/></w:pPr>
            <w:rPr><w:b/><w:sz w:val="23"/><w:szCs w:val="23"/><w:color w:val="264A68"/></w:rPr>
          </w:style>
          <w:style w:type="paragraph" w:styleId="Heading3">
            <w:name w:val="Heading 3"/>
            <w:basedOn w:val="Normal"/>
            <w:qFormat/>
            <w:pPr><w:keepNext/><w:spacing w:before="120" w:after="80"/></w:pPr>
            <w:rPr><w:b/><w:sz w:val="21"/><w:szCs w:val="21"/><w:color w:val="1F2937"/></w:rPr>
          </w:style>
        </w:styles>
        """
    }
}

private struct ReportCell {
    var text: String
    var alignment: String
    var isEmphasis: Bool
    var fill: String?
    var width: Int

    init(
        _ text: String,
        alignment: String = "left",
        isEmphasis: Bool = false,
        fill: String? = nil,
        width: Int = 1200
    ) {
        self.text = text.nilIfBlank ?? "-"
        self.alignment = alignment
        self.isEmphasis = isEmphasis
        self.fill = fill
        self.width = width
    }
}
