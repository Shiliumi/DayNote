import SwiftUI

struct CalendarTagEditorView: View {
    let date: Date
    let initialTags: [CalendarTag]
    let accent: Color
    let onSave: ([CalendarTag]) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var tags: [CalendarTag]
    @State private var newTitle = ""
    @State private var newColorName = "orange"

    init(date: Date, tags: [CalendarTag], accent: Color, onSave: @escaping ([CalendarTag]) -> Void) {
        self.date = date
        self.initialTags = tags
        self.accent = accent
        self.onSave = onSave
        _tags = State(initialValue: tags)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 4) {
                Text("自定义标签")
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                Text(date.formatted(.dateTime.year().month().day().weekday(.wide)))
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
            }

            if tags.isEmpty {
                Text("还没有标签，可以用来标记考试、复盘、休息或任何重要事项。")
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                VStack(spacing: 10) {
                    ForEach($tags) { $tag in
                        HStack(spacing: 10) {
                            colorPicker(selection: $tag.colorName)
                            TextField("标签名称", text: $tag.title)
                                .textFieldStyle(.roundedBorder)
                            Button(role: .destructive) {
                                tags.removeAll { $0.id == tag.id }
                            } label: {
                                Image(systemName: "trash")
                            }
                            .buttonStyle(.borderless)
                        }
                    }
                }
            }

            Divider()

            VStack(alignment: .leading, spacing: 9) {
                Text("添加标签")
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                HStack(spacing: 10) {
                    colorPicker(selection: $newColorName)
                    TextField("例如：模拟考试", text: $newTitle)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit(addTag)
                    Button("添加", action: addTag)
                        .disabled(newTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }

            HStack {
                Button("取消") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button("保存") {
                    onSave(tags)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .tint(accent)
            }
        }
        .padding(24)
        .frame(width: 440)
    }

    private func colorPicker(selection: Binding<String>) -> some View {
        Menu {
            ForEach(CalendarTagPalette.names, id: \.self) { name in
                Button {
                    selection.wrappedValue = name
                } label: {
                    Label(colorTitle(name), systemImage: selection.wrappedValue == name ? "checkmark.circle.fill" : "circle.fill")
                }
            }
        } label: {
            Circle()
                .fill(CalendarTagPalette.color(named: selection.wrappedValue))
                .frame(width: 20, height: 20)
                .overlay(Circle().stroke(Color.white, lineWidth: 2))
                .shadow(color: .black.opacity(0.12), radius: 2, y: 1)
        }
        .menuStyle(.borderlessButton)
        .frame(width: 28)
    }

    private func addTag() {
        let cleaned = newTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return }
        tags.append(CalendarTag(title: cleaned, colorName: newColorName))
        newTitle = ""
    }

    private func colorTitle(_ name: String) -> String {
        switch name {
        case "blue": return "蓝色"
        case "green": return "绿色"
        case "purple": return "紫色"
        case "pink": return "粉色"
        case "gray": return "灰色"
        default: return "橙色"
        }
    }
}
