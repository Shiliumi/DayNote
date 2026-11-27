import AppKit
import SwiftUI

struct ContentView: View {
    @ObservedObject var store: TaskStore
    @ObservedObject var controller: AppController
    @AppStorage("daynote.pin-window") private var isPinned = true
    @AppStorage("daynote.desktop-mode") private var isDesktopMode = false
    @State private var selectedDate = Date()
    @State private var observedTodayKey = TaskStore.dayKey(for: Date())
    @State private var newTaskTitle = ""
    @State private var newTaskIsRecurring = true
    @State private var showingResetAlert = false
    @State private var showingCalendar = false
    @State private var showingStatistics = false
    @State private var showingSettings = false
    @State private var showingGoalEditor = false
    @State private var editingRequest: TaskEditRequest?
    @State private var draggingTaskID: UUID?
    @FocusState private var isAddingTask: Bool

    private let accent = Color(red: 0.96, green: 0.43, blue: 0.27)
    private let calendar = Calendar.autoupdatingCurrent

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            Group {
                if controller.isMiniMode {
                    miniCapsule(at: context.date)
                } else {
                    panel(at: context.date)
                }
            }
            .onChange(of: TaskStore.dayKey(for: context.date)) {
                handleDayChange(at: context.date)
            }
            .onChange(of: Int(context.date.timeIntervalSince1970)) {
                controller.evaluateFocusReminder(at: context.date)
            }
        }
        .frame(
            minWidth: controller.isMiniMode ? 280 : 340,
            idealWidth: controller.isMiniMode ? 330 : 370,
            maxWidth: controller.isMiniMode ? 420 : .infinity,
            minHeight: controller.isMiniMode ? 54 : 460,
            idealHeight: controller.isMiniMode ? 58 : 560,
            maxHeight: controller.isMiniMode ? 68 : .infinity
        )
        .background(
            WindowConfigurator(
                controller: controller,
                isPinned: isPinned,
                isDesktopMode: isDesktopMode,
                isMiniMode: controller.isMiniMode
            )
            .frame(width: 0, height: 0)
        )
        .alert("重新开始这一天？", isPresented: $showingResetAlert) {
            Button("取消", role: .cancel) { }
            Button("清零", role: .destructive) {
                store.resetDay(selectedDate)
            }
        } message: {
            Text("所有勾选状态和计时都会清零，任务名称会保留。")
        }
        .alert(item: $controller.sleepPrompt) { prompt in
            Alert(
                title: Text("检测到离开 / 休眠"),
                message: Text("期间约 \(formatAwayDuration(prompt.awaySeconds)) 被计入了「\(prompt.taskTitle)」，需要扣除这段挂机时长吗？"),
                primaryButton: .default(Text("扣除并暂停")) {
                    controller.resolveSleepPrompt(deduct: true, pause: true)
                },
                secondaryButton: .cancel(Text("保留（一直在学）")) {
                    controller.resolveSleepPrompt(deduct: false, pause: false)
                }
            )
        }
        .sheet(isPresented: $showingCalendar) {
            CalendarHistoryView(store: store, selectedDate: $selectedDate, accent: accent)
        }
        .sheet(isPresented: $showingStatistics) {
            MonthlyStatisticsView(store: store, initialMonth: selectedDate, accent: accent)
        }
        .sheet(isPresented: $showingSettings) {
            SettingsView(store: store, controller: controller, accent: accent)
        }
        .sheet(item: $editingRequest) { request in
            TaskEditView(request: request, accent: accent) { title, completed, seconds, isRecurring in
                store.updateTask(
                    id: request.task.id,
                    on: request.date,
                    title: title,
                    isCompleted: completed,
                    elapsedSeconds: seconds,
                    isRecurring: isRecurring
                )
            }
        }
    }

    // MARK: - Mini Floating Capsule

    private func miniCapsule(at now: Date) -> some View {
        let active = store.activeTask
        let elapsed = active != nil ? store.activeElapsed(at: now) : store.totalElapsed(on: now, at: now)
        let goalMin = store.goalMinutes(on: now)
        let percent = StudyGoal.percent(elapsedSeconds: store.totalElapsed(on: now, at: now), goalMinutes: goalMin)

        return HStack(spacing: 10) {
            Circle()
                .fill(active != nil ? accent : Color.secondary.opacity(0.4))
                .frame(width: 8, height: 8)

            VStack(alignment: .leading, spacing: 1) {
                Text(active?.title ?? "今日便笺 · 达成 \(percent)%")
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundStyle(Color(red: 0.22, green: 0.18, blue: 0.14))
                    .lineLimit(1)
                if active != nil {
                    Text("今日总计 \(Self.formatDuration(store.totalElapsed(on: now, at: now))) · \(percent)%")
                        .font(.system(size: 9, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }

            Spacer(minLength: 4)

            Text(Self.formatDuration(elapsed))
                .font(.system(size: 13, weight: .bold, design: .monospaced))
                .foregroundStyle(active != nil ? accent : Color.secondary)
                .monospacedDigit()

            Button {
                store.toggleQuickTimer(at: now)
            } label: {
                Image(systemName: active != nil ? "pause.fill" : "play.fill")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(active != nil ? .white : accent)
                    .frame(width: 26, height: 26)
                    .background(Circle().fill(active != nil ? accent : accent.opacity(0.14)))
            }
            .buttonStyle(.plain)
            .help(active != nil ? "暂停计时 (⌥⇧Space)" : "开始计时 (⌥⇧Space)")

            Button {
                controller.isMiniMode = false
            } label: {
                Image(systemName: "arrow.up.left.and.arrow.down.right")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 24, height: 24)
                    .background(Circle().fill(Color.white.opacity(0.55)))
            }
            .buttonStyle(.plain)
            .help("展开完整便笺")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .background(
            LinearGradient(
                colors: [
                    Color(red: 1.0, green: 0.98, blue: 0.91),
                    Color(red: 1.0, green: 0.95, blue: 0.88)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .clipShape(Capsule())
        .overlay(
            Capsule()
                .stroke(active != nil ? accent.opacity(0.4) : Color.white.opacity(0.8), lineWidth: 1)
        )
        .padding(4)
    }

    // MARK: - Main Sticky Note Panel

    private func panel(at now: Date) -> some View {
        let dayTasks = store.tasks(on: selectedDate)

        return VStack(spacing: 0) {
            header(at: now)

            dailyGoalBar

            if let nearest = store.upcomingCountdowns(from: now).first {
                countdownBanner(event: nearest.event, daysRemaining: nearest.daysRemaining)
            }

            if let reminder = controller.focusReminderMessage {
                focusReminderBanner(reminder)
            }

            if !calendar.isDate(selectedDate, inSameDayAs: now) {
                historyBanner(at: now)
            }

            Divider().overlay(Color.black.opacity(0.06))

            taskList(dayTasks, at: now)

            Divider().overlay(Color.black.opacity(0.06))

            addTaskBar
            summary(dayTasks, at: now)
        }
        .background(
            LinearGradient(
                colors: [
                    Color(red: 1.0, green: 0.98, blue: 0.91),
                    Color(red: 1.0, green: 0.95, blue: 0.88)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.white.opacity(0.75), lineWidth: 1)
        )
        .padding(8)
    }

    private func header(at now: Date) -> some View {
        let isToday = calendar.isDate(selectedDate, inSameDayAs: now)
        let isFuture = selectedDate > calendar.startOfDay(for: now) && !isToday

        return HStack(alignment: .top, spacing: 5) {
            VStack(alignment: .leading, spacing: 4) {
                Text(isToday ? "今日便笺" : (isFuture ? "计划便笺" : "历史便笺"))
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .foregroundStyle(Color(red: 0.22, green: 0.18, blue: 0.14))

                Text(selectedDate.formatted(.dateTime.year().month(.wide).day().weekday(.wide)))
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 4)

            headerButton("calendar", help: "日历与历史") {
                showingCalendar = true
            }

            headerButton("chart.bar.xaxis", help: "周/月统计") {
                showingStatistics = true
            }

            headerButton("rectangle.compress.vertical", help: "迷你悬浮条") {
                controller.isMiniMode = true
            }

            headerButton(isDesktopMode ? "desktopcomputer.and.macbook" : "desktopcomputer", isActive: isDesktopMode, help: isDesktopMode ? "退出桌面模式" : "固定在系统桌面") {
                isDesktopMode.toggle()
            }

            headerButton(isPinned ? "pin.fill" : "pin", isActive: isPinned && !isDesktopMode, help: isPinned ? "取消置顶" : "保持置顶") {
                if isDesktopMode { isDesktopMode = false }
                isPinned.toggle()
            }

            headerButton("gearshape", help: "设置、快捷键与数据备份") {
                showingSettings = true
            }
        }
        .padding(.horizontal, 18)
        .padding(.top, 18)
        .padding(.bottom, 14)
    }

    private func headerButton(
        _ systemName: String,
        isActive: Bool = false,
        help: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .frame(width: 24, height: 24)
        }
        .buttonStyle(HeaderButtonStyle(isActive: isActive, accent: accent))
        .help(help)
    }

    private func countdownBanner(event: CountdownEvent, daysRemaining: Int) -> some View {
        let color = CalendarTagPalette.color(named: event.colorName)
        return Button {
            showingSettings = true
        } label: {
            HStack(spacing: 7) {
                Image(systemName: "flag.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(color)
                Text(event.title)
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundStyle(Color(red: 0.25, green: 0.20, blue: 0.16))
                    .lineLimit(1)
                Spacer()
                Text(daysRemaining == 0 ? "就是今天!" : "还有 \(daysRemaining) 天")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundStyle(color)
                    .monospacedDigit()
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 7)
            .background(color.opacity(0.08))
        }
        .buttonStyle(.plain)
        .help("点击管理首页倒计时")
    }

    private func focusReminderBanner(_ message: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "bell.badge.fill")
                .foregroundStyle(accent)
            Text(message)
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .lineLimit(2)
            Spacer(minLength: 4)
            Button("休息") {
                controller.pauseForBreak()
            }
            .buttonStyle(.borderedProminent)
            .tint(accent)
            .controlSize(.mini)
            Button("继续") {
                controller.dismissFocusReminder()
            }
            .buttonStyle(.bordered)
            .controlSize(.mini)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(accent.opacity(0.12))
    }

    private func historyBanner(at now: Date) -> some View {
        let isFuture = selectedDate > calendar.startOfDay(for: now)
        return HStack(spacing: 8) {
            Image(systemName: isFuture ? "calendar.badge.plus" : "clock.arrow.circlepath")
            Text(isFuture ? "未来日期 · 可提前安排任务与目标" : "历史日期 · 可补打卡或双击/右键编辑")
                .lineLimit(1)
            Spacer()
            Button("回到今天") {
                selectedDate = Date()
            }
            .buttonStyle(.plain)
            .foregroundStyle(accent)
        }
        .font(.system(size: 11, weight: .semibold, design: .rounded))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 18)
        .padding(.vertical, 9)
        .background(accent.opacity(0.07))
    }

    private var dailyGoalBar: some View {
        let goalMinutes = store.goalMinutes(on: selectedDate)

        return HStack(spacing: 10) {
            Image(systemName: "target")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(accent)

            Text(calendar.isDateInToday(selectedDate) ? "今日目标" : "当天目标")
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(.secondary)

            Spacer()

            Button {
                store.setGoalMinutes(goalMinutes - 30, on: selectedDate)
            } label: {
                Image(systemName: "minus")
                    .frame(width: 22, height: 22)
            }
            .buttonStyle(.plain)
            .background(Circle().fill(Color.black.opacity(0.06)))
            .disabled(goalMinutes <= 30)
            .help("减少半小时")

            Button {
                showingGoalEditor.toggle()
            } label: {
                HStack(spacing: 5) {
                    Text(StudyGoal.durationLabel(minutes: goalMinutes))
                        .monospacedDigit()
                    Image(systemName: "chevron.down")
                        .font(.system(size: 8, weight: .bold))
                }
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundStyle(accent)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(Capsule().fill(accent.opacity(0.11)))
            }
            .buttonStyle(.plain)
            .popover(isPresented: $showingGoalEditor, arrowEdge: .top) {
                StudyGoalEditor(
                    goalMinutes: Binding(
                        get: { store.goalMinutes(on: selectedDate) },
                        set: { store.setGoalMinutes($0, on: selectedDate) }
                    ),
                    date: selectedDate,
                    accent: accent
                )
            }
            .help("选择当天学习目标")

            Button {
                store.setGoalMinutes(goalMinutes + 30, on: selectedDate)
            } label: {
                Image(systemName: "plus")
                    .frame(width: 22, height: 22)
            }
            .buttonStyle(.plain)
            .background(Circle().fill(Color.black.opacity(0.06)))
            .disabled(goalMinutes >= 24 * 60)
            .help("增加半小时")
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 9)
        .background(Color.white.opacity(0.28))
    }

    @ViewBuilder
    private func taskList(_ dayTasks: [DailyTask], at now: Date) -> some View {
        if dayTasks.isEmpty {
            VStack(spacing: 12) {
                Image(systemName: "checklist")
                    .font(.system(size: 32, weight: .light))
                    .foregroundStyle(accent.opacity(0.75))
                Text(calendar.isDate(selectedDate, inSameDayAs: now) ? "写下今天想完成的事" : "这一天还没有记录")
                    .font(.system(size: 14, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
            .onTapGesture { isAddingTask = true }
        } else {
            ScrollView {
                LazyVStack(spacing: 8) {
                    ForEach(dayTasks) { task in
                        TaskRow(
                            task: task,
                            elapsed: store.elapsed(for: task, on: selectedDate, at: now),
                            isRunning: store.activeDayKey == TaskStore.dayKey(for: selectedDate) && store.activeTaskID == task.id,
                            canStartTimer: calendar.isDate(selectedDate, inSameDayAs: now),
                            accent: accent,
                            onToggleCompletion: {
                                store.toggleCompletion(for: task.id, on: selectedDate, at: now)
                            },
                            onToggleTimer: {
                                store.toggleTimer(for: task.id, on: selectedDate, at: now)
                            },
                            onRename: { newTitle in
                                store.renameTask(id: task.id, on: selectedDate, title: newTitle)
                            },
                            onAdjustMinutes: { minutes in
                                store.adjustTaskDuration(id: task.id, on: selectedDate, deltaSeconds: TimeInterval(minutes * 60), at: now)
                            },
                            onToggleRecurring: {
                                store.toggleRecurring(for: task.id, on: selectedDate)
                            },
                            onEdit: {
                                editingRequest = TaskEditRequest(task: task, date: selectedDate)
                            },
                            onDelete: {
                                store.deleteTask(id: task.id, on: selectedDate, at: now)
                            }
                        )
                        .draggable(task.id.uuidString) {
                            Text(task.title)
                                .font(.system(size: 12, weight: .semibold, design: .rounded))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(RoundedRectangle(cornerRadius: 8).fill(Color.white.opacity(0.95)))
                                .onAppear { draggingTaskID = task.id }
                        }
                        .dropDestination(for: String.self) { items, _ in
                            guard let raw = items.first, let dragged = UUID(uuidString: raw) else { return false }
                            withAnimation(.easeInOut(duration: 0.18)) {
                                store.moveTask(draggedID: dragged, targetID: task.id, on: selectedDate)
                            }
                            draggingTaskID = nil
                            return true
                        }
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
            }
            .scrollIndicators(.hidden)
            .frame(maxHeight: .infinity)
        }
    }

    private var addTaskBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "plus.circle.fill")
                .font(.system(size: 18))
                .foregroundStyle(accent)

            TextField(calendar.isDateInToday(selectedDate) ? "添加任务，按回车保存" : "为这一天添加任务", text: $newTaskTitle)
                .textFieldStyle(.plain)
                .font(.system(size: 14, weight: .medium, design: .rounded))
                .focused($isAddingTask)
                .onSubmit(addTask)

            Button {
                newTaskIsRecurring.toggle()
            } label: {
                Text(newTaskIsRecurring ? "每日" : "仅今天")
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .foregroundStyle(newTaskIsRecurring ? accent : Color.blue)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(Capsule().fill((newTaskIsRecurring ? accent : Color.blue).opacity(0.12)))
            }
            .buttonStyle(.plain)
            .help(newTaskIsRecurring ? "每日固定任务：次日自动沿用（点击切换为仅今天）" : "仅今天临时任务：次日不会自动复制（点击切换为每日固定）")

            if !newTaskTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Button(action: addTask) {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 18))
                        .foregroundStyle(accent)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color.white.opacity(0.38))
    }

    private func summary(_ dayTasks: [DailyTask], at now: Date) -> some View {
        let count = dayTasks.count
        let completed = dayTasks.lazy.filter(\.isCompleted).count
        let elapsed = store.totalElapsed(on: selectedDate, at: now)
        let goalMinutes = store.goalMinutes(on: selectedDate)
        let progress = StudyGoal.rate(elapsedSeconds: elapsed, goalMinutes: goalMinutes)
        let percent = StudyGoal.percent(elapsedSeconds: elapsed, goalMinutes: goalMinutes)

        return VStack(spacing: 9) {
            HStack {
                Label("达成 \(percent)%", systemImage: "chart.bar.fill")

                Spacer()
                Label("打卡 \(completed)/\(count)", systemImage: "checkmark.circle")
                Spacer()
                Label("\(Self.formatDuration(elapsed))/\(StudyGoal.compactDurationLabel(minutes: goalMinutes))", systemImage: "timer")
            }
            .font(.system(size: 11, weight: .semibold, design: .rounded))
            .foregroundStyle(Color(red: 0.33, green: 0.27, blue: 0.21).opacity(0.8))

            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.black.opacity(0.08))
                    Capsule()
                        .fill(accent)
                        .frame(width: geometry.size.width * progress)
                }
            }
            .frame(height: 6)
            .animation(.easeOut(duration: 0.25), value: progress)
        }
        .padding(.horizontal, 18)
        .padding(.top, 12)
        .padding(.bottom, 16)
        .contextMenu {
            Button("清零这一天", role: .destructive) { showingResetAlert = true }
        }
    }

    private func addTask() {
        store.addTask(title: newTaskTitle, on: selectedDate, isRecurring: newTaskIsRecurring)
        newTaskTitle = ""
        isAddingTask = true
    }

    private func handleDayChange(at now: Date) {
        let newKey = TaskStore.dayKey(for: now)
        if TaskStore.dayKey(for: selectedDate) == observedTodayKey {
            selectedDate = now
        }
        observedTodayKey = newKey
        store.prepareForCurrentDay(at: now)
    }

    private func formatAwayDuration(_ seconds: TimeInterval) -> String {
        let totalMinutes = max(1, Int((seconds / 60).rounded()))
        let hours = totalMinutes / 60
        let mins = totalMinutes % 60
        if hours > 0 { return "\(hours) 小时 \(mins) 分钟" }
        return "\(mins) 分钟"
    }

    static func formatDuration(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds))
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let remainingSeconds = total % 60

        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, remainingSeconds)
        }
        return String(format: "%02d:%02d", minutes, remainingSeconds)
    }
}

