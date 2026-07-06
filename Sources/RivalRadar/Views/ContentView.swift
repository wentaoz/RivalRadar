import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var store: RivalRadarStore
    @SceneStorage("selectedSidebarID") private var selectedSidebarID = SidebarSelection.dashboard.rawValue

    private var selection: Binding<SidebarSelection> {
        Binding(
            get: { SidebarSelection(rawValue: selectedSidebarID) ?? .dashboard },
            set: { selectedSidebarID = $0.rawValue }
        )
    }

    var body: some View {
        NavigationSplitView {
            SidebarView(selection: selection)
        } detail: {
            DetailView(selection: selection.wrappedValue)
                .environmentObject(store)
        }
        .frame(minWidth: 980, minHeight: 720)
    }
}
