import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    @ObservedObject var store: TaskStore
    @ObservedObject var controller: AppController
    let accent: Color

    @Environment(\.dismiss) private var dismiss
    @State private var statusBanner: String?
    @State private var isErrorBanner = false
    @State private var newCountdownTitle = ""
    @State private var newCountdownDate = Calendar.autoupdatingCurrent.date(byAdding: .day, value: 30, to: Date()) ?? Date()
    @State private var newCountdownColor = "orange"
    @State private var newTemplateName = ""
    @State private var newTemplateTasksText = ""
    @State private var newCategoryName = ""
    @State private var newCategoryColor = "blue"

    private let focusOptions: [(label: String, minutes: Int)] = [
        ("关闭", 0),
        ("每 25 分钟", 25),
        ("每 45 分钟", 45),
        ("每 60 分钟", 60)
    ]

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("设置与偏好")
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                    Text("主题外观 · 番茄专注 · 任务模板 · 倒计时 · 数据备份")
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("完成") { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }
            .padding(22)

            Divider()

            if let statusBanner {
                HStack(spacing: 8) {
                    Image(systemName: isErrorBanner ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                        .foregroundStyle(isErrorBanner ? .red : .green)
                    Text(statusBanner)
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                    Spacer()
                    Button { self.statusBanner = nil } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 10, weight: .bold))
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 10)
                .background((isErrorBanner ? Color.red : Color.green).opacity(0.09))
            }

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    appearanceSection
                    categorySection
                    generalSection
                    timerSection
                    templateSection
                    countdownSection
                    backupSection
                }
                .padding(22)
            }
        }
        .frame(width: 570, height: 660)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    // MARK: - Appearance & Theme

    private var appearanceSection: some View {
        settingsCard(title: "主题外观与透明度", icon: "paintpalette.fill") {
            HStack(spacing: 10) {
                ForEach(DayNoteThemeID.allCases) { theme in
                    let p = theme.palette
                    let selected = controller.themeID == theme
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            controller.themeID = theme
                        }
                    } label: {
                        VStack(spacing: 6) {
                            ZStack {
                                RoundedRectangle(cornerRadius: 11, style: .continuous)
                                    .fill(p.swatchPreview)
                                    .frame(height: 36)
                                    .overlay(
                                        Circle()
                                            .fill(p.accent)
                                            .frame(width: 14, height: 14)
                                    )
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 11, style: .continuous)
                                            .stroke(selected ? p.accent : Color.secondary.opacity(0.22), lineWidth: selected ? 2.2 : 1)
                                    )
                            }
                            Text(theme.displayName)
                                .font(.system(size: 10.5, weight: selected ? .bold : .medium, design: .rounded))
                                .foregroundStyle(selected ? accent : .secondary)
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.plain)
                }
            }

            HStack(spacing: 12) {
                Text("窗口不透明度")
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
                Slider(value: $controller.windowOpacity, in: 0.75...1.0, step: 0.05)
                    .tint(accent)
                Text("\(Int((controller.windowOpacity * 100).rounded()))%")
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                    .frame(width: 40, alignment: .trailing)
            }
        }
    }

    // MARK: - Custom Categories

    private var categorySection: some View {
        settingsCard(title: "任务分类管理（完全自定义）", icon: "folder.badge.gearshape") {
            if store.categories.isEmpty {
                Text("还没有创建分类。你可以按科目、项目或生活领域自由新建分类，统计页会自动按分类汇总时长与占比。")
                    .font(.system(size: 11, design: .rounded))
                    .foregroundStyle(.secondary)
            } else {
                VStack(spacing: 8) {
                    ForEach(store.categories) { cat in
                        CategoryEditRow(
                            category: cat,
                            onChangeColor: { newColor in
                                store.updateCategory(id: cat.id, name: cat.name, colorName: newColor)
                            },
                            onCommitName: { newName in
                                store.updateCategory(id: cat.id, name: newName, colorName: cat.colorName)
                            },
                            onDelete: {
                                store.deleteCategory(id: cat.id)
                                showStatus("已删除分类「\(cat.name)」，原任务已保留为未分类")
                            }
                        )
                    }
                }
            }

            Divider().opacity(0.5)

            HStack(spacing: 8) {
                categoryColorMenu(currentColor: newCategoryColor) { newCategoryColor = $0 }
                TextField("新分类名称（如：专业课 / 英语 / 科研）", text: $newCategoryName)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(createCategory)
                Button("添加", action: createCategory)
                    .buttonStyle(.borderedProminent)
                    .tint(accent)
                    .disabled(newCategoryName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
    }

    private func createCategory() {
        guard let created = store.addCategory(name: newCategoryName, colorName: newCategoryColor) else { return }
        newCategoryName = ""
        showStatus("已添加分类「\(created.name)」")
    }

    private func categoryColorMenu(currentColor: String, onSelect: @escaping (String) -> Void) -> some View {
        Menu {
            ForEach(CalendarTagPalette.names, id: \.self) { name in
                Button {
                    onSelect(name)
                } label: {
                    Label(colorTitle(name), systemImage: currentColor == name ? "checkmark.circle.fill" : "circle.fill")
                }
            }
        } label: {
            Circle()
                .fill(CalendarTagPalette.color(named: currentColor))
                .frame(width: 18, height: 18)
                .overlay(Circle().stroke(Color.white, lineWidth: 1.5))
                .shadow(color: .black.opacity(0.12), radius: 1.5, y: 1)
        }
        .menuStyle(.borderlessButton)
        .frame(width: 26)
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

    private var generalSection: some View {
        settingsCard(title: "通用与快捷方式", icon: "command") {
            Toggle("开机自动启动 DayNote", isOn: Binding(
                get: { controller.isLaunchAtLoginEnabled },
                set: { controller.setLaunchAtLogin($0) }
            ))
            if let err = controller.launchAtLoginError {
                Text(err)
                    .font(.system(size: 11, design: .rounded))
                    .foregroundStyle(.red)
            }

            Toggle("启用全局快捷键（⌥Space 呼出/隐藏，⌥⇧Space 暂停/计时）", isOn: $controller.globalHotkeysEnabled)

            Toggle("迷你悬浮条模式（折叠为单行置顶计时胶囊）", isOn: $controller.isMiniMode)
        }
    }

    private var timerSection: some View {
        settingsCard(title: "番茄专注与防误计", icon: "bell.badge") {
            Toggle("启用番茄倒计时模式（到点提示并自动计入今日番茄数）", isOn: $controller.pomodoroEnabled)

            if controller.pomodoroEnabled {
                HStack {
                    Text("单轮番茄时长")
                        .font(.system(size: 12, design: .rounded))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Picker("", selection: $controller.pomodoroMinutes) {
                        Text("25 分钟").tag(25)
                        Text("45 分钟").tag(45)
                        Text("60 分钟").tag(60)
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 220)
                }
            } else {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("正向计时休息提醒")
                            .font(.system(size: 12.5, weight: .medium, design: .rounded))
                        Text("达到设定分钟数时轻声提醒休息，不中断计时")
                            .font(.system(size: 10.5, design: .rounded))
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Picker("", selection: $controller.focusReminderMinutes) {
                        ForEach(focusOptions, id: \.minutes) { option in
                            Text(option.label).tag(option.minutes)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 130)
                }
            }

            Divider().opacity(0.5)

            Toggle("休眠 / 锁屏防误计（唤醒后询问是否扣除离开时长）", isOn: $controller.sleepProtectionEnabled)

            if controller.sleepProtectionEnabled {
                HStack {
                    Text("触发询问阈值")
                        .font(.system(size: 12, design: .rounded))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Picker("", selection: $controller.sleepThresholdMinutes) {
                        Text("离开 ≥ 1 分钟").tag(1)
                        Text("离开 ≥ 3 分钟").tag(3)
                        Text("离开 ≥ 5 分钟").tag(5)
                        Text("离开 ≥ 10 分钟").tag(10)
                    }
                    .labelsHidden()
                    .frame(width: 145)
                }
            }
        }
    }

    private var templateSection: some View {
        settingsCard(title: "任务模板库", icon: "doc.on.clipboard") {
            if store.taskTemplates.isEmpty {
                Text("可以把工作日、周末或模考日的不同任务组合保存成模板，在首页底部一键套用。")
                    .font(.system(size: 11, design: .rounded))
                    .foregroundStyle(.secondary)
            } else {
                VStack(spacing: 6) {
                    ForEach(store.taskTemplates) { template in
                        HStack(spacing: 8) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(template.name)
                                    .font(.system(size: 12.5, weight: .semibold, design: .rounded))
                                Text(template.items.map(\.title).joined(separator: " · "))
                                    .font(.system(size: 10.5, design: .rounded))
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                            Spacer()
                            Button("应用到今日") {
                                store.applyTemplate(template, to: Date(), replaceExisting: false)
                                showStatus("已将模板「\(template.name)」追加到今日任务")
                            }
                            .controlSize(.small)
                            Button(role: .destructive) {
                                store.deleteTemplate(id: template.id)
                            } label: {
                                Image(systemName: "trash").font(.system(size: 11))
                            }
                            .buttonStyle(.borderless)
                        }
                    }
                }
            }

            Divider().opacity(0.5)

            HStack(spacing: 8) {
                TextField("模板名（如：周末冲刺）", text: $newTemplateName)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 145)
                TextField("任务列表（用中文或英文逗号分隔）", text: $newTemplateTasksText)
                    .textFieldStyle(.roundedBorder)
                Button("新建") {
                    let parts = newTemplateTasksText
                        .replacingOccurrences(of: "，", with: ",")
                        .split(separator: ",")
                        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                        .filter { !$0.isEmpty }
                    let items = parts.map { TaskTemplateItem(title: $0, isRecurring: true) }
                    store.addTemplate(name: newTemplateName, items: items)
                    newTemplateName = ""
                    newTemplateTasksText = ""
                    showStatus("已创建任务模板")
                }
                .buttonStyle(.borderedProminent)
                .tint(accent)
                .disabled(
                    newTemplateName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
                    newTemplateTasksText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                )
            }
        }
    }

    private var countdownSection: some View {
        settingsCard(title: "首页倒计时", icon: "flag.checkered") {
            if store.countdowns.isEmpty {
                Text("添加重要节点（如考试日、答辩日），将在首页卡片中显示剩余天数；也可以在日历中直接添加。")
                    .font(.system(size: 11, design: .rounded))
                    .foregroundStyle(.secondary)
            } else {
                VStack(spacing: 6) {
                    ForEach(store.countdowns) { event in
                        HStack(spacing: 8) {
                            Circle()
                                .fill(CalendarTagPalette.color(named: event.colorName))
                                .frame(width: 8, height: 8)
                            Text(event.title)
                                .font(.system(size: 12, weight: .semibold, design: .rounded))
                            Text(event.targetDayKey)
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundStyle(.secondary)
                            Spacer()
                            if let days = store.daysRemaining(for: event) {
                                Text(days > 0 ? "还剩 \(days) 天" : (days == 0 ? "就是今天" : "已过 \(-days) 天"))
                                    .font(.system(size: 11, weight: .bold, design: .rounded))
                                    .foregroundStyle(days >= 0 ? accent : .secondary)
                            }
                            Button(role: .destructive) {
                                store.deleteCountdown(id: event.id)
                            } label: {
                                Image(systemName: "trash")
                                    .font(.system(size: 11))
                            }
                            .buttonStyle(.borderless)
                        }
                    }
                }
            }

            Divider().opacity(0.5)

            HStack(spacing: 8) {
                TextField("目标名称（如：考研初试）", text: $newCountdownTitle)
                    .textFieldStyle(.roundedBorder)
                DatePicker("", selection: $newCountdownDate, displayedComponents: .date)
                    .labelsHidden()
                    .frame(width: 115)
                Button("添加") {
                    store.addCountdown(title: newCountdownTitle, targetDate: newCountdownDate, colorName: newCountdownColor)
                    newCountdownTitle = ""
                }
                .buttonStyle(.borderedProminent)
                .tint(accent)
                .disabled(newCountdownTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
    }

    private var backupSection: some View {
        settingsCard(title: "数据备份与导入导出", icon: "externaldrive.badge.timemachine") {
            HStack(spacing: 10) {
                Button {
                    exportJSON()
                } label: {
                    Label("导出 JSON 备份", systemImage: "square.and.arrow.up")
                }
                .buttonStyle(.borderedProminent)
                .tint(accent)

                Button {
                    exportCSV()
                } label: {
                    Label("导出 CSV 表格", systemImage: "tablecells")
                }
                .buttonStyle(.bordered)

                Spacer()

                Button {
                    importJSON()
                } label: {
                    Label("从备份恢复", systemImage: "square.and.arrow.down")
                }
                .buttonStyle(.bordered)
            }

            Divider().opacity(0.5)

            VStack(alignment: .leading, spacing: 6) {
                Text("自动备份目录（可选，推荐设为 iCloud Drive 或常用文档目录）")
                    .font(.system(size: 12, weight: .medium, design: .rounded))

                HStack(spacing: 8) {
                    Text(store.autoBackupDirectoryPath.isEmpty ? "未开启自动备份" : store.autoBackupDirectoryPath)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(store.autoBackupDirectoryPath.isEmpty ? .tertiary : .secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer()
                    Button("选择文件夹") {
                        chooseAutoBackupFolder()
                    }
                    .controlSize(.small)
                    if !store.autoBackupDirectoryPath.isEmpty {
                        Button("立即备份") {
                            store.performAutoBackupIfConfigured(force: true)
                            showStatus("已写入 DayNote-AutoBackup.json")
                        }
                        .controlSize(.small)
                        Button("关闭") {
                            store.autoBackupDirectoryPath = ""
                            showStatus("已关闭自动备份")
                        }
                        .controlSize(.small)
                    }
                }
            }
        }
    }

    private func settingsCard<Content: View>(title: String, icon: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 11) {
            Label(title, systemImage: icon)
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .foregroundStyle(accent)
            content()
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.secondary.opacity(0.06)))
    }

    private func showStatus(_ message: String, isError: Bool = false) {
        statusBanner = message
        isErrorBanner = isError
    }

    private func exportJSON() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "DayNote-Backup-\(TaskStore.dayKey(for: Date())).json"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let data = try store.exportJSONData()
            try data.write(to: url, options: .atomic)
            showStatus("已导出 JSON 备份至 \(url.lastPathComponent)")
        } catch {
            showStatus("导出失败：\(error.localizedDescription)", isError: true)
        }
    }

    private func exportCSV() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.commaSeparatedText]
        panel.nameFieldStringValue = "DayNote-Records-\(TaskStore.dayKey(for: Date())).csv"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try store.exportCSVString().write(to: url, atomically: true, encoding: .utf8)
            showStatus("已导出 CSV 表格至 \(url.lastPathComponent)")
        } catch {
            showStatus("导出 CSV 失败：\(error.localizedDescription)", isError: true)
        }
    }

    private func importJSON() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let data = try Data(contentsOf: url)
            try store.importBackup(from: data)
            showStatus("已成功恢复备份（包含任务、随记、模板、标签、目标与倒计时）")
        } catch {
            showStatus("导入失败，请确认文件是 DayNote 导出的 JSON 备份：\(error.localizedDescription)", isError: true)
        }
    }

    private func chooseAutoBackupFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.prompt = "选择自动备份目录"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        store.autoBackupDirectoryPath = url.path
        store.performAutoBackupIfConfigured(force: true)
        showStatus("已开启自动备份，每次变更会自动同步至 DayNote-AutoBackup.json")
    }
}

