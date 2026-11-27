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

    private let focusOptions: [(label: String, minutes: Int)] = [
        ("关闭", 0),
        ("25 分钟（番茄）", 25),
        ("45 分钟", 45),
        ("60 分钟", 60)
    ]

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("设置与数据备份")
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                    Text("快捷键 · 防误计 · 倒计时 · 导入导出")
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
                VStack(alignment: .leading, spacing: 18) {
                    generalSection
                    timerSection
                    countdownSection
                    backupSection
                }
                .padding(22)
            }
        }
        .frame(width: 540, height: 610)
        .background(Color(nsColor: .windowBackgroundColor))
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
        settingsCard(title: "计时保护与专注提醒", icon: "bell.badge") {
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
                    .frame(width: 150)
                }
            }

            Divider().opacity(0.5)

            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("连续专注休息提醒")
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                    Text("达到设定分钟数时轻声提醒休息，不打断已计时间")
                        .font(.system(size: 11, design: .rounded))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Picker("", selection: $controller.focusReminderMinutes) {
                    ForEach(focusOptions, id: \.minutes) { option in
                        Text(option.label).tag(option.minutes)
                    }
                }
                .labelsHidden()
                .frame(width: 150)
            }
        }
    }

    private var countdownSection: some View {
        settingsCard(title: "首页倒计时", icon: "flag.checkered") {
            if store.countdowns.isEmpty {
                Text("添加重要节点（如考试日、答辩日），将在首页顶部显示剩余天数；也可以在日历中直接对任意未来日期添加。")
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
            showStatus("已成功恢复备份（包含全部任务、标签、目标与倒计时）")
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
