import Charts
import SwiftUI

struct MonthlyStatisticsView: View {
    enum Period: String, CaseIterable, Identifiable {
        case week = "本周"
        case month = "本月"
        case all = "全部累计"
        var id: String { rawValue }
    }

    @ObservedObject var store: TaskStore
    let accent: Color

    @Environment(\.dismiss) private var dismiss
    @State private var period: Period = .month
    @State private var visibleMonth: Date
    @State private var visibleWeekDate: Date
    @State private var selectedX: Int?
    @State private var selectedCategoryFilterID: String?
    @State private var hoveredHeatmapDay: DayStats?
    private let calendar = Calendar.autoupdatingCurrent

    init(store: TaskStore, initialMonth: Date, accent: Color) {
        self.store = store
        self.accent = accent
        _visibleMonth = State(initialValue: Calendar.autoupdatingCurrent.dateInterval(of: .month, for: initialMonth)?.start ?? initialMonth)
        _visibleWeekDate = State(initialValue: initialMonth)
    }

    var body: some View {
        let stats: [DayStats] = {
            switch period {
            case .week: return store.weeklyStats(containing: visibleWeekDate)
            case .month: return store.dayStats(inMonthContaining: visibleMonth)
            case .all: return store.allTimeDayStats()
            }
        }()
        let totalSeconds = stats.reduce(0) { $0 + $1.elapsedSeconds }
        let elapsedDayCount = period == .all ? max(1, stats.count) : elapsedDaysCount(for: stats)
        let relevantStats = period == .all ? stats : Array(stats.prefix(elapsedDayCount))
        let targetSeconds = relevantStats.reduce(0.0) { total, stat in
            total + TimeInterval(store.goalMinutes(on: stat.date) * 60)
        }
        let rate = targetSeconds > 0 ? min(1, totalSeconds / targetSeconds) : 0
        let studyDays = stats.lazy.filter { $0.elapsedSeconds > 0 }.count
        let categoryStats: [CategoryTimeStat] = {
            switch period {
            case .week: return store.categoryTimeStats(inWeekContaining: visibleWeekDate)
            case .month: return store.categoryTimeStats(inMonthContaining: visibleMonth)
            case .all: return store.categoryTimeStatsAllTime()
            }
        }()
        let allTaskTotals: [TaskTimeTotal] = {
            switch period {
            case .week: return store.taskTimeTotals(inWeekContaining: visibleWeekDate)
            case .month: return store.taskTimeTotals(inMonthContaining: visibleMonth)
            case .all: return store.taskTimeTotalsAllTime()
            }
        }()
        let filteredCategory = categoryStats.first { $0.id == selectedCategoryFilterID }
        let displayedTasks = filteredCategory?.tasks ?? allTaskTotals
        let streak = store.currentStreak()
        let bestStreak = store.bestStreak()
        let totalPomodoros = stats.reduce(0) { $0 + store.pomodoroCount(on: $1.date) }

        return VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text(period == .month ? "月度统计" : (period == .week ? "本周统计" : "全部累计统计"))
                        .font(.system(size: 24, weight: .bold, design: .rounded))
                    Text("分类时长占比 · 每日趋势 · 12 周热力图")
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Picker("", selection: $period) {
                    ForEach(Period.allCases) { p in
                        Text(p.rawValue).tag(p)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 225)
                .onChange(of: period) {
                    selectedX = nil
                    selectedCategoryFilterID = nil
                }

                Button("完成") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                    .padding(.leading, 8)
            }
            .padding(22)

            Divider()

            ScrollView {
                VStack(spacing: 18) {
                    if period != .all {
                        periodHeader
                    }

                    HStack(spacing: 10) {
                        metricCard(
                            title: "总专注",
                            value: longDuration(totalSeconds),
                            subtitle: totalPomodoros > 0 ? "🍅 \(totalPomodoros) 个番茄" : nil,
                            icon: "timer"
                        )
                        metricCard(
                            title: period == .month ? "月达成率" : (period == .week ? "周达成率" : "累计达成率"),
                            value: "\(Int((rate * 100).rounded()))%",
                            subtitle: nil,
                            icon: "target"
                        )
                        metricCard(
                            title: "学习天数",
                            value: period == .all ? "\(studyDays) 天" : "\(studyDays)/\(max(1, elapsedDayCount)) 天",
                            subtitle: nil,
                            icon: "calendar.badge.checkmark"
                        )
                        metricCard(
                            title: "连续打卡",
                            value: "\(streak) 天",
                            subtitle: "最长 \(bestStreak) 天",
                            icon: "flame.fill"
                        )
                    }

                    categoryBreakdownSection(categoryStats: categoryStats, totalSeconds: totalSeconds)

                    if period != .all {
                        chartSection(stats: stats)
                    }

                    heatmapSection

                    taskRankingSection(
                        tasks: displayedTasks,
                        activeFilterName: filteredCategory?.name
                    )
                }
                .padding(22)
            }
        }
        .frame(width: 770, height: 690)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    // MARK: - Category Breakdown (Donut + Interactive Bars)

