import SwiftUI

struct DashboardView: View {
    @EnvironmentObject private var store: RivalRadarStore

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 12) { metrics }
                VStack(spacing: 12) { metrics }
            }

            SectionCard(title: "采集控制", systemImage: "play.circle") {
                HStack(spacing: 12) {
                    Button {
                        store.runAllNow()
                    } label: {
                        Label(store.isRunning ? "运行中" : "立即运行全部", systemImage: "arrow.clockwise")
                    }
                    .disabled(store.isRunning)

                    Button {
                        store.generateTodayReports()
                    } label: {
                        Label("生成今日 Word 报告", systemImage: "doc.richtext")
                    }

                    Spacer()

                    Label(store.statusText, systemImage: store.isRunning ? "hourglass" : "info.circle")
                        .foregroundStyle(.secondary)
                }
            }

            SectionCard(title: "今日新增", systemImage: "calendar") {
                if store.todaysItems.isEmpty {
                    Text("今天暂无新增情报。")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(store.todaysItems.prefix(8)) { item in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(item.title)
                                .font(.headline)
                            Text("\(store.competitorName(for: item.competitorID)) · \(item.category.label) · 重要性 \(item.importance)/5")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text(item.summary)
                                .foregroundStyle(.secondary)
                        }
                        Divider()
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var metrics: some View {
        MetricTile(title: "竞品", value: "\(store.competitors.count)", systemImage: "building.2")
        MetricTile(title: "启用数据源", value: "\(store.enabledSources.count)", systemImage: "antenna.radiowaves.left.and.right")
        MetricTile(title: "今日情报", value: "\(store.todaysItems.count)", systemImage: "newspaper")
        MetricTile(title: "历史情报", value: "\(store.items.count)", systemImage: "tray.full")
    }
}
