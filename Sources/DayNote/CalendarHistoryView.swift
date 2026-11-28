import SwiftUI

struct CalendarHistoryView: View {
    @ObservedObject var store: TaskStore
    @Binding var selectedDate: Date
    let accent: Color

    @Environment(\.dismiss) private var dismiss
    @State private var visibleMonth: Date
    @State private var calendarSelection: Date
    @State private var searchQuery = ""
    @State private var showingTagEditor = false
    @State private var showingDayGoalEditor = false
    @State private var showingCountdownPopover = false
    @State private var countdownTitleDraft = ""

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
            HStack(spacing: 14) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("中国日历与历史")
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                    Text("农历 · 2024–2027 节假日 · 随记搜索 · 倒计时")
                        .font(.system(size: 11.5, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                }

                Spacer()

                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                    TextField("搜索任务、随记或标签…", text: $searchQuery)
                        .textFieldStyle(.plain)
                        .font(.system(size: 12, design: .rounded))
                    if !searchQuery.isEmpty {
                        Button { searchQuery = "" } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .frame(width: 210)
                .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(Color.secondary.opacity(0.10)))

                Button("完成") { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }
            .padding(.horizontal, 22)
            .padding(.vertical, 18)

            Divider()

            HStack(spacing: 0) {
                if !searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    searchResultsPane
                        .frame(width: 500)
                } else {
                    VStack(spacing: 12) {
                        monthHeader
                        weekdayHeader
                        calendarGrid
                        calendarLegend
                        Spacer(minLength: 0)
                    }
                    .padding(20)
                    .frame(width: 500)
                }

                Divider()

                selectedDayPreview
                    .frame(width: 320)
            }
        }
        .frame(width: 820, height: 630)
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

    private var searchResultsPane: some View {
        let matches = store.searchHistory(query: searchQuery)
        return VStack(alignment: .leading, spacing: 12) {
            Text("找到 \(matches.count) 条匹配日期")
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(.secondary)

            if matches.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 28, weight: .light))
                        .foregroundStyle(.tertiary)
                    Text("没有找到包含“\(searchQuery)”的历史记录")
                        .font(.system(size: 13, design: .rounded))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(matches) { match in
                            Button {
                                calendarSelection = match.date
                                visibleMonth = calendar.dateInterval(of: .month, for: match.date)?.start ?? match.date
                                searchQuery = ""
                            } label: {
                                VStack(alignment: .leading, spacing: 5) {
                                    HStack {
                                        Text(match.dayKey)
                                            .font(.system(size: 13, weight: .bold, design: .rounded))
                                            .foregroundStyle(accent)
                                        Text(match.date.formatted(.dateTime.weekday(.abbreviated)))
                                            .font(.system(size: 11, design: .rounded))
                                            .foregroundStyle(.secondary)
                                        Spacer()
                                        if match.elapsedSeconds > 0 {
                                            Text(ContentView.formatDuration(match.elapsedSeconds))
                                                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                                                .foregroundStyle(.secondary)
                                        }
                                    }
                                    ForEach(match.snippets, id: \.self) { snippet in
                                        Text(snippet)
                                            .font(.system(size: 12, design: .rounded))
                                            .foregroundStyle(.primary)
                                            .lineLimit(1)
                                    }
                                }
                                .padding(11)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(RoundedRectangle(cornerRadius: 11, style: .continuous).fill(Color.secondary.opacity(0.07)))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
        .padding(20)
    }

    private var monthHeader: some View {
        HStack {
            Button { changeMonth(by: -1) } label: { Image(systemName: "chevron.left") }
                .buttonStyle(.borderless)

            Spacer()

            VStack(spacing: 2) {
                HStack(spacing: 8) {
                    Text(visibleMonth.formatted(.dateTime.year().month(.wide)))
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                    if !isShowingCurrentMonth {
                        Button("回到今天") {
                            let today = Date()
                            calendarSelection = today
                            visibleMonth = calendar.dateInterval(of: .month, for: today)?.start ?? today
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.mini)
                    }
                }
                if !ChinaCalendar.hasOfficialSchedule(for: calendar.component(.year, from: visibleMonth)) {
                    Text("该年度暂无官方放假安排")
                        .font(.system(size: 9, weight: .medium, design: .rounded))
                        .foregroundStyle(.orange)
                }
            }

            Spacer()

            Button { changeMonth(by: 1) } label: { Image(systemName: "chevron.right") }
                .buttonStyle(.borderless)
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
        let isFuture = calendar.startOfDay(for: date) > calendar.startOfDay(for: Date())
        let taskCount = store.tasks(on: date).count
        let hasActivity = store.hasActivity(on: date)
        let hasNote = store.hasNote(on: date)
        let achievement = StudyGoal.percent(elapsedSeconds: store.totalElapsed(on: date), goalMinutes: store.goalMinutes(on: date))
        let holiday = ChinaCalendar.officialHoliday(for: date)
        let festival = ChinaCalendar.traditionalFestival(for: date)
        let tags = store.tags(on: date)
        let dayKey = TaskStore.dayKey(for: date)
        let hasCountdown = store.countdowns.contains { $0.targetDayKey == dayKey }
        let lunar = festival ?? ChinaCalendar.lunarText(for: date)

        return Button {
            calendarSelection = date
        } label: {
            VStack(spacing: 1) {
                HStack(spacing: 2) {
                    Text("\(calendar.component(.day, from: date))")
                        .font(.system(size: 13, weight: isToday ? .bold : .medium, design: .rounded))
                    if hasCountdown {
                        Image(systemName: "flag.fill")
                            .font(.system(size: 7))
                            .foregroundStyle(isSelected ? .white : accent)
                    } else if hasNote {
                        Image(systemName: "doc.text.fill")
                            .font(.system(size: 7))
                            .foregroundStyle(isSelected ? .white.opacity(0.85) : Color.secondary)
                    }
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
                    if taskCount > 0 && !isFuture {
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
            .foregroundStyle(isSelected ? Color.white : (isFuture ? Color.primary.opacity(0.68) : Color.primary))
            .frame(maxWidth: .infinity, minHeight: 56)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(isSelected ? accent : (isToday ? accent.opacity(0.09) : Color.clear))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(isToday && !isSelected ? accent.opacity(0.45) : (hasCountdown && !isSelected ? accent.opacity(0.28) : Color.clear), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button("编辑这一天的标签") {
                calendarSelection = date
                showingTagEditor = true
            }
            if calendar.startOfDay(for: date) >= calendar.startOfDay(for: Date()) {
                Button("设为首页倒计时") {
                    calendarSelection = date
                    countdownTitleDraft = store.tags(on: date).first?.title ?? ""
                    showingCountdownPopover = true
                }
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
                Image(systemName: "doc.text.fill").font(.system(size: 7))
                Text("随记")
            }
            HStack(spacing: 4) {
                Image(systemName: "flag.fill").font(.system(size: 7)).foregroundStyle(accent)
                Text("倒计时")
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
        let isFuture = calendar.startOfDay(for: calendarSelection) > calendar.startOfDay(for: Date())
        let dayKey = TaskStore.dayKey(for: calendarSelection)
        let dayCountdowns = store.countdowns.filter { $0.targetDayKey == dayKey }
        let noteBinding = Binding<String>(
            get: { store.note(on: calendarSelection) },
            set: { store.setNote($0, on: calendarSelection) }
        )

        return VStack(alignment: .leading, spacing: 11) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(calendarSelection.formatted(.dateTime.month(.wide).day()))
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                    if isFuture {
                        badge("未来日期", color: .blue)
                    }
                }
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

            if calendar.startOfDay(for: calendarSelection) >= calendar.startOfDay(for: Date()) {
                Button {
                    countdownTitleDraft = tags.first?.title ?? ""
                    showingCountdownPopover = true
                } label: {
                    Label(dayCountdowns.isEmpty ? "设为首页倒计时" : "添加倒计时", systemImage: "flag.badge.ellipsis")
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .popover(isPresented: $showingCountdownPopover, arrowEdge: .trailing) {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("添加首页倒计时")
                            .font(.system(size: 14, weight: .bold, design: .rounded))
                        TextField("例如：考研初试", text: $countdownTitleDraft)
                            .textFieldStyle(.roundedBorder)
                        HStack {
                            Button("取消") { showingCountdownPopover = false }
                            Spacer()
                            Button("添加") {
                                store.addCountdown(title: countdownTitleDraft, targetDate: calendarSelection)
                                showingCountdownPopover = false
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(accent)
                            .disabled(countdownTitleDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        }
                    }
                    .padding(14)
                    .frame(width: 240)
                }
            }

            if !dayCountdowns.isEmpty {
                FlowLayout(spacing: 5) {
                    ForEach(dayCountdowns) { event in
                        badge("🎯 \(event.title)", color: accent)
                    }
                }
            }

            VStack(alignment: .leading, spacing: 6) {
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

            VStack(alignment: .leading, spacing: 5) {
                Text("当日随记")
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                TextEditor(text: noteBinding)
                    .font(.system(size: 11.5, design: .rounded))
                    .frame(height: 58)
                    .padding(4)
                    .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.secondary.opacity(0.08)))
            }

            Divider()

            if tasks.isEmpty {
                Text(isFuture ? "可以打开这一天提前规划任务" : "这一天没有任务记录")
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
                                    HStack(spacing: 5) {
                                        Text(task.title)
                                            .font(.system(size: 12, weight: .medium, design: .rounded))
                                            .lineLimit(2)
                                        if let cat = store.category(for: task.categoryID) {
                                            let catColor = CalendarTagPalette.color(named: cat.colorName)
                                            Text(cat.name)
                                                .font(.system(size: 8.5, weight: .bold, design: .rounded))
                                                .foregroundStyle(catColor)
                                                .padding(.horizontal, 5)
                                                .padding(.vertical, 1.5)
                                                .background(Capsule().fill(catColor.opacity(0.12)))
                                        }
                                    }
                                    let liveElapsed = store.elapsed(for: task, on: calendarSelection, at: Date())
                                    if liveElapsed > 0 {
                                        Text(ContentView.formatDuration(liveElapsed))
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
        .padding(18)
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
