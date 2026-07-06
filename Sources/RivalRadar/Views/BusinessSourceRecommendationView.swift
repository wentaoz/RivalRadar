import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct BusinessSourceRecommendationView: View {
    @Binding var jsonText: String
    @Binding var statusText: String
    var recommendationAction: (String, Int) async throws -> String
    var importAction: () throws -> SourceRecommendationImportResult
    var summaryAction: (String) throws -> SourceRecommendationSummary

    @State private var businessDescription = "监控菲律宾和印度小贷业务竞品，关注放款产品、利率费用、风控、监管牌照、用户投诉、营销获客、App 评价和融资动态。"
    @State private var marketLanguageHints = "市场：philippines, india\n语言：en, fil, hi, ta"
    @State private var competitorCount = 20
    @State private var isGenerating = false
    @State private var showJSONPreview = true
    @State private var summary: SourceRecommendationSummary?

    var body: some View {
        SectionCard(title: "业务描述智能推荐", systemImage: "sparkles") {
            VStack(alignment: .leading, spacing: 16) {
                intro
                inputArea
                actionBar
                summaryArea

                DisclosureGroup("查看和修改推荐 JSON", isExpanded: $showJSONPreview) {
                    VStack(alignment: .leading, spacing: 10) {
                        AdaptiveTextArea(
                            placeholder: "AI 推荐后会在这里展示通用数据源 JSON，也可以直接粘贴或修改 JSON。",
                            text: $jsonText,
                            minLines: 12,
                            maxLines: 38,
                            monospaced: true
                        )
                        .onChange(of: jsonText) { _ in
                            refreshSummary(silent: true)
                        }

                        Text("JSON 不保存 Tavily Key、模型 Key、Cookie 或 Chrome 路径；登录来源和通用 Search API 会默认导入为未启用。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.top, 8)
                }
            }
            .onAppear {
                refreshSummary(silent: true)
            }
        }
    }

    private var intro: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("输入业务目标后，系统会先用 Tavily 发现公开资料，再交给当前配置的大模型生成竞品、关键词、来源类型和可导入 JSON。")
                .foregroundStyle(.secondary)
            Text("建议：描述里写清国家、业务类型、产品关注点、监管/舆情/增长等重点。生成后先看摘要和 JSON，再确认导入。")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var inputArea: some View {
        GroupBox("第 1 步：描述你要监控的业务") {
            VStack(alignment: .leading, spacing: 10) {
                AdaptiveTextArea(
                    placeholder: "例如：监控菲律宾和印度小贷业务竞品，关注放款产品、利率费用、风控、监管牌照、用户投诉、营销获客和融资动态。",
                    text: $businessDescription,
                    minLines: 4,
                    maxLines: 16
                )

                AdaptiveTextArea(
                    placeholder: "市场和语言提示（可选），例如：市场：philippines, india；语言：en, fil, hi",
                    text: $marketLanguageHints,
                    minLines: 2,
                    maxLines: 8
                )

                HStack(spacing: 14) {
                    Stepper("推荐竞品数量 \(competitorCount)", value: $competitorCount, in: 1...30)
                    Text("默认 20 个；演示或试跑建议 5-10 个，正式监控再扩大。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                }
            }
            .padding(.vertical, 6)
        }
    }

    private var actionBar: some View {
        HStack(spacing: 10) {
            Button {
                Task {
                    await generateRecommendation()
                }
            } label: {
                Label(isGenerating ? "正在智能推荐..." : "智能推荐数据源", systemImage: "wand.and.stars")
            }
            .disabled(isGenerating || businessDescription.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

            Button {
                confirmImport()
            } label: {
                Label("确认导入", systemImage: "square.and.arrow.down")
            }
            .disabled(jsonText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

            Button {
                exportJSON()
            } label: {
                Label("导出 JSON", systemImage: "square.and.arrow.up")
            }
            .disabled(jsonText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

            Button {
                refreshSummary(silent: false)
            } label: {
                Label("刷新预览", systemImage: "arrow.clockwise")
            }
            .disabled(jsonText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

            Spacer()

            if !statusText.isEmpty {
                Text(statusText)
                    .font(.caption)
                    .foregroundStyle(statusText.contains("失败") || statusText.contains("错误") ? Color.red : Color.secondary)
                    .lineLimit(3)
            }
        }
    }

    @ViewBuilder
    private var summaryArea: some View {
        if let summary {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 10) {
                    MetricTile(title: "竞品", value: "\(summary.competitorCount)", systemImage: "building.2")
                    MetricTile(title: "数据源", value: "\(summary.sourceCount)", systemImage: "antenna.radiowaves.left.and.right")
                    MetricTile(title: "需人工配置", value: "\(summary.disabledSourceCount)", systemImage: "wrench.and.screwdriver")
                }

                if !summary.recommendationSummary.isEmpty {
                    Text(summary.recommendationSummary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                HStack(spacing: 8) {
                    ForEach(summary.typeCounts, id: \.0) { type, count in
                        Label("\(type.label) \(count)", systemImage: type.systemImage)
                            .font(.caption)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 5)
                            .background(.quaternary, in: RoundedRectangle(cornerRadius: 6))
                    }
                }

                VStack(alignment: .leading, spacing: 0) {
                    previewHeader
                    ForEach(Array(summary.rows.prefix(12).enumerated()), id: \.element.id) { _, row in
                        previewRow(row)
                        Divider()
                    }
                }
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Color.secondary.opacity(0.18))
                )

                if summary.rows.count > 12 {
                    Text("仅展示前 12 条，完整内容请查看 JSON。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var previewHeader: some View {
        HStack(spacing: 10) {
            Text("竞品")
                .frame(width: 150, alignment: .leading)
            Text("市场")
                .frame(width: 100, alignment: .leading)
            Text("来源")
                .frame(width: 220, alignment: .leading)
            Text("类型")
                .frame(width: 120, alignment: .leading)
            Text("状态/原因")
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .font(.caption.weight(.semibold))
        .foregroundStyle(.secondary)
        .padding(8)
        .background(.quaternary)
    }

    private func previewRow(_ row: SourceRecommendationPreviewRow) -> some View {
        HStack(spacing: 10) {
            Text(row.competitorName)
                .frame(width: 150, alignment: .leading)
                .lineLimit(2)
            Text(row.market.isEmpty ? "-" : row.market)
                .frame(width: 100, alignment: .leading)
                .lineLimit(1)
                .foregroundStyle(.secondary)
            Text(row.sourceName)
                .frame(width: 220, alignment: .leading)
                .lineLimit(2)
            Label(row.type.label, systemImage: row.type.systemImage)
                .frame(width: 120, alignment: .leading)
                .lineLimit(1)
            Label(row.isEnabled ? "启用" : row.reason, systemImage: row.isEnabled ? "checkmark.circle" : "exclamationmark.triangle")
                .foregroundStyle(row.isEnabled ? Color.secondary : Color.orange)
                .frame(maxWidth: .infinity, alignment: .leading)
                .lineLimit(2)
        }
        .font(.caption)
        .padding(8)
    }

    private func generateRecommendation() async {
        isGenerating = true
        statusText = "正在调用 Tavily 和 AI 生成推荐..."
        defer { isGenerating = false }

        do {
            jsonText = try await recommendationAction(recommendationDescription, competitorCount)
            showJSONPreview = true
            refreshSummary(silent: true)
            statusText = "已生成推荐 JSON，请确认后导入"
        } catch {
            statusText = "智能推荐失败：\(error.localizedDescription)"
        }
    }

    private func confirmImport() {
        do {
            let result = try importAction()
            var message = "已导入/更新 \(result.competitors) 个竞品，\(result.sources) 个数据源"
            if result.disabledSources > 0 {
                message += "，其中 \(result.disabledSources) 个需配置后启用"
            }
            if result.skippedSources > 0 {
                message += "，跳过 \(result.skippedSources) 个缺少 URL/Endpoint 的来源"
            }
            statusText = message
            refreshSummary(silent: true)
        } catch {
            statusText = "导入失败：\(error.localizedDescription)"
        }
    }

    private func refreshSummary(silent: Bool) {
        guard !jsonText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            summary = nil
            return
        }

        do {
            summary = try summaryAction(jsonText)
            if !silent {
                statusText = "预览已刷新"
            }
        } catch {
            summary = nil
            if !silent {
                statusText = "预览失败：\(error.localizedDescription)"
            }
        }
    }

    private func exportJSON() {
        let panel = NSSavePanel()
        panel.title = "导出推荐数据源 JSON"
        panel.prompt = "导出"
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "RivalRadar-数据源推荐.json"

        guard panel.runModal() == .OK, let url = panel.url else { return }

        do {
            try jsonText.write(to: url, atomically: true, encoding: .utf8)
            statusText = "已导出 JSON：\(url.lastPathComponent)"
        } catch {
            statusText = "导出失败：\(error.localizedDescription)"
        }
    }

    private var recommendationDescription: String {
        [
            businessDescription.nilIfBlank,
            marketLanguageHints.nilIfBlank.map { "市场和语言提示：\n\($0)" }
        ]
        .compactMap { $0 }
        .joined(separator: "\n\n")
    }
}
