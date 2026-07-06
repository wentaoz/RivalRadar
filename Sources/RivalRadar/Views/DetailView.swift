import SwiftUI

struct DetailView: View {
    @EnvironmentObject private var store: RivalRadarStore
    let selection: SidebarSelection

    var body: some View {
        ScrollView {
            Group {
                switch selection {
                case .dashboard:
                    DashboardView()
                case .competitors:
                    CompetitorsView()
                case .sources:
                    SourcesView()
                case .history:
                    HistoryView()
                case .reports:
                    ReportsView()
                case .logs:
                    LogsView()
                case .settings:
                    SettingsView()
                }
            }
            .environmentObject(store)
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .navigationTitle(selection.title)
    }
}
