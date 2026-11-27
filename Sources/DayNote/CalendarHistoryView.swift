import SwiftUI

struct CalendarHistoryView: View {
    @ObservedObject var store: TaskStore
    @Binding var selectedDate: Date
    let accent: Color

    @Environment(\.dismiss) private var dismiss
    @State private var visibleMonth: Date
    @State private var calendarSelection: Date
    @State private var showingTagEditor = false
    @State private var showingDayGoalEditor = false

    private let calendar = Calendar.autoupdatingCurrent
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 5), count: 7)

    init(store: TaskStore, selectedDate: Binding<Date>, accent: Color) {
        self.store = store
        _selectedDate = selectedDate
        self.accent = accent
        let date = selectedDate.wrappedValue
        _visibleMonth = State(initialValue: Calendar.autoupdatingCurrent.dateInterval(of: .month, for: date)?.start ?? date)
        _calendarSelection = State(initialValue: date)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("中国日历与历史")
                        .font(.system(size: 24, weight: .bold, design: .rounded))
                    Text("农历 · 法定节假日 · 学习记录 · 自定义标签")
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("完成") { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }
            .padding(24)

            Divider()

            HStack(spacing: 0) {
                VStack(spacing: 12) {
                    monthHeader
                    weekdayHeader
                    calendarGrid
                    calendarLegend
                    Spacer(minLength: 0)
                }
                .padding(20)
                .frame(width: 500)

                Divider()

                selectedDayPreview
                    .frame(width: 300)
            }
        }
        .frame(width: 800, height: 610)
        .background(Color(nsColor: .windowBackgroundColor))
        .sheet(isPresented: $showingTagEditor) {
            CalendarTagEditorView(
                date: calendarSelection,
                tags: store.tags(on: calendarSelection),
                accent: accent
            ) { tags in
                store.setTags(tags, on: calendarSelection)
            }
        }
    }

    private var monthHeader: some View {
        HStack {
            Button { changeMonth(by: -1) } label: { Image(systemName: "chevron.left") }
                .buttonStyle(.borderless)

            Spacer()

            VStack(spacing: 2) {
                Text(visibleMonth.formatted(.dateTime.year().month(.wide)))
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                if !ChinaCalendar.hasOfficialSchedule(for: calendar.component(.year, from: visibleMonth)) {
                    Text("该年度暂无官方放假安排")
                        .font(.system(size: 9, weight: .medium, design: .rounded))
                        .foregroundStyle(.orange)
                }
            }

            Spacer()

            Button { changeMonth(by: 1) } label: { Image(systemName: "chevron.right") }
                .buttonStyle(.borderless)
                .disabled(isShowingCurrentMonth)
        }
    }

    private var weekdayHeader: some View {
        LazyVGrid(columns: columns, spacing: 0) {
            ForEach(weekdaySymbols, id: \.self) { symbol in
                Text(symbol)
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
            }
        }
    }

    private var calendarGrid: some View {
        LazyVGrid(columns: columns, spacing: 5) {
            ForEach(Array(monthCells.enumerated()), id: \.offset) { _, date in
                if let date {
                    dayCell(date)
                } else {
                    Color.clear.frame(height: 60)
                }
            }
        }
    }

    private func dayCell(_ date: Date) -> some View {
        let isSelected = calendar.isDate(date, inSameDayAs: calendarSelection)
        let isToday = calendar.isDateInToday(date)
        let isFuture = date > calendar.startOfDay(for: Date())
        let taskCount = store.tasks(on: date).count
        let hasActivity = store.hasActivity(on: date)
        let achievement = StudyGoal.percent(elapsedSeconds: store.totalElapsed(on: date), goalMinutes: store.goalMinutes(on: date))
        let holiday = ChinaCalendar.officialHoliday(for: date)
        let festival = ChinaCalendar.traditionalFestival(for: date)
        let tags = store.tags(on: date)
        let lunar = festival ?? ChinaCalendar.lunarText(for: date)

        return Button {
            calendarSelection = date
        } label: {
            VStack(spacing: 1) {
                HStack(spacing: 2) {
                    Text("\(calendar.component(.day, from: date))")
                        .font(.system(size: 13, weight: isToday ? .bold : .medium, design: .rounded))
                    Spacer(minLength: 0)
                    if let holiday {
                        Text(holiday.badge)
                            .font(.system(size: 8, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
                            .frame(width: 15, height: 15)
                            .background(Circle().fill(holiday.kind == .holiday ? Color.red : Color.blue))
                    }
                }

                Text(lunar)
                    .font(.system(size: 9, weight: festival == nil ? .medium : .bold, design: .rounded))
                    .foregroundStyle(isSelected ? Color.white.opacity(0.85) : (festival == nil ? Color.secondary : Color.red))
                    .lineLimit(1)

                HStack(spacing: 2) {
                    if hasActivity {
                        Circle().fill(isSelected ? Color.white : accent).frame(width: 5, height: 5)
                    }
                    if taskCount > 0 {
                        Text("\(achievement)%")
                            .font(.system(size: 8, weight: .semibold, design: .rounded))
                    }
                    Spacer(minLength: 0)
                    ForEach(tags.prefix(3)) { tag in
                        Circle()
                            .fill(CalendarTagPalette.color(named: tag.colorName))
                            .frame(width: 5, height: 5)
                    }
                }
                .frame(height: 9)
            }
            .padding(.horizontal, 5)
            .foregroundStyle(isSelected ? Color.white : (isFuture ? Color.secondary.opacity(0.42) : Color.primary))
            .frame(maxWidth: .infinity, minHeight: 56)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(isSelected ? accent : (isToday ? accent.opacity(0.09) : Color.clear))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(isToday && !isSelected ? accent.opacity(0.45) : Color.clear, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .disabled(isFuture)
        .contextMenu {
            Button("编辑这一天的标签") {
                calendarSelection = date
                showingTagEditor = true
            }
        }
    }

    private var calendarLegend: some View {
        HStack(spacing: 12) {
            Label("法定休息", systemImage: "r.circle.fill")
                .symbolRenderingMode(.palette)
                .foregroundStyle(.white, .red)
            Label("调休上班", systemImage: "b.circle.fill")
                .symbolRenderingMode(.palette)
                .foregroundStyle(.white, .blue)
            HStack(spacing: 4) {
                Circle().fill(accent).frame(width: 6, height: 6)
                Text("学习记录")
            }
            HStack(spacing: 4) {
                Circle().fill(.purple).frame(width: 6, height: 6)
                Text("自定义标签")
            }
            Spacer()
        }
        .font(.system(size: 9, weight: .medium, design: .rounded))
        .foregroundStyle(.secondary)
    }

    private var selectedDayPreview: some View {
        let tasks = store.tasks(on: calendarSelection)
        let completed = tasks.lazy.filter(\.isCompleted).count
        let elapsed = store.totalElapsed(on: calendarSelection)
        let goalMinutes = store.goalMinutes(on: calendarSelection)
        let achievement = StudyGoal.percent(elapsedSeconds: elapsed, goalMinutes: goalMinutes)
        let holiday = ChinaCalendar.officialHoliday(for: calendarSelection)
        let festival = ChinaCalendar.traditionalFestival(for: calendarSelection)
        let tags = store.tags(on: calendarSelection)

        return VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(calendarSelection.formatted(.dateTime.month(.wide).day()))
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                HStack(spacing: 7) {
                    Text(calendarSelection.formatted(.dateTime.weekday(.wide)))
                    Text(ChinaCalendar.lunarDetail(for: calendarSelection))
                }
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .foregroundStyle(.secondary)
            }

            if holiday != nil || festival != nil {
                HStack(spacing: 6) {
                    if let holiday {
                        badge(
                            "\(holiday.badge) \(holiday.name)",
                            color: holiday.kind == .holiday ? .red : .blue
                        )
                    }
                    if let festival, festival != holiday?.name {
                        badge(festival, color: .orange)
                    }
                }
            }

            HStack(spacing: 12) {
                Label("达成 \(achievement)%", systemImage: "target")
                Label("打卡 \(completed)/\(tasks.count)", systemImage: "checkmark.circle")
            }
            .font(.system(size: 11, weight: .semibold, design: .rounded))
            .foregroundStyle(.secondary)

            Button {
                showingDayGoalEditor.toggle()
            } label: {
                Label("\(ContentView.formatDuration(elapsed)) / 目标 \(StudyGoal.durationLabel(minutes: goalMinutes))", systemImage: "timer")
            }
            .buttonStyle(.plain)
            .popover(isPresented: $showingDayGoalEditor, arrowEdge: .trailing) {
                StudyGoalEditor(
                    goalMinutes: Binding(
                        get: { store.goalMinutes(on: calendarSelection) },
                        set: { store.setGoalMinutes($0, on: calendarSelection) }
                    ),
                    date: calendarSelection,
                    accent: accent
                )
            }
            .help("调整这一天的学习目标")
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 7) {
                HStack {
                    Text("标签")
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                    Spacer()
                    Button {
                        showingTagEditor = true
                    } label: {
                        Label(tags.isEmpty ? "添加" : "编辑", systemImage: "tag")
                    }
                    .buttonStyle(.borderless)
                    .foregroundStyle(accent)
                }

                if tags.isEmpty {
                    Text("还没有自定义标签")
                        .font(.system(size: 10, weight: .medium, design: .rounded))
                        .foregroundStyle(.tertiary)
                } else {
                    FlowLayout(spacing: 5) {
                        ForEach(tags) { tag in
                            badge(tag.title, color: CalendarTagPalette.color(named: tag.colorName))
                        }
                    }
                }
            }

            Divider()

            if tasks.isEmpty {
                Text("这一天没有任务记录")
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(.tertiary)
                Spacer()
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(tasks) { task in
                            HStack(alignment: .top, spacing: 7) {
                                Image(systemName: task.isCompleted ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(task.isCompleted ? accent : Color.secondary)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(task.title)
                                        .font(.system(size: 12, weight: .medium, design: .rounded))
                                        .lineLimit(2)
                                    if task.elapsedSeconds > 0 {
                                        Text(ContentView.formatDuration(task.elapsedSeconds))
                                            .font(.system(size: 10, weight: .medium, design: .monospaced))
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }

            Button {
                selectedDate = calendarSelection
                dismiss()
            } label: {
                Text(calendar.isDateInToday(calendarSelection) ? "打开今日便笺" : "打开这一天")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(accent)
        }
        .padding(20)
    }

    private func badge(_ title: String, color: Color) -> some View {
        Text(title)
            .font(.system(size: 9, weight: .bold, design: .rounded))
            .foregroundStyle(color)
            .padding(.horizontal, 7)
            .padding(.vertical, 4)
            .background(Capsule().fill(color.opacity(0.12)))
            .lineLimit(1)
    }

    private var weekdaySymbols: [String] {
        let symbols = calendar.veryShortStandaloneWeekdaySymbols
        let start = max(0, calendar.firstWeekday - 1)
        return Array(symbols[start...] + symbols[..<start])
    }

    private var monthCells: [Date?] {
        guard
            let interval = calendar.dateInterval(of: .month, for: visibleMonth),
            let dayRange = calendar.range(of: .day, in: .month, for: visibleMonth)
        else { return [] }

        let weekday = calendar.component(.weekday, from: interval.start)
        let leading = (weekday - calendar.firstWeekday + 7) % 7
        var cells = Array<Date?>(repeating: nil, count: leading)
        cells.append(contentsOf: dayRange.compactMap { day in
            calendar.date(byAdding: .day, value: day - 1, to: interval.start)
        })
        while cells.count % 7 != 0 { cells.append(nil) }
        return cells
    }

    private var isShowingCurrentMonth: Bool {
        calendar.isDate(visibleMonth, equalTo: Date(), toGranularity: .month)
    }

    private func changeMonth(by value: Int) {
        guard let month = calendar.date(byAdding: .month, value: value, to: visibleMonth) else { return }
        visibleMonth = calendar.dateInterval(of: .month, for: month)?.start ?? month
    }
}

private struct FlowLayout: Layout {
    let spacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        arrange(proposal: proposal, subviews: subviews).size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = arrange(proposal: ProposedViewSize(width: bounds.width, height: proposal.height), subviews: subviews)
        for (index, point) in result.points.enumerated() {
            subviews[index].place(at: CGPoint(x: bounds.minX + point.x, y: bounds.minY + point.y), proposal: .unspecified)
        }
    }

    private func arrange(proposal: ProposedViewSize, subviews: Subviews) -> (size: CGSize, points: [CGPoint]) {
        let maxWidth = proposal.width ?? .infinity
        var points: [CGPoint] = []
        var x: CGFloat = 0
        var y: CGFloat = 0
        var lineHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0, x + size.width > maxWidth {
                x = 0
                y += lineHeight + spacing
                lineHeight = 0
            }
            points.append(CGPoint(x: x, y: y))
            x += size.width + spacing
            lineHeight = max(lineHeight, size.height)
        }
        return (CGSize(width: maxWidth.isFinite ? maxWidth : x, height: y + lineHeight), points)
    }
}
