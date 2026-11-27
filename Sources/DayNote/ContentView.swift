import AppKit
import SwiftUI

struct ContentView: View {
    @ObservedObject var store: TaskStore
    @ObservedObject var controller: AppController
    @ObservedObject var clock: LiveClock
    @AppStorage("daynote.pin-window") private var isPinned = true
    @AppStorage("daynote.desktop-mode") private var isDesktopMode = false
    @State private var selectedDate = Date()
    @State private var observedTodayKey = TaskStore.dayKey(for: Date())
    @State private var newTaskTitle = ""
    @State private var newTaskIsRecurring = true
    @State private var newTaskCategoryID: UUID?
    @State private var filterCategoryID: UUID?
    @State private var showingResetAlert = false
    @State private var showingCalendar = false
    @State private var showingStatistics = false
    @State private var showingSettings = false
    @State private var showingGoalEditor = false
    @State private var showingDailyNote = false
    @State private var showingSaveTemplateAlert = false
    @State private var templateNameDraft = ""
    @State private var editingRequest: TaskEditRequest?
    @FocusState private var isAddingTask: Bool

    private let calendar = Calendar.autoupdatingCurrent
    private var palette: DayNotePalette { controller.palette }

    var body: some View {
        let now = clock.now

        Group {
            if controller.isMiniMode {
                miniCapsule(at: now)
            } else {
                panel(at: now)
            }
        }
        .preferredColorScheme(palette.colorScheme)
        .onChange(of: TaskStore.dayKey(for: now)) {
            handleDayChange(at: now)
        }
        .frame(
            minWidth: controller.isMiniMode ? 290 : 356,
            idealWidth: controller.isMiniMode ? 344 : 384,
            maxWidth: controller.isMiniMode ? 440 : .infinity,
            minHeight: controller.isMiniMode ? 56 : 500,
            idealHeight: controller.isMiniMode ? 62 : 610,
            maxHeight: controller.isMiniMode ? 72 : .infinity
        )
        .background(
            WindowConfigurator(
                controller: controller,
                isPinned: isPinned,
                isDesktopMode: isDesktopMode,
                isMiniMode: controller.isMiniMode,
                windowOpacity: controller.windowOpacity,
                isDarkTheme: palette.isDark
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
        .alert("保存为任务模板", isPresented: $showingSaveTemplateAlert) {
            TextField("例如：工作日冲刺", text: $templateNameDraft)
            Button("取消", role: .cancel) { templateNameDraft = "" }
            Button("保存") {
                store.saveDayAsTemplate(name: templateNameDraft, from: selectedDate)
                templateNameDraft = ""
            }
        } message: {
            Text("将当前列表中的任务保存为快捷模板，随时可一键应用到任意日期。")
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
            CalendarHistoryView(store: store, selectedDate: $selectedDate, accent: palette.accent)
        }
        .sheet(isPresented: $showingStatistics) {
            MonthlyStatisticsView(store: store, initialMonth: selectedDate, accent: palette.accent)
        }
        .sheet(isPresented: $showingSettings) {
            SettingsView(store: store, controller: controller, accent: palette.accent)
        }
        .sheet(item: $editingRequest) { request in
            TaskEditView(
                request: request,
                categories: store.categories,
                accent: palette.accent
            ) { title, completed, seconds, isRecurring, categoryID in
                store.updateTask(
                    id: request.task.id,
                    on: request.date,
                    title: title,
                    isCompleted: completed,
                    elapsedSeconds: seconds,
                    isRecurring: isRecurring,
                    categoryID: .some(categoryID)
                )
            }
        }
    }

    // MARK: - Mini Floating Capsule

    private func miniCapsule(at now: Date) -> some View {
        let active = store.activeTask
        let totalElapsed = store.totalElapsed(on: now, at: now)
        let goalMin = store.goalMinutes(on: now)
        let progress = StudyGoal.rate(elapsedSeconds: totalElapsed, goalMinutes: goalMin)
        let percent = StudyGoal.percent(elapsedSeconds: totalElapsed, goalMinutes: goalMin)
        let pomodoroRem = controller.pomodoroRemainingSeconds(at: now)
        let displayTime = pomodoroRem ?? (active != nil ? store.activeElapsed(at: now) : totalElapsed)

        return HStack(spacing: 10) {
            ZStack {
                Circle()
                    .stroke(palette.accent.opacity(0.20), lineWidth: 3)
                Circle()
                    .trim(from: 0, to: pomodoroRem != nil ? controller.pomodoroProgress(at: now) : progress)
                    .stroke(palette.accent, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                if active != nil {
                    Circle().fill(palette.accent).frame(width: 6, height: 6)
                }
            }
            .frame(width: 22, height: 22)

            VStack(alignment: .leading, spacing: 1) {
                Text(active?.title ?? "今日便笺 · 达成 \(percent)%")
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundStyle(palette.inkPrimary)
                    .lineLimit(1)
                if active != nil {
                    Text(pomodoroRem != nil ? "🍅 番茄倒计时 · 今日 \(percent)%" : "今日总计 \(Self.formatDuration(totalElapsed)) · \(percent)%")
                        .font(.system(size: 9.5, weight: .medium, design: .rounded))
                        .foregroundStyle(palette.inkSecondary)
                        .monospacedDigit()
                }
            }

            Spacer(minLength: 4)

            Text(Self.formatDuration(displayTime))
                .font(.system(size: 13.5, weight: .bold, design: .monospaced))
                .foregroundStyle(active != nil ? palette.accent : palette.inkSecondary)
                .monospacedDigit()

            Button {
                store.toggleQuickTimer(at: now)
                controller.updateStatusBarTitle()
            } label: {
                Image(systemName: active != nil ? "pause.fill" : "play.fill")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(active != nil ? .white : palette.accent)
                    .frame(width: 26, height: 26)
                    .background(Circle().fill(active != nil ? palette.accent : palette.accentSoft))
            }
            .buttonStyle(.plain)
            .help(active != nil ? "暂停计时 (⌥⇧Space)" : "开始计时 (⌥⇧Space)")

            Button {
                controller.isMiniMode = false
            } label: {
                Image(systemName: "arrow.up.left.and.arrow.down.right")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(palette.inkSecondary)
                    .frame(width: 24, height: 24)
                    .background(Circle().fill(palette.surfaceCard))
            }
            .buttonStyle(.plain)
            .help("展开完整便笺")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .background(palette.backgroundGradient)
        .clipShape(Capsule())
        .overlay(
            Capsule()
                .stroke(active != nil ? palette.accent.opacity(0.45) : palette.borderSubtle, lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(palette.isDark ? 0.35 : 0.10), radius: 8, y: 3)
        .padding(4)
    }

    // MARK: - Main Sticky Note Panel (Redesigned 2-Tier Layout)

    private func panel(at now: Date) -> some View {
        let dayTasks = store.tasks(on: selectedDate)

        return VStack(spacing: 0) {
            windowChromeBar

            heroCard(dayTasks, at: now)
                .padding(.horizontal, 14)
                .padding(.top, 2)
                .padding(.bottom, 10)

            if let reminder = controller.focusReminderMessage {
                focusReminderBanner(reminder)
                    .padding(.horizontal, 14)
                    .padding(.bottom, 8)
            }

            if !calendar.isDate(selectedDate, inSameDayAs: now) {
                historyBanner(at: now)
                    .padding(.horizontal, 14)
                    .padding(.bottom, 8)
            }

            if showingDailyNote {
                dailyNoteDrawer
                    .padding(.horizontal, 14)
                    .padding(.bottom, 10)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }

            categoryFilterBar(for: dayTasks)

            taskList(filteredTasks(from: dayTasks), allDayTasksCount: dayTasks.count, at: now)

            addTaskBar
                .padding(.horizontal, 14)
                .padding(.top, 8)
                .padding(.bottom, 14)
        }
        .background(palette.backgroundGradient)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(palette.isDark ? Color.white.opacity(0.12) : Color.white.opacity(0.85), lineWidth: 1)
        )
        .padding(6)
    }

    // MARK: - Tier 1: Dedicated Window Chrome Bar (Zero Traffic-Light Overlap!)

    private var windowChromeBar: some View {
        HStack(spacing: 5) {
            // Left 68pt intentionally clear for native macOS traffic lights
            Spacer(minLength: 74)

            chromeIconButton(
                isDesktopMode ? "desktopcomputer.and.macbook" : "desktopcomputer",
                isActive: isDesktopMode,
                help: isDesktopMode ? "退出桌面模式" : "固定在系统桌面"
            ) {
                isDesktopMode.toggle()
            }

            chromeIconButton(
                isPinned ? "pin.fill" : "pin",
                isActive: isPinned && !isDesktopMode,
                help: isPinned ? "取消置顶" : "保持置顶"
            ) {
                if isDesktopMode { isDesktopMode = false }
                isPinned.toggle()
            }

            chromeIconButton(
                "rectangle.compress.vertical",
                isActive: false,
                help: "收起为迷你悬浮条"
            ) {
                controller.isMiniMode = true
            }

            chromeIconButton(
                "gearshape",
                isActive: false,
                help: "主题、快捷键与数据备份"
            ) {
                showingSettings = true
            }
        }
        .padding(.horizontal, 14)
        .padding(.top, 8)
        .padding(.bottom, 6)
    }

    private func chromeIconButton(
        _ systemName: String,
        isActive: Bool,
        help: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(isActive ? palette.accent : palette.inkSecondary.opacity(0.85))
                .frame(width: 24, height: 24)
                .background(
                    Circle().fill(isActive ? palette.accentSoft : palette.surfaceElevated)
                )
        }
        .buttonStyle(.plain)
        .help(help)
    }

    // MARK: - Tier 2: Unified Hero Focus Card

    private func heroCard(_ dayTasks: [DailyTask], at now: Date) -> some View {
        let isToday = calendar.isDate(selectedDate, inSameDayAs: now)
        let isFuture = selectedDate > calendar.startOfDay(for: now) && !isToday
        let elapsed = store.totalElapsed(on: selectedDate, at: now)
        let goalMinutes = store.goalMinutes(on: selectedDate)
        let progress = StudyGoal.rate(elapsedSeconds: elapsed, goalMinutes: goalMinutes)
        let percent = StudyGoal.percent(elapsedSeconds: elapsed, goalMinutes: goalMinutes)
        let completed = dayTasks.lazy.filter(\.isCompleted).count
        let streak = store.currentStreak(at: now)
        let pomodoros = store.pomodoroCount(on: selectedDate)
        let lunarShort = ChinaCalendar.traditionalFestival(for: selectedDate) ?? ChinaCalendar.lunarDetail(for: selectedDate)
        let pomodoroRem = isToday ? controller.pomodoroRemainingSeconds(at: now) : nil

        return VStack(alignment: .leading, spacing: 11) {
            // Top Row: Title + Date + Progress Ring
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text(isToday ? "今日便笺" : (isFuture ? "计划便笺" : "历史便笺"))
                            .font(.system(size: 20, weight: .bold, design: .rounded))
                            .foregroundStyle(palette.inkPrimary)

                        if streak > 0 && isToday {
                            HStack(spacing: 2) {
                                Image(systemName: "flame.fill")
                                    .font(.system(size: 9))
                                Text("\(streak)天")
                                    .font(.system(size: 10, weight: .bold, design: .rounded))
                            }
                            .foregroundStyle(palette.accent)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2.5)
                            .background(Capsule().fill(palette.accentSoft))
                            .help("已连续打卡 \(streak) 天")
                        }

                        if pomodoros > 0 {
                            Text("🍅×\(pomodoros)")
                                .font(.system(size: 10, weight: .bold, design: .rounded))
                                .foregroundStyle(palette.inkSecondary)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2.5)
                                .background(Capsule().fill(palette.borderSubtle))
                                .help("当天已完成 \(pomodoros) 个番茄")
                        }
                    }

                    Text("\(selectedDate.formatted(.dateTime.month().day().weekday(.abbreviated))) · \(lunarShort)")
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundStyle(palette.inkSecondary)
                }

                Spacer(minLength: 4)

                // Circular Progress Ring
                ZStack {
                    Circle()
                        .stroke(palette.accent.opacity(0.16), lineWidth: 5)
                    Circle()
                        .trim(from: 0, to: progress)
                        .stroke(
                            AngularGradient(
                                colors: [palette.accent.opacity(0.75), palette.accent],
                                center: .center
                            ),
                            style: StrokeStyle(lineWidth: 5, lineCap: .round)
                        )
                        .rotationEffect(.degrees(-90))
                        .animation(.easeOut(duration: 0.35), value: progress)

                    VStack(spacing: -1) {
                        Text("\(percent)%")
                            .font(.system(size: 12, weight: .bold, design: .rounded))
                            .foregroundStyle(palette.inkPrimary)
                            .monospacedDigit()
                        Text("\(completed)/\(dayTasks.count)")
                            .font(.system(size: 8.5, weight: .semibold, design: .rounded))
                            .foregroundStyle(palette.inkSecondary)
                            .monospacedDigit()
                    }
                }
                .frame(width: 50, height: 50)
                .help("学习时长达成率 \(percent)% · 任务打卡 \(completed)/\(dayTasks.count)")
            }