struct TaskEditRequest: Identifiable {
    let task: DailyTask
    let date: Date
    var id: UUID { task.id }
}

private struct TaskEditView: View {
    let request: TaskEditRequest
    let accent: Color
    let onSave: (String, Bool, TimeInterval, Bool) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var title: String
    @State private var isCompleted: Bool
    @State private var isRecurring: Bool
    @State private var totalMinutes: Int
    @State private var hoursText: String
    @State private var minutesText: String

    init(request: TaskEditRequest, accent: Color, onSave: @escaping (String, Bool, TimeInterval, Bool) -> Void) {
        self.request = request
        self.accent = accent
        self.onSave = onSave
        let mins = max(0, Int(request.task.elapsedSeconds) / 60)
        _title = State(initialValue: request.task.title)
        _isCompleted = State(initialValue: request.task.isCompleted)
        _isRecurring = State(initialValue: request.task.isRecurring)
        _totalMinutes = State(initialValue: mins)
        _hoursText = State(initialValue: "\(mins / 60)")
        _minutesText = State(initialValue: "\(mins % 60)")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 4) {
                Text("编辑任务")
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                Text(request.date.formatted(.dateTime.year().month().day().weekday(.wide)))
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
            }

            TextField("任务名称", text: $title)
                .textFieldStyle(.roundedBorder)

