import Charts
import SwiftUI

struct MonthlyStatisticsView: View {
    enum Period: String, CaseIterable, Identifiable {
        case week = "本周统计"
        case month = "月度统计"
        var id: String { rawValue }
    }

    @ObservedObject var store: TaskStore
    let accent: Color

    @Environment(\.dismiss) private var dismiss
    @State private var period: Period = .month
    @State private var visibleMonth: Date
    @State private var visibleWeekDate: Date
    @State private var selectedX: Int?
    private let calendar = Calendar.autoupdatingCurrent

    init(store: TaskStore, initialMonth: Date, accent: Color) {
        self.store = store
        self.accent = accent
        _visibleMonth = State(initialValue: Calendar.autoupdatingCurrent.dateInterval(of: .month, for: initialMonth)?.start ?? initialMonth)
        _visibleWeekDate = State(initialValue: initialMonth)
    }

    var body: some View {
        let stats = period == .month ? store.dayStats(inMonthContaining: visibleMonth) : store.weeklyStats(containing: visibleWeekDate)
        let totalSeconds = stats.reduce(0) { $0 + $1.elapsedSeconds }
        let elapsedDayCount = elapsedDaysCount(for: stats)
        let relevantStats = Array(stats.prefix(elapsedDayCount))
        let targetSeconds = relevantStats.reduce(0.0) { total, stat in
            total + TimeInterval(store.goalMinutes(on: stat.date) * 60)
        }
        let rate = targetSeconds > 0 ? min(1, totalSeconds / targetSeconds) : 0
        let studyDays = stats.lazy.filter { $0.elapsedSeconds > 0 }.count
        let taskTotals = period == .month ? store.taskTimeTotals(inMonthContaining: visibleMonth) : store.taskTimeTotals(inWeekContaining: visibleWeekDate)
        let streak = store.currentStreak()
        let bestStreak = store.bestStreak()

        return VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text(period == .month ? "月度统计" : "本周统计")
                        .font(.system(size: 24, weight: .bold, design: .rounded))
                    Text("专注时长 · 连续打卡 · 柱状图悬停/点击查看详情")
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
                .frame(width: 180)
                .onChange(of: period) { selectedX = nil }

                Button("完成") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                    .padding(.leading, 8)
            }
            .padding(22)

            Divider()

            ScrollView {
                VStack(spacing: 18) {
                    periodHeader

                    HStack(spacing: 10) {
                        metricCard(title: "总专注", value: longDuration(totalSeconds), subtitle: nil, icon: "timer")
                        metricCard(title: period == .month ? "月达成率" : "周达成率", value: "\(Int((rate * 100).rounded()))%", subtitle: nil, icon: "target")
                        metricCard(title: "学习天数", value: "\(studyDays)/\(max(1, elapsedDayCount)) 天", subtitle: nil, icon: "calendar.badge.checkmark")
                        metricCard(title: "连续打卡", value: "\(streak) 天", subtitle: "最长 \(bestStreak) 天", icon: "flame.fill")
                    }

                    chartSection(stats: stats)

                    VStack(alignment: .leading, spacing: 12) {
                        Text("任务时长排行")
                            .font(.system(size: 15, weight: .bold, design: .rounded))

                        if taskTotals.isEmpty {
                            Text(period == .month ? "本月还没有计时记录" : "本周还没有计时记录")
                                .font(.system(size: 13, weight: .medium, design: .rounded))
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, minHeight: 70)
                        } else {
                            ForEach(Array(taskTotals.prefix(8).enumerated()), id: \.offset) { index, item in
                                HStack(spacing: 10) {
                                    Text("\(index + 1)")
                                        .font(.system(size: 11, weight: .bold, design: .rounded))
                                        .foregroundStyle(index == 0 ? Color.white : accent)
                                        .frame(width: 24, height: 24)
                                        .background(Circle().fill(index == 0 ? accent : accent.opacity(0.1)))
                                    Text(item.title)
                                        .font(.system(size: 13, weight: .medium, design: .rounded))
                                        .lineLimit(1)
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
                .padding(22)
            }
        }
        .frame(width: 740, height: 640)
        .background(Color(nsColor: .windowBackgroundColor))
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
            .frame(height: 195)
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
        padding(18)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color.secondary.opacity(0.055))
            )
    }
}
