import AppKit
import SwiftUI

struct ReportsView: View {
    @EnvironmentObject private var store: RivalRadarStore

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            SectionCard(title: "报告目录", systemImage: "folder") {
                HStack(alignment: .top) {
                    AdaptiveTextArea(placeholder: "报告输出目录", text: $store.reportsFolder, minLines: 1, maxLines: 4)

                    Button {
                        chooseFolder()
                    } label: {
                        Image(systemName: "folder")
                    }
                    .help("选择目录")

                    Button {
                        openFolder()
                    } label: {
                        Image(systemName: "arrow.up.forward.app")
                    }
                    .help("在 Finder 中打开")
                }
            }

            SectionCard(title: "今日报告", systemImage: "doc.richtext") {
                HStack {
                    Button {
                        store.generateTodayReports()
                    } label: {
                        Label("生成今日 Word 报告", systemImage: "doc.badge.plus")
                    }

                    Text("今天 \(store.todaysItems.count) 条情报")
                        .foregroundStyle(.secondary)
                }

                if !store.lastGeneratedReports.isEmpty {
                    Divider()
                    ForEach(store.lastGeneratedReports, id: \.path) { url in
                        HStack {
                            Image(systemName: "doc.richtext")
                            Text(url.lastPathComponent)
                            Spacer()
                            Button("打开") {
                                NSWorkspace.shared.open(url)
                            }
                        }
                    }
                }
            }

            SectionCard(title: "生成规则", systemImage: "info.circle") {
                Text("每次有新情报后，竞品雷达会从本地数据库读取当天数据并重生成当天 Word 文档：一份总日报，以及每个竞品各一份文档。跨天会自动创建新的日期目录。")
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url {
            store.reportsFolder = url.path
        }
    }

    private func openFolder() {
        let url = URL(fileURLWithPath: store.reportsFolder, isDirectory: true)
        NSWorkspace.shared.open(url)
    }
}