            HStack(spacing: 20) {
                Toggle("已完成打卡", isOn: $isCompleted)
                Toggle("每日自动沿用", isOn: $isRecurring)
            }

            VStack(alignment: .leading, spacing: 10) {
                Text("记录时长（可直接输入数字或快捷微调）")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)

                HStack(spacing: 10) {
                    TextField("0", text: $hoursText)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 60)
                        .onChange(of: hoursText) { syncFromTextFields() }
                    Text("小时")
                    TextField("0", text: $minutesText)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 60)
                        .onChange(of: minutesText) { syncFromTextFields() }
                    Text("分钟")
                    Spacer()
                }

                HStack(spacing: 6) {
                    quickButton("-15分", delta: -15)
                    quickButton("-5分", delta: -5)
                    quickButton("+5分", delta: 5)
                    quickButton("+15分", delta: 15)
                    quickButton("+30分", delta: 30)
                }
            }

            HStack {
                Button("取消") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button("保存") {
                    syncFromTextFields()
                    onSave(title, isCompleted, TimeInterval(totalMinutes * 60), isRecurring)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .tint(accent)
                .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(24)
        .frame(width: 390)
    }

    private func quickButton(_ label: String, delta: Int) -> some View {
        Button(label) {
            totalMinutes = max(0, min(99 * 60 + 59, totalMinutes + delta))
            hoursText = "\(totalMinutes / 60)"
            minutesText = "\(totalMinutes % 60)"
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
    }

    private func syncFromTextFields() {
        let h = max(0, min(99, Int(hoursText.filter(\.isNumber)) ?? 0))
        let m = max(0, min(5999, Int(minutesText.filter(\.isNumber)) ?? 0))
        totalMinutes = h * 60 + m
    }
}

private struct TaskRow: View {
    let task: DailyTask
    let elapsed: TimeInterval
    let isRunning: Bool
    let canStartTimer: Bool
    let accent: Color
    let onToggleCompletion: () -> Void
    let onToggleTimer: () -> Void
    let onRename: (String) -> Void
    let onAdjustMinutes: (Int) -> Void
    let onToggleRecurring: () -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void

    @State private var isHovering = false
    @State private var isInlineEditing = false
    @State private var draftTitle = ""
    @FocusState private var inlineFocused: Bool

    var body: some View {
        HStack(spacing: 10) {
            Button(action: onToggleCompletion) {
                Image(systemName: task.isCompleted ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 20, weight: .medium))
                    .foregroundStyle(task.isCompleted ? accent : Color.secondary.opacity(0.55))
            }
            .buttonStyle(.plain)

            if isInlineEditing {
                TextField("任务名称", text: $draftTitle)
                    .textFieldStyle(.plain)
                    .font(.system(size: 14, weight: .medium, design: .rounded))
                    .focused($inlineFocused)
                    .onSubmit(commitInlineEdit)
                    .onExitCommand { isInlineEditing = false }
                    .onChange(of: inlineFocused) {
                        if !inlineFocused && isInlineEditing {
                            commitInlineEdit()
                        }
                    }
            } else {
                VStack(alignment: .leading, spacing: 2) {
                    Text(task.title)
                        .font(.system(size: 14, weight: .medium, design: .rounded))
                        .foregroundStyle(task.isCompleted ? Color.secondary : Color.primary.opacity(0.86))
                        .strikethrough(task.isCompleted, color: .secondary)
                        .lineLimit(2)

                    if !task.isRecurring {
                        Text("仅今天")
                            .font(.system(size: 9, weight: .semibold, design: .rounded))
                            .foregroundStyle(.blue)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(Capsule().fill(Color.blue.opacity(0.10)))
                    }
                }
                .contentShape(Rectangle())
                .onTapGesture(count: 2) {
                    draftTitle = task.title
                    isInlineEditing = true
                    inlineFocused = true
                }
                .help("双击修改名称 · 拖拽可调整顺序")
            }

            Spacer(minLength: 4)

            if isHovering && !isInlineEditing {
                Button(action: onEdit) {
                    Image(systemName: "pencil")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 20, height: 20)
                }
                .buttonStyle(.plain)
                .help("编辑任务与时长")
            }

            Text(ContentView.formatDuration(elapsed))
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundStyle(isRunning ? accent : Color.secondary)
                .monospacedDigit()

            if canStartTimer {
                Button(action: onToggleTimer) {
                    Image(systemName: isRunning ? "pause.fill" : "play.fill")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(task.isCompleted ? Color.secondary.opacity(0.4) : (isRunning ? .white : accent))
                        .frame(width: 26, height: 26)
                        .background(Circle().fill(isRunning ? accent : accent.opacity(task.isCompleted ? 0.06 : 0.12)))
                }
                .buttonStyle(.plain)
                .disabled(task.isCompleted)
            } else {
                Button(action: onEdit) {
                    Image(systemName: "pencil")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(accent)
                        .frame(width: 26, height: 26)
                        .background(Circle().fill(accent.opacity(0.1)))
                }
                .buttonStyle(.plain)
                .help("编辑任务与时长")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.white.opacity(isRunning ? 0.8 : 0.56))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(isRunning ? accent.opacity(0.28) : Color.white.opacity(0.5), lineWidth: 1)
        )
        .onHover { isHovering = $0 }
        .contextMenu {
            Button("编辑任务与时长", action: onEdit)
            Button("重命名") {
                draftTitle = task.title
                isInlineEditing = true
                inlineFocused = true
            }
            Divider()
            Button("时长 +15 分钟") { onAdjustMinutes(15) }
            Button("时长 -15 分钟") { onAdjustMinutes(-15) }
            Divider()
            Button(task.isRecurring ? "改为仅今天任务" : "改为每日固定任务", action: onToggleRecurring)
            Divider()
            Button("删除任务", role: .destructive, action: onDelete)
        }
    }

    private func commitInlineEdit() {
        let cleaned = draftTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        if !cleaned.isEmpty {
            onRename(cleaned)
        }
        isInlineEditing = false
    }
}

