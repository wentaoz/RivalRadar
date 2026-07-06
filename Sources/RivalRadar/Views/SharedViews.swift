import SwiftUI

struct SectionCard<Content: View>: View {
    var title: String
    var systemImage: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(title, systemImage: systemImage)
                .font(.headline)
            content
        }
        .padding(14)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
    }
}

struct AdaptiveTextArea: View {
    var placeholder: String
    @Binding var text: String
    var minLines: Int = 2
    var maxLines: Int = 12
    var monospaced: Bool = false

    private var lineHeight: CGFloat { monospaced ? 19 : 20 }
    private var verticalPadding: CGFloat { 18 }

    var body: some View {
        ZStack(alignment: .topLeading) {
            TextEditor(text: $text)
                .font(monospaced ? .system(.body, design: .monospaced) : .body)
                .frame(height: editorHeight)
                .scrollContentBackground(.hidden)
                .padding(.horizontal, 2)

            if text.isEmpty {
                Text(placeholder)
                    .foregroundStyle(.tertiary)
                    .padding(.top, 8)
                    .padding(.leading, 7)
                    .allowsHitTesting(false)
            }
        }
        .frame(maxWidth: .infinity)
        .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 6))
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(Color.secondary.opacity(0.25))
        )
    }

    private var editorHeight: CGFloat {
        let lines = max(minLines, min(maxLines, estimatedLineCount))
        return CGFloat(lines) * lineHeight + verticalPadding
    }

    private var estimatedLineCount: Int {
        let wrapWidth = monospaced ? 86 : 74
        let logicalLines = text.split(separator: "\n", omittingEmptySubsequences: false)
        guard !logicalLines.isEmpty else { return minLines }

        return logicalLines.reduce(0) { result, line in
            result + max(1, Int(ceil(Double(line.count) / Double(wrapWidth))))
        }
    }
}

struct MetricTile: View {
    var title: String
    var value: String
    var systemImage: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.title3)
                .frame(width: 26)
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 4) {
                Text(value)
                    .font(.title2)
                    .fontWeight(.semibold)
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
    }
}

struct TimeFilterBar: View {
    @Binding var preset: TimeFilterPreset
    @Binding var startDate: Date
    @Binding var endDate: Date
    var resultCount: Int
    var totalCount: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                Picker("时间范围", selection: $preset) {
                    ForEach(TimeFilterPreset.allCases) { preset in
                        Text(preset.label).tag(preset)
                    }
                }
                .pickerStyle(.segmented)

                Spacer()

                Text("\(resultCount)/\(totalCount)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if preset == .custom {
                HStack(spacing: 10) {
                    DatePicker("开始", selection: $startDate, displayedComponents: .date)
                    DatePicker("结束", selection: $endDate, displayedComponents: .date)
                    Spacer()
                    Text("包含结束日当天")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}