    private func categoryBreakdownSection(categoryStats: [CategoryTimeStat], totalSeconds: TimeInterval) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("分类时长分布")
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                Spacer()
                if selectedCategoryFilterID != nil {
                    Button("显示全部分类") {
                        selectedCategoryFilterID = nil
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.mini)
                } else if !categoryStats.isEmpty {
                    Text("点击任意分类可筛选下方任务明细")
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundStyle(.tertiary)
                }
            }

            if categoryStats.isEmpty {
                Text("当前时段还没有计时记录")
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 80)
            } else {
                HStack(alignment: .center, spacing: 24) {
                    ZStack {
                        Chart(categoryStats) { item in
                            SectorMark(
                                angle: .value("时长", item.seconds),
                                innerRadius: .ratio(0.60),
                                angularInset: 2
                            )
                            .cornerRadius(4)
                            .foregroundStyle(CalendarTagPalette.color(named: item.colorName))
                            .opacity(selectedCategoryFilterID == nil || selectedCategoryFilterID == item.id ? 1.0 : 0.30)
                        }
                        .frame(width: 144, height: 144)

                        VStack(spacing: 1) {
                            Text(shortHours(totalSeconds))
                                .font(.system(size: 16, weight: .bold, design: .rounded))
                                .monospacedDigit()
                            Text("总计")
                                .font(.system(size: 10, weight: .medium, design: .rounded))
                                .foregroundStyle(.secondary)
                        }
                    }

                    VStack(spacing: 10) {
                        ForEach(categoryStats) { item in
                            let color = CalendarTagPalette.color(named: item.colorName)
                            let isSelected = selectedCategoryFilterID == item.id
                            let pct = Int((item.share * 100).rounded())

                            Button {
                                withAnimation(.easeInOut(duration: 0.16)) {
                                    selectedCategoryFilterID = isSelected ? nil : item.id
                                }
                            } label: {
                                VStack(spacing: 5) {
                                    HStack(spacing: 8) {
                                        Circle()
                                            .fill(color)
                                            .frame(width: 9, height: 9)
                                        Text(item.name)
                                            .font(.system(size: 13, weight: isSelected ? .bold : .semibold, design: .rounded))
                                            .foregroundStyle(.primary)
                                        Text("\(item.tasks.count) 项")
                                            .font(.system(size: 10, weight: .medium, design: .rounded))
                                            .foregroundStyle(.tertiary)
                                        Spacer()
                                        Text("\(pct)%")
                                            .font(.system(size: 12, weight: .bold, design: .rounded))
                                            .foregroundStyle(color)
                                            .monospacedDigit()
                                        Text(longDuration(item.seconds))
                                            .font(.system(size: 12, weight: .semibold, design: .monospaced))
                                            .foregroundStyle(.secondary)
                                            .frame(minWidth: 78, alignment: .trailing)
                                    }

                                    GeometryReader { geo in
                                        ZStack(alignment: .leading) {
                                            Capsule().fill(Color.secondary.opacity(0.12))
                                            Capsule()
                                                .fill(color)
                                                .frame(width: max(4, geo.size.width * item.share))
                                        }
                                    }
                                    .frame(height: 5)
                                }
                                .padding(.horizontal, 10)
                                .padding(.vertical, 7)
                                .background(
                                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                                        .fill(isSelected ? color.opacity(0.11) : Color.clear)
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                                        .stroke(isSelected ? color.opacity(0.45) : Color.clear, lineWidth: 1)
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .frame(maxWidth: .infinity)
                }
            }
        }
        .statSection()
    }

    // MARK: - Task Ranking

    private func taskRankingSection(tasks: [TaskTimeTotal], activeFilterName: String?) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(activeFilterName.map { "「\($0)」任务时长明细" } ?? "任务时长排行")
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                Spacer()
                if activeFilterName != nil {
                    Button("返回全部排行") {
                        selectedCategoryFilterID = nil
                    }
                    .buttonStyle(.borderless)
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(accent)
                }
            }

            if tasks.isEmpty {
                Text("当前时段还没有计时记录")
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 60)
            } else {
                ForEach(Array(tasks.prefix(12).enumerated()), id: \.element.id) { index, item in
                    let cat = store.category(for: item.categoryID)
                    let catColor = cat.map { CalendarTagPalette.color(named: $0.colorName) } ?? .secondary
                    HStack(spacing: 10) {
                        Text("\(index + 1)")
                            .font(.system(size: 11, weight: .bold, design: .rounded))
                            .foregroundStyle(index == 0 ? Color.white : accent)
                            .frame(width: 24, height: 24)
                            .background(Circle().fill(index == 0 ? accent : accent.opacity(0.1)))
                        Text(item.title)
                            .font(.system(size: 13, weight: .medium, design: .rounded))
                            .lineLimit(1)
                        if let cat, activeFilterName == nil {
                            Text(cat.name)
                                .font(.system(size: 9.5, weight: .bold, design: .rounded))
                                .foregroundStyle(catColor)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Capsule().fill(catColor.opacity(0.12)))
                        }
                        Spacer()
                        Text(longDuration(item.seconds))
                            .font(.system(size: 12, weight: .semibold, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .statSection()
    }

    // MARK: - 12-Week Study Heatmap

    private var heatmapSection: some View {
        let columns = store.heatmapStats(weeks: 12)
        let todayStart = calendar.startOfDay(for: Date())
        let weekdayLabels = ["一", "", "三", "", "五", "", "日"]

        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("近 12 周学习热力图")
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                Spacer()
                if let hovered = hoveredHeatmapDay {
                    let goalMin = store.goalMinutes(on: hovered.date)
                    let pct = StudyGoal.percent(elapsedSeconds: hovered.elapsedSeconds, goalMinutes: goalMin)
                    Text("\(hovered.date.formatted(.dateTime.month().day())) · 专注 \(longDuration(hovered.elapsedSeconds)) · 达成 \(pct)%")
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundStyle(accent)
                } else {
                    HStack(spacing: 4) {
                        Text("少").font(.system(size: 9.5)).foregroundStyle(.secondary)
                        ForEach([0.0, 0.25, 0.5, 0.75, 1.0], id: \.self) { level in
                            RoundedRectangle(cornerRadius: 3)
                                .fill(heatmapColor(rate: level, hasActivity: level > 0))
                                .frame(width: 11, height: 11)
                        }
                        Text("多").font(.system(size: 9.5)).foregroundStyle(.secondary)
                    }
                }
            }

            HStack(alignment: .top, spacing: 6) {
                VStack(spacing: 4) {
                    ForEach(0..<7, id: \.self) { row in
                        Text(weekdayLabels[row])
                            .font(.system(size: 9, weight: .medium, design: .rounded))
                            .foregroundStyle(.secondary)
                            .frame(width: 14, height: 14)
                    }
                }

                HStack(spacing: 5) {
                    ForEach(Array(columns.enumerated()), id: \.offset) { _, week in
                        VStack(spacing: 4) {
                            ForEach(week) { day in
                                let isFuture = calendar.startOfDay(for: day.date) > todayStart
                                let rate = StudyGoal.rate(elapsedSeconds: day.elapsedSeconds, goalMinutes: store.goalMinutes(on: day.date))
                                RoundedRectangle(cornerRadius: 3.5, style: .continuous)
                                    .fill(isFuture ? Color.clear : heatmapColor(rate: rate, hasActivity: day.hasActivity))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 3.5, style: .continuous)
                                            .stroke(
                                                hoveredHeatmapDay?.id == day.id ? accent : Color.clear,
                                                lineWidth: 1.2
                                            )
                                    )
                                    .frame(maxWidth: .infinity)
                                    .frame(height: 14)
                                    .onHover { inside in
                                        if inside && !isFuture {
                                            hoveredHeatmapDay = day
                                        } else if !inside && hoveredHeatmapDay?.id == day.id {
                                            hoveredHeatmapDay = nil
                                        }
                                    }
                            }
                        }
                    }
                }
            }
        }
        .statSection()
    }

    private func heatmapColor(rate: Double, hasActivity: Bool) -> Color {
        guard hasActivity else { return Color.secondary.opacity(0.11) }
        switch rate {
        case ..<0.25: return accent.opacity(0.24)
        case ..<0.55: return accent.opacity(0.46)
        case ..<0.85: return accent.opacity(0.72)
        default: return accent
        }
    }

    private func chartSection(stats: [DayStats]) -> some View {
        let selectedStat: DayStats? = {
            guard let selectedX else { return nil }
            if period == .month {
                return stats.first { calendar.component(.day, from: $0.date) == selectedX }
            } else {
                let idx = selectedX - 1
                return stats.indices.contains(idx) ? stats[idx] : nil
            }
        }()

        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("每天专注时长")
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                Spacer()
                if let stat = selectedStat {
                    let goalMin = store.goalMinutes(on: stat.date)
                    let pct = StudyGoal.percent(elapsedSeconds: stat.elapsedSeconds, goalMinutes: goalMin)
                    HStack(spacing: 8) {
                        Text(stat.date.formatted(.dateTime.month().day().weekday(.abbreviated)))
                            .fontWeight(.bold)
                        Text("专注 \(longDuration(stat.elapsedSeconds))")
                            .foregroundStyle(accent)
                        Text("目标 \(StudyGoal.durationLabel(minutes: goalMin))")
                            .foregroundStyle(.blue)
                        Text("达成 \(pct)%")
                            .foregroundStyle(.secondary)
                    }
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(Capsule().fill(accent.opacity(0.10)))
                } else {
                    Text("点击或拖动柱子查看当天精确时长")
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundStyle(.tertiary)
                }
            }

            Chart {
                ForEach(Array(stats.enumerated()), id: \.element.id) { idx, stat in
                    let xVal = period == .month ? calendar.component(.day, from: stat.date) : (idx + 1)
                    let isSelected = selectedX == xVal

                    BarMark(
                        x: .value("日期", xVal),
                        y: .value("小时", stat.elapsedSeconds / 3600)
                    )
                    .foregroundStyle(
                        isSelected
                        ? accent.gradient
                        : (stat.hasActivity ? accent.opacity(0.82).gradient : Color.secondary.opacity(0.15).gradient)
                    )
                    .cornerRadius(4)

                    LineMark(
                        x: .value("日期", xVal),
                        y: .value("当天目标", Double(store.goalMinutes(on: stat.date)) / 60)
                    )
                    .foregroundStyle(Color.blue)
                    .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
                    .symbol {
                        Circle().fill(Color.blue).frame(width: 4, height: 4)
                    }
                }
            }
            .chartXSelection(value: $selectedX)
            .chartXAxis {
                if period == .month {
                    AxisMarks(values: .stride(by: 5))
                } else {
                    AxisMarks(values: [1, 2, 3, 4, 5, 6, 7]) { value in
                        AxisValueLabel {
                            if let i = value.as(Int.self), (1...7).contains(i) {
                                Text(["周一", "周二", "周三", "周四", "周五", "周六", "周日"][i - 1])
                            }
                        }
                    }
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading) {
                    AxisGridLine()
                    AxisValueLabel(format: Decimal.FormatStyle.number.precision(.fractionLength(1)))
                }
            }
            .frame(height: 185)
        }
        .statSection()
    }

    private var periodHeader: some View {
        HStack {
            Button { changePeriod(by: -1) } label: { Image(systemName: "chevron.left") }
                .buttonStyle(.borderless)
            Spacer()
            Text(periodTitle)
                .font(.system(size: 18, weight: .bold, design: .rounded))
            Spacer()
            Label("蓝色虚线：每天独立目标", systemImage: "chart.line.uptrend.xyaxis")
                .font(.system(size: 10, weight: .medium, design: .rounded))
                .foregroundStyle(.blue)

            Button { changePeriod(by: 1) } label: { Image(systemName: "chevron.right") }
                .buttonStyle(.borderless)
                .disabled(isCurrentPeriod)
        }
    }

    private var periodTitle: String {
        if period == .month {
            return visibleMonth.formatted(.dateTime.year().month(.wide))
        }
        let stats = store.weeklyStats(containing: visibleWeekDate)
        guard let first = stats.first?.date, let last = stats.last?.date else { return "本周" }
        return "\(first.formatted(.dateTime.month().day())) – \(last.formatted(.dateTime.month().day()))"
    }

    private var isCurrentPeriod: Bool {
        if period == .month {
            return calendar.isDate(visibleMonth, equalTo: Date(), toGranularity: .month)
        }
        var mondayCal = calendar
        mondayCal.firstWeekday = 2
        return mondayCal.isDate(visibleWeekDate, equalTo: Date(), toGranularity: .weekOfYear)
    }

    private func metricCard(title: String, value: String, subtitle: String?, icon: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(accent)
                .frame(width: 32, height: 32)
                .background(Circle().fill(accent.opacity(0.1)))
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)
                Text(value)
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                if let subtitle {
                    Text(subtitle)
                        .font(.system(size: 9, weight: .medium, design: .rounded))
                        .foregroundStyle(.tertiary)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .frame(maxWidth: .infinity)
        .background(RoundedRectangle(cornerRadius: 13, style: .continuous).fill(Color.secondary.opacity(0.07)))
    }

    private func longDuration(_ seconds: TimeInterval) -> String {
        let totalMinutes = max(0, Int(seconds) / 60)
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60
        if hours > 0 { return "\(hours)小时\(minutes)分" }
        return "\(minutes)分钟"
    }

    private func shortHours(_ seconds: TimeInterval) -> String {
        let hours = seconds / 3600.0
        if hours >= 10 {
            return String(format: "%.0fh", hours)
        }
        return String(format: "%.1fh", hours)
    }

    private func changePeriod(by value: Int) {
        selectedX = nil
        if period == .month {
            guard let month = calendar.date(byAdding: .month, value: value, to: visibleMonth) else { return }
            visibleMonth = calendar.dateInterval(of: .month, for: month)?.start ?? month
        } else {
            guard let next = calendar.date(byAdding: .weekOfYear, value: value, to: visibleWeekDate) else { return }
            visibleWeekDate = next
        }
    }

    private func elapsedDaysCount(for stats: [DayStats]) -> Int {
        let todayStart = calendar.startOfDay(for: Date())
        return stats.filter { calendar.startOfDay(for: $0.date) <= todayStart }.count
    }
}

private extension View {
    func statSection() -> some View {
        padding(16)
            .background(
                RoundedRectangle(cornerRadius: 15, style: .continuous)
                    .fill(Color.secondary.opacity(0.055))
            )
    }
}
