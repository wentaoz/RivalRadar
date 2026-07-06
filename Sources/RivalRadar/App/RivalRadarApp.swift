import SwiftUI

@main
struct RivalRadarApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var store = RivalRadarStore()
    @Environment(\.openWindow) private var openWindow

    var body: some Scene {
        WindowGroup("竞品雷达", id: "main") {
            ContentView()
                .environmentObject(store)
                .frame(minWidth: 1080, minHeight: 700)
        }
        .commands {
            CommandMenu("竞品雷达") {
                Button("立即运行全部") {
                    store.runAllNow()
                }
                .keyboardShortcut("r", modifiers: [.command])
                .disabled(store.isRunning)

                Button("生成今日 Word 报告") {
                    store.generateTodayReports()
                }
                .keyboardShortcut("g", modifiers: [.command, .shift])
            }
        }

        MenuBarExtra("竞品雷达", systemImage: "scope") {
            Button(store.isRunning ? "运行中..." : "立即运行全部") {
                store.runAllNow()
            }
            .disabled(store.isRunning)

            Button("打开主窗口") {
                openMainWindow()
            }

            Button("生成今日报告") {
                store.generateTodayReports()
            }

            Divider()

            Text(store.statusText)
            Text("今日 \(store.todaysItems.count) 条")
            Text("数据源 \(store.enabledSources.count) 个")

            Divider()

            Button("退出竞品雷达") {
                NSApplication.shared.terminate(nil)
            }
            .keyboardShortcut("q")
        }
    }

    private func openMainWindow() {
        openWindow(id: "main")
        NSApplication.shared.activate(ignoringOtherApps: true)
    }
}
