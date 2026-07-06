import SwiftUI

struct CompetitorsView: View {
    @EnvironmentObject private var store: RivalRadarStore
    @State private var selectedID: UUID?
    @State private var name = ""
    @State private var aliasesText = ""
    @State private var keywordsText = ""
    @State private var notes = ""
    @State private var isEnabled = true

    var body: some View {
        ViewThatFits(in: .horizontal) {
            content(axis: .horizontal)
            content(axis: .vertical)
        }
        .onAppear {
            if selectedID == nil {
                selectedID = store.competitors.first?.id
                loadSelected()
            }
        }
    }

    @ViewBuilder
    private func content(axis: Axis) -> some View {
        let isHorizontal = axis == .horizontal
        Group {
            if isHorizontal {
                HStack(alignment: .top, spacing: 16) {
                    listCard
                        .frame(width: 280)
                    configCard
                }
            } else {
                VStack(alignment: .leading, spacing: 16) {
                    listCard
                    configCard
                }
            }
        }
    }

    private var listCard: some View {
            SectionCard(title: "竞品列表", systemImage: "building.2") {
                VStack(alignment: .leading, spacing: 10) {
                    Button {
                        store.addCompetitor()
                        selectedID = store.competitors.first?.id
                        loadSelected()
                    } label: {
                        Label("添加竞品", systemImage: "plus")
                    }

                    ForEach(store.competitors) { competitor in
                        Button {
                            selectedID = competitor.id
                            loadSelected()
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(competitor.name)
                                        .lineLimit(1)
                                    Text(competitor.keywords.joined(separator: ", "))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }
                                Spacer()
                                if selectedID == competitor.id {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                        .buttonStyle(.plain)
                        Divider()
                    }
                }
            }
    }

    private var configCard: some View {
            SectionCard(title: "竞品配置", systemImage: "slider.horizontal.3") {
                if selectedID == nil {
                    Text("选择或添加一个竞品。")
                        .foregroundStyle(.secondary)
                } else {
                    VStack(alignment: .leading, spacing: 12) {
                        TextField("竞品名称", text: $name)
                            .textFieldStyle(.roundedBorder)

                        AdaptiveTextArea(placeholder: "别名，用逗号或换行分隔", text: $aliasesText, minLines: 2, maxLines: 8)

                        AdaptiveTextArea(placeholder: "关键词，用逗号或换行分隔", text: $keywordsText, minLines: 2, maxLines: 10)

                        AdaptiveTextArea(placeholder: "备注", text: $notes, minLines: 3, maxLines: 14)

                        Toggle("启用该竞品", isOn: $isEnabled)

                        HStack {
                            Button {
                                save()
                            } label: {
                                Label("保存", systemImage: "checkmark")
                            }
                            .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                            Button(role: .destructive) {
                                delete()
                            } label: {
                                Label("删除", systemImage: "trash")
                            }
                        }
                    }
                }
            }
    }

    private func loadSelected() {
        guard let selectedID,
              let competitor = store.competitors.first(where: { $0.id == selectedID }) else {
            name = ""
            aliasesText = ""
            keywordsText = ""
            notes = ""
            isEnabled = true
            return
        }
        name = competitor.name
        aliasesText = competitor.aliases.joined(separator: "\n")
        keywordsText = competitor.keywords.joined(separator: "\n")
        notes = competitor.notes
        isEnabled = competitor.isEnabled
    }

    private func save() {
        guard let selectedID else { return }
        let existing = store.competitors.first(where: { $0.id == selectedID })
        store.saveCompetitor(
            Competitor(
                id: selectedID,
                name: name.trimmingCharacters(in: .whitespacesAndNewlines),
                aliases: aliasesText.splitList(),
                keywords: keywordsText.splitList(),
                notes: notes,
                isEnabled: isEnabled,
                createdAt: existing?.createdAt ?? Date()
            )
        )
    }

    private func delete() {
        guard let selectedID,
              let competitor = store.competitors.first(where: { $0.id == selectedID }) else { return }
        store.deleteCompetitor(competitor)
        self.selectedID = store.competitors.first?.id
        loadSelected()
    }
}
