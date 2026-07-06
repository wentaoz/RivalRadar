import SwiftUI

struct SidebarView: View {
    @Binding var selection: SidebarSelection

    var body: some View {
        List(selection: $selection) {
            Section {
                ForEach(SidebarSelection.allCases) { item in
                    Label(item.title, systemImage: item.systemImage)
                        .tag(item)
                }
            }
        }
        .listStyle(.sidebar)
        .navigationTitle("竞品雷达")
        .frame(minWidth: 220, idealWidth: 240)
    }
}
