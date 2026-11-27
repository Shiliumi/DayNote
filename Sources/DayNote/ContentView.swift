import AppKit
import SwiftUI

struct ContentView: View {
    @ObservedObject var store: TaskStore
    @AppStorage("daynote.pin-window") private var isPinned = true
    @AppStorage("daynote.desktop-mode") private var isDesktopMode = false
    @State private var selectedDate = Date()
    @State private var observedTodayKey = TaskStore.dayKey(for: Date())
    @State private var newTaskTitle = ""
    @State private var showingResetAlert = false
    @State private var showingCalendar = false
    @State private var showingStatistics = false
    @State private var showingGoalEditor = false
    @State private var editingRequest: TaskEditRequest?
    @FocusState private var isAddingTask: Bool

    private let accent = Color(red: 0.96, green: 0.43, blue: 0.27)
    private let calendar = Calendar.autoupdatingCurrent

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            panel(at: context.date)
                .onChange(of: TaskStore.dayKey(for: context.date)) {
                    handleDayChange(at: context.date)
                }
        }
        .background(
            WindowConfigurator(isPinned: isPinned, isDesktopMode: isDesktopMode)
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
        .sheet(isPresented: $showingCalendar) {
            CalendarHistoryView(store: store, selectedDate: $selectedDate, accent: accent)
        }
        .sheet(isPresented: $showingStatistics) {
            MonthlyStatisticsView(store: store, initialMonth: selectedDate, accent: accent)
        }
        .sheet(item: $editingRequest) { request in
            TaskEditView(request: request, accent: accent) { title, completed, seconds in
                store.updateTask(
                    id: request.task.id,
                    on: request.date,
                    title: title,
                    isCompleted: completed,
                    elapsedSeconds: seconds
                )
            }
        }
    }

    private func panel(at now: Date) -> some View {
        let dayTasks = store.tasks(on: selectedDate)

        return VStack(spacing: 0) {
            header(at: now)

            dailyGoalBar

            if !calendar.isDate(selectedDate, inSameDayAs: now) {
                historyBanner
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
        HStack(alignment: .top, spacing: 8) {
            VStack(alignment: .leading, spacing: 4) {
                Text(calendar.isDate(selectedDate, inSameDayAs: now) ? "今日便笺" : "历史便笺")
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                    .foregroundStyle(Color(red: 0.22, green: 0.18, blue: 0.14))

                Text(selectedDate.formatted(.dateTime.year().month(.wide).day().weekday(.wide)))
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 6)

            headerButton("calendar", help: "日历与历史") {
                showingCalendar = true
            }

            headerButton("chart.bar.xaxis", help: "月度统计") {
                showingStatistics = true
            }

            headerButton(isDesktopMode ? "desktopcomputer.and.macbook" : "desktopcomputer", isActive: isDesktopMode, help: isDesktopMode ? "退出桌面模式" : "固定在系统桌面") {
                isDesktopMode.toggle()
            }

            headerButton(isPinned ? "pin.fill" : "pin", isActive: isPinned && !isDesktopMode, help: isPinned ? "取消置顶" : "保持置顶") {
                if isDesktopMode { isDesktopMode = false }
                isPinned.toggle()
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 20)
        .padding(.bottom, 16)
    }

    private func headerButton(
        _ systemName: String,
        isActive: Bool = false,
        help: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .frame(width: 26, height: 26)
        }
        .buttonStyle(HeaderButtonStyle(isActive: isActive, accent: accent))
        .help(help)
    }

    private var historyBanner: some View {
        HStack(spacing: 8) {
            Image(systemName: "clock.arrow.circlepath")
            Text("历史日期 · 可补打卡或右键编辑任务与时长")
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
                            onEdit: {
                                editingRequest = TaskEditRequest(task: task, date: selectedDate)
                            },
                            onDelete: {
                                store.deleteTask(id: task.id, on: selectedDate, at: now)
                            }
                        )
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
        HStack(spacing: 10) {
            Image(systemName: "plus.circle.fill")
                .font(.system(size: 18))
                .foregroundStyle(accent)

            TextField(calendar.isDateInToday(selectedDate) ? "添加任务，按回车保存" : "为这一天补记任务", text: $newTaskTitle)
                .textFieldStyle(.plain)
                .font(.system(size: 14, weight: .medium, design: .rounded))
                .focused($isAddingTask)
                .onSubmit(addTask)

            if !newTaskTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Button(action: addTask) {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 18))
                        .foregroundStyle(accent)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 13)
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
        store.addTask(title: newTaskTitle, on: selectedDate)
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
    let onSave: (String, Bool, TimeInterval) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var title: String
    @State private var isCompleted: Bool
    @State private var hours: Int
    @State private var minutes: Int

    init(request: TaskEditRequest, accent: Color, onSave: @escaping (String, Bool, TimeInterval) -> Void) {
        self.request = request
        self.accent = accent
        self.onSave = onSave
        _title = State(initialValue: request.task.title)
        _isCompleted = State(initialValue: request.task.isCompleted)
        _hours = State(initialValue: Int(request.task.elapsedSeconds) / 3600)
        _minutes = State(initialValue: (Int(request.task.elapsedSeconds) % 3600) / 60)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 4) {
                Text("编辑任务")
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                Text(request.date.formatted(.dateTime.year().month().day().weekday(.wide)))
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
            }

            TextField("任务名称", text: $title)
                .textFieldStyle(.roundedBorder)

            Toggle("已完成打卡", isOn: $isCompleted)

            VStack(alignment: .leading, spacing: 10) {
                Text("记录时长")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)
                Stepper("\(hours) 小时", value: $hours, in: 0...99)
                Stepper("\(minutes) 分钟", value: $minutes, in: 0...59)
            }

            HStack {
                Button("取消") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button("保存") {
                    onSave(title, isCompleted, TimeInterval(hours * 3600 + minutes * 60))
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .tint(accent)
                .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(24)
        .frame(width: 360)
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
    let onEdit: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 11) {
            Button(action: onToggleCompletion) {
                Image(systemName: task.isCompleted ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 20, weight: .medium))
                    .foregroundStyle(task.isCompleted ? accent : Color.secondary.opacity(0.55))
            }
            .buttonStyle(.plain)

            Text(task.title)
                .font(.system(size: 14, weight: .medium, design: .rounded))
                .foregroundStyle(task.isCompleted ? Color.secondary : Color.primary.opacity(0.86))
                .strikethrough(task.isCompleted, color: .secondary)
                .lineLimit(2)

            Spacer(minLength: 6)

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
        .contextMenu {
            Button("编辑任务与时长", action: onEdit)
            Divider()
            Button("删除任务", role: .destructive, action: onDelete)
        }
    }
}

