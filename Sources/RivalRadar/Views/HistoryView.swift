import AppKit
import SwiftUI

struct HistoryView: View {
    @EnvironmentObject private var store: RivalRadarStore
    @State private var timeFilter = TimeFilterPreset.all
    @State private var startDate = Calendar.current.date(byAdding: .day, value: -7, to: Date()) ?? Date()
    @State private var endDate = Date()

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionCard(title: "情报历史", systemImage: "tray.full") {
                TimeFilterBar(
                    preset: $timeFilter,
                    startDate: $startDate,
                    endDate: $endDate,
                    resultCount: filteredItems.count,
                    totalCount: store.items.count
                )

                if store.items.isEmpty {
                    Text("暂无情报。配置数据源后点击“立即运行全部”。")
                        .foregroundStyle(.secondary)
                } else if filteredItems.isEmpty {
                    Text("当前时间范围内暂无情报。")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(filteredItems) { item in
                        VStack(alignment: .leading, spacing: 6) {
                            HStack(alignment: .firstTextBaseline) {
                                Text(item.title)
                                    .font(.headline)
                                Spacer()
                                Text("\(item.importance)/5")
                                    .font(.caption)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 3)
                                    .background(.quaternary, in: Capsule())
                            }

                            Text("\(store.competitorName(for: item.competitorID)) · \(item.category.label) · \(AppDateFormatting.dateTime.string(from: item.discoveredAt))")
                                .font(.caption)
                                .foregroundStyle(.secondary)

                            Text(item.summary)
                            Text(item.impact)
                                .foregroundStyle(.secondary)

                            HStack {
                                Button {
                                    open(item.url)
                                } label: {
                                    Label("打开来源", systemImage: "safari")
                                }
                                .buttonStyle(.borderless)

                                Text(item.domain)
                                    .font(.caption)
                                    .foregroundStyle(.tertiary)
                            }
                        }
                        Divider()
                    }
                }
            }
        }
    }

    private var filteredItems: [IntelligenceItem] {
        store.items.filter { item in
            timeFilter.contains(item.discoveredAt, startDate: startDate, endDate: endDate)
        }
    }

    private func open(_ rawURL: String) {
        guard let url = URL(string: rawURL) else { return }
        NSWorkspace.shared.open(url)
    }
}