            // Middle Row: Big Focus Duration + Compact Goal Pill
            HStack(alignment: .center, spacing: 8) {
                HStack(alignment: .firstTextBaseline, spacing: 5) {
                    Text(Self.formatDuration(elapsed))
                        .font(.system(size: 21, weight: .bold, design: .rounded))
                        .foregroundStyle(store.isTimerRunning && isToday ? palette.accent : palette.inkPrimary)
                        .monospacedDigit()
                    Text("专注")
                        .font(.system(size: 10.5, weight: .semibold, design: .rounded))
                        .foregroundStyle(palette.inkSecondary)
                }

                Spacer()

                // Compact Goal Stepper Pill
                HStack(spacing: 4) {
                    Button {
                        store.setGoalMinutes(goalMinutes - 30, on: selectedDate)
                    } label: {
                        Image(systemName: "minus")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(palette.inkSecondary)
                            .frame(width: 20, height: 20)
                            .background(Circle().fill(palette.borderSubtle))
                    }
                    .buttonStyle(.plain)
                    .disabled(goalMinutes <= 30)
                    .help("目标减少半小时")

                    Button {
                        showingGoalEditor.toggle()
                    } label: {
                        HStack(spacing: 3) {
                            Text("目标 \(StudyGoal.compactDurationLabel(minutes: goalMinutes))")
                                .monospacedDigit()
                            Image(systemName: "chevron.down")
                                .font(.system(size: 7.5, weight: .bold))
                        }
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundStyle(palette.accent)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Capsule().fill(palette.accentSoft))
                    }
                    .buttonStyle(.plain)
                    .popover(isPresented: $showingGoalEditor, arrowEdge: .bottom) {
                        StudyGoalEditor(
                            goalMinutes: Binding(
                                get: { store.goalMinutes(on: selectedDate) },
                                set: { store.setGoalMinutes($0, on: selectedDate) }
                            ),
                            date: selectedDate,
                            accent: palette.accent
                        )
                    }
                    .help("选择当天学习目标")

                    Button {
                        store.setGoalMinutes(goalMinutes + 30, on: selectedDate)
                    } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(palette.inkSecondary)
                            .frame(width: 20, height: 20)
                            .background(Circle().fill(palette.borderSubtle))
                    }
                    .buttonStyle(.plain)
                    .disabled(goalMinutes >= 24 * 60)
                    .help("目标增加半小时")
                }
            }

            // Optional Pomodoro Live Progress Strip
            if let remaining = pomodoroRem {
                VStack(spacing: 5) {
                    HStack {
                        Label("番茄倒计时（\(controller.pomodoroMinutes)分钟）", systemImage: "flame.fill")
                            .font(.system(size: 10.5, weight: .bold, design: .rounded))
                            .foregroundStyle(palette.accent)
                        Spacer()
                        Text("剩余 \(Self.formatDuration(remaining))")
                            .font(.system(size: 11, weight: .bold, design: .monospaced))
                            .foregroundStyle(palette.accent)
                    }
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule().fill(palette.accent.opacity(0.16))
                            Capsule()
                                .fill(palette.accent)
                                .frame(width: geo.size.width * controller.pomodoroProgress(at: now))
                        }
                    }
                    .frame(height: 4)
                }
                .padding(.top, 2)
            }

            // Optional Countdown Chip
            if let nearest = store.upcomingCountdowns(from: now).first {
                let chipColor = CalendarTagPalette.color(named: nearest.event.colorName)
                Button {
                    showingSettings = true
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "flag.fill")
                            .font(.system(size: 9.5))
                            .foregroundStyle(chipColor)
                        Text(nearest.event.title)
                            .font(.system(size: 11, weight: .semibold, design: .rounded))
                            .foregroundStyle(palette.inkPrimary)
                            .lineLimit(1)
                        Spacer()
                        Text(nearest.daysRemaining == 0 ? "就是今天!" : "还剩 \(nearest.daysRemaining) 天")
                            .font(.system(size: 11, weight: .bold, design: .rounded))
                            .foregroundStyle(chipColor)
                            .monospacedDigit()
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(chipColor.opacity(0.10)))
                }
                .buttonStyle(.plain)
                .help("点击管理首页倒计时")
            }

            // Bottom Row: 4 Crisp Labeled Action Pills
            HStack(spacing: 6) {
                actionPill(title: "日历", icon: "calendar", isActive: false) {
                    showingCalendar = true
                }
                actionPill(title: "统计", icon: "chart.bar.xaxis", isActive: false) {
                    showingStatistics = true
                }
                actionPill(
                    title: "随记",
                    icon: "square.and.pencil",
                    isActive: showingDailyNote,
                    showDot: store.hasNote(on: selectedDate) && !showingDailyNote
                ) {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        showingDailyNote.toggle()
                    }
                }
                pomodoroPill
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(palette.surfaceCard)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(palette.borderSubtle, lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(palette.isDark ? 0.22 : 0.045), radius: 8, y: 3)
        .contextMenu {
            Button("清零这一天", role: .destructive) { showingResetAlert = true }
        }
    }

    private func actionPill(
        title: String,
        icon: String,
        isActive: Bool,
        showDot: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 10.5, weight: .semibold))
                Text(title)
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                if showDot {
                    Circle().fill(palette.accent).frame(width: 5, height: 5)
                }
            }
            .foregroundStyle(isActive ? .white : palette.inkPrimary.opacity(0.82))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(isActive ? palette.accent : palette.surfaceElevated)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .stroke(isActive ? Color.clear : palette.borderSubtle, lineWidth: 0.8)
            )
        }
        .buttonStyle(.plain)
    }

    private var pomodoroPill: some View {
        Menu {
            Button {
                controller.pomodoroEnabled = false
            } label: {
                Label("正向计时（秒表）", systemImage: controller.pomodoroEnabled ? "circle" : "checkmark.circle.fill")
            }
            Divider()
            ForEach([25, 45, 60], id: \.self) { mins in
                Button {
                    controller.pomodoroMinutes = mins
                    controller.pomodoroEnabled = true
                } label: {
                    Label(
                        "番茄倒计时 \(mins) 分钟",
                        systemImage: (controller.pomodoroEnabled && controller.pomodoroMinutes == mins) ? "checkmark.circle.fill" : "flame"
                    )
                }
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: controller.pomodoroEnabled ? "flame.fill" : "flame")
                    .font(.system(size: 10.5, weight: .semibold))
                Text(controller.pomodoroEnabled ? "\(controller.pomodoroMinutes)分" : "番茄")
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
            }
            .foregroundStyle(controller.pomodoroEnabled ? .white : palette.inkPrimary.opacity(0.82))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(controller.pomodoroEnabled ? palette.accent : palette.surfaceElevated)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .stroke(controller.pomodoroEnabled ? Color.clear : palette.borderSubtle, lineWidth: 0.8)
            )
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .help("切换正向秒表或番茄倒计时模式")
    }

    // MARK: - Daily Note Collapsible Drawer

    private var dailyNoteDrawer: some View {
        let binding = Binding<String>(
            get: { store.note(on: selectedDate) },
            set: { store.setNote($0, on: selectedDate) }
        )
        return VStack(alignment: .leading, spacing: 6) {
            HStack {
                Label(calendar.isDateInToday(selectedDate) ? "今日随记" : "当日随记", systemImage: "note.text")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundStyle(palette.accent)
                Spacer()
                Text("自动保存")
                    .font(.system(size: 9.5, design: .rounded))
                    .foregroundStyle(palette.inkSecondary.opacity(0.75))
            }

            ZStack(alignment: .topLeading) {
                if binding.wrappedValue.isEmpty {
                    Text("记下今天的复盘小结、错题提醒或灵感...")
                        .font(.system(size: 12, design: .rounded))
                        .foregroundStyle(palette.inkSecondary.opacity(0.55))
                        .padding(.top, 5)
                        .padding(.leading, 4)
                        .allowsHitTesting(false)
                }
                TextEditor(text: binding)
                    .font(.system(size: 12.5, design: .rounded))
                    .foregroundStyle(palette.inkPrimary)
                    .scrollContentBackground(.hidden)
                    .frame(minHeight: 62, maxHeight: 92)
            }
        }
        .padding(11)
        .background(
            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .fill(palette.surfaceCard)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .stroke(palette.accent.opacity(0.25), lineWidth: 1)
        )
    }

    // MARK: - Banners

    private func focusReminderBanner(_ message: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "bell.badge.fill")
                .foregroundStyle(palette.accent)
            Text(message)
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(palette.inkPrimary)
                .lineLimit(2)
            Spacer(minLength: 4)
            Button("休息") {
                controller.pauseForBreak()
            }
            .buttonStyle(.borderedProminent)
            .tint(palette.accent)
            .controlSize(.mini)
            Button("知道了") {
                controller.dismissFocusReminder()
            }
            .buttonStyle(.bordered)
            .controlSize(.mini)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(palette.accentSoft)
        )
    }

    private func historyBanner(at now: Date) -> some View {
        let isFuture = selectedDate > calendar.startOfDay(for: now)
        return HStack(spacing: 8) {
            Image(systemName: isFuture ? "calendar.badge.plus" : "clock.arrow.circlepath")
                .foregroundStyle(palette.accent)
            Text(isFuture ? "未来日期 · 可提前安排任务与目标" : "历史日期 · 可补打卡或编辑任务时长")
                .lineLimit(1)
            Spacer()
            Button("回到今天") {
                selectedDate = Date()
            }
            .buttonStyle(.plain)
            .foregroundStyle(palette.accent)
            .fontWeight(.bold)
        }
        .font(.system(size: 11, weight: .semibold, design: .rounded))
        .foregroundStyle(palette.inkSecondary)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .fill(palette.accentSoft)
        )
    }

    // MARK: - Category Filter Bar

    @ViewBuilder
    private func categoryFilterBar(for dayTasks: [DailyTask]) -> some View {
        let presentIDs = Set(dayTasks.compactMap(\.categoryID))
        let visibleCategories = store.categories.filter { presentIDs.contains($0.id) }
        if visibleCategories.count >= 2 {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    filterChip(title: "全部", color: palette.accent, isSelected: filterCategoryID == nil) {
                        filterCategoryID = nil
                    }
                    ForEach(visibleCategories) { cat in
                        filterChip(
                            title: cat.name,
                            color: CalendarTagPalette.color(named: cat.colorName),
                            isSelected: filterCategoryID == cat.id
                        ) {
                            filterCategoryID = (filterCategoryID == cat.id) ? nil : cat.id
                        }
                    }
                }
                .padding(.horizontal, 14)
                .padding(.bottom, 6)
            }
        }
    }

    private func filterChip(title: String, color: Color, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Circle()
                    .fill(isSelected ? Color.white : color)
                    .frame(width: 6, height: 6)
                Text(title)
                    .font(.system(size: 10.5, weight: .semibold, design: .rounded))
            }
            .foregroundStyle(isSelected ? Color.white : palette.inkSecondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Capsule().fill(isSelected ? color : palette.surfaceElevated))
            .overlay(Capsule().stroke(isSelected ? Color.clear : palette.borderSubtle, lineWidth: 0.8))
        }
        .buttonStyle(.plain)
    }

    private func filteredTasks(from dayTasks: [DailyTask]) -> [DailyTask] {
        guard let filterCategoryID else { return dayTasks }
        let matched = dayTasks.filter { $0.categoryID == filterCategoryID }
        return matched.isEmpty ? dayTasks : matched
    }

    // MARK: - Task List

    @ViewBuilder
    private func taskList(_ dayTasks: [DailyTask], allDayTasksCount: Int, at now: Date) -> some View {
        if allDayTasksCount == 0 {
            VStack(spacing: 10) {
                Image(systemName: "sparkles")
                    .font(.system(size: 28, weight: .light))
                    .foregroundStyle(palette.accent.opacity(0.75))
                Text(calendar.isDate(selectedDate, inSameDayAs: now) ? "写下今天想专注的事" : "这一天还没有任务记录")
                    .font(.system(size: 13.5, weight: .medium, design: .rounded))
                    .foregroundStyle(palette.inkSecondary)
                if !store.taskTemplates.isEmpty {
                    Menu("从模板一键导入") {
                        ForEach(store.taskTemplates) { template in
                            Button("\(template.name)（\(template.items.count) 项）") {
                                store.applyTemplate(template, to: selectedDate)
                            }
                        }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
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
                            category: store.category(for: task.categoryID),
                            allCategories: store.categories,
                            elapsed: store.elapsed(for: task, on: selectedDate, at: now),
                            isRunning: store.activeDayKey == TaskStore.dayKey(for: selectedDate) && store.activeTaskID == task.id,
                            canStartTimer: calendar.isDate(selectedDate, inSameDayAs: now),
                            palette: palette,
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
                            onSelectCategory: { categoryID in
                                store.setCategory(categoryID, for: task.id, on: selectedDate)
                            },
                            onApplyCategoryToAllSameName: { categoryID in
                                store.applyCategoryToAllTasksNamed(task.title, categoryID: categoryID)
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
                                .background(RoundedRectangle(cornerRadius: 8).fill(palette.surfaceCardActive))
                        }
                        .dropDestination(for: String.self) { items, _ in
                            guard let raw = items.first, let dragged = UUID(uuidString: raw) else { return false }
                            withAnimation(.easeInOut(duration: 0.18)) {
                                store.moveTask(draggedID: dragged, targetID: task.id, on: selectedDate)
                            }
                            return true
                        }
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 4)
            }
            .scrollIndicators(.hidden)
            .frame(maxHeight: .infinity)
        }
    }

    // MARK: - Bottom Floating Add-Task Capsule

    private var addTaskBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "plus.circle.fill")
                .font(.system(size: 18))
                .foregroundStyle(palette.accent)

            TextField(calendar.isDateInToday(selectedDate) ? "添加任务，按回车保存" : "为这一天添加任务", text: $newTaskTitle)
                .textFieldStyle(.plain)
                .font(.system(size: 13.5, weight: .medium, design: .rounded))
                .foregroundStyle(palette.inkPrimary)
                .focused($isAddingTask)
                .onSubmit(addTask)

            Menu {
                Button {
                    newTaskCategoryID = nil
                } label: {
                    Label("无分类", systemImage: newTaskCategoryID == nil ? "checkmark.circle.fill" : "circle")
                }
                if !store.categories.isEmpty {
                    Divider()
                    ForEach(store.categories) { cat in
                        Button {
                            newTaskCategoryID = cat.id
                        } label: {
                            Label(cat.name, systemImage: newTaskCategoryID == cat.id ? "checkmark.circle.fill" : "circle.fill")
                        }
                    }
                }
                Divider()
                Button {
                    showingSettings = true
                } label: {
                    Label("管理分类…", systemImage: "slider.horizontal.3")
                }
            } label: {
                let selectedCat = store.category(for: newTaskCategoryID)
                let catColor = selectedCat.map { CalendarTagPalette.color(named: $0.colorName) } ?? palette.inkSecondary
                HStack(spacing: 3) {
                    Circle()
                        .fill(selectedCat != nil ? catColor : palette.inkSecondary.opacity(0.45))
                        .frame(width: 6, height: 6)
                    Text(selectedCat?.name ?? "分类")
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .lineLimit(1)
                }
                .foregroundStyle(selectedCat != nil ? catColor : palette.inkSecondary)
                .padding(.horizontal, 7)
                .padding(.vertical, 3.5)
                .background(Capsule().fill(selectedCat != nil ? catColor.opacity(0.13) : palette.borderSubtle))
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .help("为新任务选择分类")

            Button {
                newTaskIsRecurring.toggle()
            } label: {
                Text(newTaskIsRecurring ? "每日" : "仅今天")
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .foregroundStyle(newTaskIsRecurring ? palette.accent : Color.blue)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3.5)
                    .background(Capsule().fill((newTaskIsRecurring ? palette.accent : Color.blue).opacity(0.13)))
            }
            .buttonStyle(.plain)
            .help(newTaskIsRecurring ? "每日固定任务：次日自动沿用（点击切换为仅今天）" : "仅今天临时任务：次日不会自动复制（点击切换为每日固定）")

            Menu {
                if !store.tasks(on: selectedDate).isEmpty {
                    Button {
                        templateNameDraft = ""
                        showingSaveTemplateAlert = true
                    } label: {
                        Label("将当前任务存为模板…", systemImage: "square.and.arrow.down")
                    }
                }
                if !store.taskTemplates.isEmpty {
                    Divider()
                    Section("应用模板（追加）") {
                        ForEach(store.taskTemplates) { template in
                            Button("\(template.name)（\(template.items.count) 项）") {
                                store.applyTemplate(template, to: selectedDate, replaceExisting: false)
                            }
                        }
                    }
                }
                Divider()
                Button("清零这一天", role: .destructive) {
                    showingResetAlert = true
                }
            } label: {
                Image(systemName: "doc.on.clipboard")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(palette.inkSecondary)
                    .frame(width: 22, height: 22)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .help("任务模板与当天操作")

            if !newTaskTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Button(action: addTask) {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 19))
                        .foregroundStyle(palette.accent)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(palette.surfaceCard)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(isAddingTask ? palette.accent.opacity(0.55) : palette.borderSubtle, lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(palette.isDark ? 0.2 : 0.04), radius: 6, y: 2)
    }

    private func addTask() {
        let effectiveCat = newTaskCategoryID ?? filterCategoryID
        store.addTask(title: newTaskTitle, on: selectedDate, isRecurring: newTaskIsRecurring, categoryID: effectiveCat)
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
    let categories: [TaskCategory]
    let accent: Color
    let onSave: (String, Bool, TimeInterval, Bool, UUID?) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var title: String
    @State private var isCompleted: Bool
    @State private var isRecurring: Bool
    @State private var categoryID: UUID?
    @State private var totalMinutes: Int
    @State private var hoursText: String
    @State private var minutesText: String

    init(
        request: TaskEditRequest,
        categories: [TaskCategory],
        accent: Color,
        onSave: @escaping (String, Bool, TimeInterval, Bool, UUID?) -> Void
    ) {
        self.request = request
        self.categories = categories
        self.accent = accent
        self.onSave = onSave
        let mins = max(0, Int(request.task.elapsedSeconds) / 60)
        _title = State(initialValue: request.task.title)
        _isCompleted = State(initialValue: request.task.isCompleted)
        _isRecurring = State(initialValue: request.task.isRecurring)
        _categoryID = State(initialValue: request.task.categoryID)
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

            if !categories.isEmpty {
                HStack {
                    Text("任务分类")
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Picker("", selection: $categoryID) {
                        Text("未分类").tag(UUID?.none)
                        ForEach(categories) { cat in
                            Text(cat.name).tag(UUID?.some(cat.id))
                        }
                    }
                    .labelsHidden()
                    .frame(width: 170)
                }
            }

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
                    onSave(title, isCompleted, TimeInterval(totalMinutes * 60), isRecurring, categoryID)
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
    let category: TaskCategory?
    let allCategories: [TaskCategory]
    let elapsed: TimeInterval
    let isRunning: Bool
    let canStartTimer: Bool
    let palette: DayNotePalette
    let onToggleCompletion: () -> Void
    let onToggleTimer: () -> Void
    let onRename: (String) -> Void
    let onAdjustMinutes: (Int) -> Void
    let onToggleRecurring: () -> Void
    let onSelectCategory: (UUID?) -> Void
    let onApplyCategoryToAllSameName: (UUID?) -> Void
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
                    .font(.system(size: 19, weight: .medium))
                    .foregroundStyle(task.isCompleted ? palette.accent : palette.inkSecondary.opacity(0.45))
            }
            .buttonStyle(.plain)

            if isInlineEditing {
                TextField("任务名称", text: $draftTitle)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13.5, weight: .medium, design: .rounded))
                    .foregroundStyle(palette.inkPrimary)
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
                        .font(.system(size: 13.5, weight: isRunning ? .semibold : .medium, design: .rounded))
                        .foregroundStyle(task.isCompleted ? palette.inkSecondary.opacity(0.75) : palette.inkPrimary)
                        .strikethrough(task.isCompleted, color: palette.inkSecondary.opacity(0.7))
                        .lineLimit(2)

                    if category != nil || !task.isRecurring {
                        HStack(spacing: 4) {
                            if let category {
                                let catColor = CalendarTagPalette.color(named: category.colorName)
                                HStack(spacing: 3) {
                                    Circle().fill(catColor).frame(width: 5, height: 5)
                                    Text(category.name)
                                }
                                .font(.system(size: 9, weight: .semibold, design: .rounded))
                                .foregroundStyle(catColor)
                                .padding(.horizontal, 5.5)
                                .padding(.vertical, 1.5)
                                .background(Capsule().fill(catColor.opacity(0.12)))
                            }
                            if !task.isRecurring {
                                Text("仅今天")
                                    .font(.system(size: 9, weight: .semibold, design: .rounded))
                                    .foregroundStyle(.blue)
                                    .padding(.horizontal, 5)
                                    .padding(.vertical, 1.5)
                                    .background(Capsule().fill(Color.blue.opacity(0.11)))
                            }
                        }
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
                        .foregroundStyle(palette.inkSecondary)
                        .frame(width: 20, height: 20)
                }
                .buttonStyle(.plain)
                .help("编辑任务与时长")
            }

            Text(ContentView.formatDuration(elapsed))
                .font(.system(size: 11.5, weight: .semibold, design: .monospaced))
                .foregroundStyle(isRunning ? palette.accent : palette.inkSecondary)
                .monospacedDigit()

            if canStartTimer {
                Button(action: onToggleTimer) {
                    Image(systemName: isRunning ? "pause.fill" : "play.fill")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(task.isCompleted ? palette.inkSecondary.opacity(0.35) : (isRunning ? .white : palette.accent))
                        .frame(width: 27, height: 27)
                        .background(Circle().fill(isRunning ? palette.accent : palette.accent.opacity(task.isCompleted ? 0.06 : 0.13)))
                }
                .buttonStyle(.plain)
                .disabled(task.isCompleted)
            } else {
                Button(action: onEdit) {
                    Image(systemName: "pencil")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(palette.accent)
                        .frame(width: 27, height: 27)
                        .background(Circle().fill(palette.accentSoft))
                }
                .buttonStyle(.plain)
                .help("编辑任务与时长")
            }
        }
        .padding(.leading, isRunning ? 14 : 12)
        .padding(.trailing, 11)
        .padding(.vertical, 10)
        .background(
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .fill(isRunning ? palette.surfaceCardActive : palette.surfaceCard)
                if isRunning {
                    RoundedRectangle(cornerRadius: 2, style: .continuous)
                        .fill(palette.accent)
                        .frame(width: 3.5)
                        .padding(.vertical, 8)
                        .padding(.leading, 4)
                }
            }
        )
        .overlay(
            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .stroke(isRunning ? palette.accent.opacity(0.34) : palette.borderSubtle, lineWidth: 1)
        )
        .shadow(
            color: Color.black.opacity(isRunning ? (palette.isDark ? 0.25 : 0.06) : (palette.isDark ? 0.12 : 0.025)),
            radius: isRunning ? 6 : 3,
            y: isRunning ? 2 : 1
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
            if !allCategories.isEmpty {
                Menu("设置分类") {
                    Button {
                        onSelectCategory(nil)
                    } label: {
                        Label("未分类", systemImage: category == nil ? "checkmark.circle.fill" : "circle")
                    }
                    Divider()
                    ForEach(allCategories) { cat in
                        Button {
                            onSelectCategory(cat.id)
                        } label: {
                            Label(cat.name, systemImage: category?.id == cat.id ? "checkmark.circle.fill" : "circle.fill")
                        }
                    }
                }
                if let category {
                    Button("将所有同名历史任务归入「\(category.name)」") {
                        onApplyCategoryToAllSameName(category.id)
                    }
                }
                Divider()
            }
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

private struct AppliedWindowConfig: Equatable {
    let isPinned: Bool
    let isDesktopMode: Bool
    let isMiniMode: Bool
    let windowOpacity: Double
    let isDarkTheme: Bool
}

private struct WindowConfigurator: NSViewRepresentable {
    let controller: AppController
    let isPinned: Bool
    let isDesktopMode: Bool
    let isMiniMode: Bool
    let windowOpacity: Double
    let isDarkTheme: Bool

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            applyIfNeeded(window: view.window, coordinator: context.coordinator)
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        let desired = AppliedWindowConfig(
            isPinned: isPinned,
            isDesktopMode: isDesktopMode,
            isMiniMode: isMiniMode,
            windowOpacity: windowOpacity,
            isDarkTheme: isDarkTheme
        )
        guard context.coordinator.lastConfig != desired || context.coordinator.configuredWindow == nil else {
            return
        }
        DispatchQueue.main.async {
            applyIfNeeded(window: nsView.window, coordinator: context.coordinator)
        }
    }

    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        coordinator.stopMonitoring()
    }

    private func applyIfNeeded(window: NSWindow?, coordinator: Coordinator) {
        guard let window else { return }
        let desired = AppliedWindowConfig(
            isPinned: isPinned,
            isDesktopMode: isDesktopMode,
            isMiniMode: isMiniMode,
            windowOpacity: windowOpacity,
            isDarkTheme: isDarkTheme
        )
        guard coordinator.configuredWindow !== window || coordinator.lastConfig != desired else { return }

        controller.mainWindow = window
        if coordinator.configuredWindow !== window {
            coordinator.configuredWindow = window
            window.titleVisibility = .hidden
            window.titlebarAppearsTransparent = true
            window.isMovableByWindowBackground = true
            window.backgroundColor = .clear
            window.isOpaque = false
            window.hasShadow = true
            window.hidesOnDeactivate = false
            window.isReleasedWhenClosed = false
            window.ignoresMouseEvents = false
            window.acceptsMouseMovedEvents = true
            coordinator.startMonitoring(window: window)
        }

        coordinator.lastConfig = desired
        window.alphaValue = CGFloat(windowOpacity)
        window.appearance = NSAppearance(named: isDarkTheme ? .darkAqua : .aqua)
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
        weak var configuredWindow: NSWindow?
        var lastConfig: AppliedWindowConfig?
        private var mouseMonitor: Any?
        private var lastMiniMode: Bool?
        private var savedNormalFrame: NSRect?

        func applyMiniMode(_ isMini: Bool, to window: NSWindow) {
            if lastMiniMode == nil {
                window.setFrameAutosaveName("DayNote.MainWindow")
                lastMiniMode = isMini
                if isMini {
                    savedNormalFrame = NSRect(x: window.frame.origin.x, y: window.frame.origin.y, width: 384, height: 610)
                    let topY = window.frame.maxY
                    window.setFrame(NSRect(x: window.frame.origin.x, y: topY - 62, width: 344, height: 62), display: true, animate: false)
                }
                return
            }
            guard lastMiniMode != isMini else { return }
            lastMiniMode = isMini

            if isMini {
                savedNormalFrame = window.frame
                let topY = window.frame.maxY
                let miniFrame = NSRect(x: window.frame.origin.x, y: topY - 62, width: 344, height: 62)
                window.setFrame(miniFrame, display: true, animate: true)
            } else {
                let targetSize = savedNormalFrame?.size ?? NSSize(width: 384, height: 610)
                let topY = window.frame.maxY
                let normalFrame = NSRect(
                    x: window.frame.origin.x,
                    y: max(40, topY - targetSize.height),
                    width: max(356, targetSize.width),
                    height: max(500, targetSize.height)
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