private struct HeaderButtonStyle: ButtonStyle {
    let isActive: Bool
    let accent: Color

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(isActive ? accent : Color.secondary)
            .background(Circle().fill(isActive ? accent.opacity(0.13) : Color.white.opacity(0.45)))
            .scaleEffect(configuration.isPressed ? 0.92 : 1)
    }
}

private struct WindowConfigurator: NSViewRepresentable {
    let isPinned: Bool
    let isDesktopMode: Bool

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
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = true
        window.backgroundColor = .clear
        window.isOpaque = false
        window.hasShadow = true
        window.hidesOnDeactivate = false
        window.ignoresMouseEvents = false
        window.acceptsMouseMovedEvents = true
        window.setFrameAutosaveName("DayNote.MainWindow")
        coordinator.startMonitoring(window: window)

        if isDesktopMode {
            // Finder owns a transparent window at the desktop icon level. Placing
            // the note below it makes the note visible while Finder consumes all
            // mouse events. One level above the icons remains below normal app
            // windows but lets this window receive clicks and keyboard focus.
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

        func startMonitoring(window: NSWindow) {
            guard mouseMonitor == nil else { return }
            mouseMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak window] event in
                guard let window, event.window === window else { return event }

                // Desktop-level windows can receive the event while the app is
                // inactive. Activate and key the window before AppKit dispatches
                // the same event so buttons and text fields work on first click.
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