private struct HeaderButtonStyle: ButtonStyle {
    let isActive: Bool
    let accent: Color

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(isActive ? accent : Color.secondary)
            .background(Circle().fill(isActive ? accent.opacity(0.13) : Color.white.opacity(0.45)))
            .scaleEffect(configuration.isPressed ? 0.92 : 1)
    }
}

private struct WindowConfigurator: NSViewRepresentable {
    let controller: AppController
    let isPinned: Bool
    let isDesktopMode: Bool
    let isMiniMode: Bool

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async { configure(view.window, coordinator: context.coordinator) }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async { configure(nsView.window, coordinator: context.coordinator) }
    }

    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        coordinator.stopMonitoring()
    }

    private func configure(_ window: NSWindow?, coordinator: Coordinator) {
        guard let window else { return }
        controller.mainWindow = window
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = true
        window.backgroundColor = .clear
        window.isOpaque = false
        window.hasShadow = true
        window.hidesOnDeactivate = false
        window.ignoresMouseEvents = false
        window.acceptsMouseMovedEvents = true
        coordinator.startMonitoring(window: window)
        coordinator.applyMiniMode(isMiniMode, to: window)

        if isMiniMode {
            window.level = .floating
            window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        } else if isDesktopMode {
            let desktopLevel = Int(CGWindowLevelForKey(.desktopIconWindow)) + 1
            window.level = NSWindow.Level(rawValue: desktopLevel)
            window.collectionBehavior = [.canJoinAllSpaces, .stationary]
        } else {
            window.level = isPinned ? .floating : .normal
            window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        }
    }

    @MainActor
    final class Coordinator {
        private var mouseMonitor: Any?
        private var lastMiniMode: Bool?
        private var savedNormalFrame: NSRect?

        func applyMiniMode(_ isMini: Bool, to window: NSWindow) {
            if lastMiniMode == nil {
                window.setFrameAutosaveName("DayNote.MainWindow")
                lastMiniMode = isMini
                if isMini {
                    savedNormalFrame = NSRect(x: window.frame.origin.x, y: window.frame.origin.y, width: 370, height: 560)
                    let topY = window.frame.maxY
                    window.setFrame(NSRect(x: window.frame.origin.x, y: topY - 60, width: 330, height: 60), display: true, animate: false)
                }
                return
            }
            guard lastMiniMode != isMini else { return }
            lastMiniMode = isMini

            if isMini {
                savedNormalFrame = window.frame
                let topY = window.frame.maxY
                let miniFrame = NSRect(x: window.frame.origin.x, y: topY - 60, width: 330, height: 60)
                window.setFrame(miniFrame, display: true, animate: true)
            } else {
                let targetSize = savedNormalFrame?.size ?? NSSize(width: 370, height: 560)
                let topY = window.frame.maxY
                let normalFrame = NSRect(
                    x: window.frame.origin.x,
                    y: max(40, topY - targetSize.height),
                    width: max(340, targetSize.width),
                    height: max(460, targetSize.height)
                )
                window.setFrame(normalFrame, display: true, animate: true)
            }
        }

        func startMonitoring(window: NSWindow) {
            guard mouseMonitor == nil else { return }
            mouseMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak window] event in
                guard let window, event.window === window else { return event }

                if window.level.rawValue < NSWindow.Level.normal.rawValue {
                    NSApp.activate(ignoringOtherApps: true)
                    window.makeKey()
                }
                return event
            }
        }

        func stopMonitoring() {
            guard let mouseMonitor else { return }
            NSEvent.removeMonitor(mouseMonitor)
            self.mouseMonitor = nil
        }
    }
}
