import AppKit
import SwiftUI

struct LogsView: View {
    @EnvironmentObject private var store: RivalRadarStore
    @State private var timeFilter = TimeFilterPreset.all
    @State private var startDate = Calendar.current.date(byAdding: .day, value: -7, to: Date()) ?? Date()
    @State private var endDate = Date()
    @State private var statusFilter = LogStatusFilter.all
    @State private var searchText = ""

    var body: some View {
        SectionCard(title: "运行记录", systemImage: "list.bullet.rectangle") {
            TimeFilterBar(
                preset: $timeFilter,
                startDate: $startDate,
                endDate: $endDate,
                resultCount: filteredLogs.count,
                totalCount: store.runLogs.count
            )

            HStack(spacing: 12) {
                Picker("状态", selection: $statusFilter) {
                    ForEach(LogStatusFilter.allCases) { filter in
                        Text(filter.label).tag(filter)
                    }
                }
                .pickerStyle(.segmented)

                TextField("搜索来源、错误信息或日志内容", text: $searchText)
                    .textFieldStyle(.roundedBorder)
            }

            if store.runLogs.isEmpty {
                Text("暂无运行记录。")
                    .foregroundStyle(.secondary)
            } else if filteredLogs.isEmpty {
                Text("当前时间范围内暂无运行记录。")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(filteredLogs) { log in
                    logRow(log)
                    Divider()
                }
            }
        }
    }

    private var filteredLogs: [RunLog] {
        store.runLogs.filter { log in
            guard timeFilter.contains(log.startedAt, startDate: startDate, endDate: endDate) else {
                return false
            }
            guard statusFilter.includes(log.status) else {
                return false
            }
            guard let query = searchText.nilIfBlank?.lowercased() else {
                return true
            }
            return log.sourceName.lowercased().contains(query) ||
                log.message.lowercased().contains(query) ||
                log.status.label.lowercased().contains(query)
        }
    }

    private func logRow(_ log: RunLog) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon(for: log.status))
                .foregroundStyle(color(for: log.status))
                .frame(width: 22)

            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text(log.sourceName)
                        .font(.headline)
                    Text(log.status.label)
                        .font(.caption)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(color(for: log.status).opacity(0.14), in: Capsule())
                        .foregroundStyle(color(for: log.status))
                    Spacer()
                    Button {
                        copy(log)
                    } label: {
                        Image(systemName: "doc.on.doc")
                    }
                    .buttonStyle(.borderless)
                    .help("复制日志")
                }

                Text("开始：\(AppDateFormatting.dateTime.string(from: log.startedAt)) · 结束：\(finishedText(for: log)) · 耗时：\(durationText(for: log)) · 新增 \(log.newCount)")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                DisclosureGroup("查看详情") {
                    VStack(alignment: .leading, spacing: 8) {
                        if let sourceID = log.sourceID {
                            Text("数据源 ID：\(sourceID.uuidString)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Text(log.message)
                            .foregroundStyle(log.status == .failed ? Color.red : Color.secondary)
                            .textSelection(.enabled)
                    }
                    .padding(.top, 4)
                }
            }
        }
    }

    private func finishedText(for log: RunLog) -> String {
        log.finishedAt.map { AppDateFormatting.dateTime.string(from: $0) } ?? "未结束"
    }

    private func durationText(for log: RunLog) -> String {
        guard let finishedAt = log.finishedAt else { return "进行中" }
        let seconds = max(0, Int(finishedAt.timeIntervalSince(log.startedAt).rounded()))
        if seconds < 60 { return "\(seconds) 秒" }
        let minutes = seconds / 60
        let remaining = seconds % 60
        return "\(minutes) 分 \(remaining) 秒"
    }

    private func copy(_ log: RunLog) {
        let value = """
        来源：\(log.sourceName)
        状态：\(log.status.label)
        开始：\(AppDateFormatting.dateTime.string(from: log.startedAt))
        结束：\(finishedText(for: log))
        耗时：\(durationText(for: log))
        新增：\(log.newCount)
        数据源 ID：\(log.sourceID?.uuidString ?? "-")
        日志：
        \(log.message)
        """
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(value, forType: .string)
    }

    private func icon(for status: RunStatus) -> String {
        switch status {
        case .running:
            return "hourglass"
        case .success:
            return "checkmark.circle"
        case .failed:
            return "xmark.octagon"
        case .skipped:
            return "minus.circle"
        }
    }

    private func color(for status: RunStatus) -> Color {
        switch status {
        case .running:
            return .secondary
        case .success:
            return .green
        case .failed:
            return .red
        case .skipped:
            return .orange
        }
    }
}

private enum LogStatusFilter: String, CaseIterable, Identifiable {
    case all
    case running
    case success
    case failed
    case skipped

    var id: String { rawValue }

    var label: String {
        switch self {
        case .all:
            return "全部"
        case .running:
            return "运行中"
        case .success:
            return "成功"
        case .failed:
            return "失败"
        case .skipped:
            return "跳过"
        }
    }

    func includes(_ status: RunStatus) -> Bool {
        switch self {
        case .all:
            return true
        case .running:
            return status == .running
        case .success:
            return status == .success
        case .failed:
            return status == .failed
        case .skipped:
            return status == .skipped
        }
    }
}