private struct CategoryEditRow: View {
    let category: TaskCategory
    let onChangeColor: (String) -> Void
    let onCommitName: (String) -> Void
    let onDelete: () -> Void

    @State private var draftName: String
    @FocusState private var isFocused: Bool

    init(
        category: TaskCategory,
        onChangeColor: @escaping (String) -> Void,
        onCommitName: @escaping (String) -> Void,
        onDelete: @escaping () -> Void
    ) {
        self.category = category
        self.onChangeColor = onChangeColor
        self.onCommitName = onCommitName
        self.onDelete = onDelete
        _draftName = State(initialValue: category.name)
    }

    var body: some View {
        HStack(spacing: 8) {
            Menu {
                ForEach(CalendarTagPalette.names, id: \.self) { name in
                    Button {
                        onChangeColor(name)
                    } label: {
                        Label(colorTitle(name), systemImage: category.colorName == name ? "checkmark.circle.fill" : "circle.fill")
                    }
                }
            } label: {
                Circle()
                    .fill(CalendarTagPalette.color(named: category.colorName))
                    .frame(width: 18, height: 18)
                    .overlay(Circle().stroke(Color.white, lineWidth: 1.5))
                    .shadow(color: .black.opacity(0.12), radius: 1.5, y: 1)
            }
            .menuStyle(.borderlessButton)
            .frame(width: 26)

            TextField("分类名称", text: $draftName)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 12, design: .rounded))
                .focused($isFocused)
                .onSubmit(commit)
                .onChange(of: isFocused) {
                    if !isFocused { commit() }
                }
                .onChange(of: category.name) {
                    if !isFocused && draftName != category.name {
                        draftName = category.name
                    }
                }

            Button(role: .destructive, action: onDelete) {
                Image(systemName: "trash").font(.system(size: 11))
            }
            .buttonStyle(.borderless)
            .help("删除分类（不会删除任务）")
        }
    }

    private func commit() {
        let cleaned = draftName.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleaned.isEmpty {
            draftName = category.name
        } else if cleaned != category.name {
            onCommitName(cleaned)
        }
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
