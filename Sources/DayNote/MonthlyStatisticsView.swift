import Charts
import SwiftUI

struct MonthlyStatisticsView: View {
    @ObservedObject var store: TaskStore
    let accent: Color

    @Environment(\.dismiss) private var dismiss
    @State private var visibleMonth: Date
    private let calendar = Calendar.autoupdatingCurrent

    init(store: TaskStore, initialMonth: Date, accent: Color) {
        self.store = store
        self.accent = accent
        _visibleMonth = State(initialValue: Calendar.autoupdatingCurrent.dateInterval(of: .month, for: initialMonth)?.start ?? initialMonth)
    }

    var body: some View {
        let stats = store.dayStats(inMonthContaining: visibleMonth)
        let totalSeconds = stats.reduce(0) { $0 + $1.elapsedSeconds }
        let elapsedDayCount = elapsedDaysInVisibleMonth
        let relevantStats = Array(stats.prefix(elapsedDayCount))
        let targetSeconds = relevantStats.reduce(0.0) { total, stat in
            total + TimeInterval(store.goalMinutes(on: stat.date) * 60)
        }
        let monthlyRate = targetSeconds > 0 ? min(1, totalSeconds / targetSeconds) : 0
        let studyDays = stats.lazy.filter { $0.elapsedSeconds > 0 }.count
        let taskTotals = store.taskTimeTotals(inMonthContaining: visibleMonth)

        return VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("月度统计")
                        .font(.system(size: 24, weight: .bold, design: .rounded))
                    Text("专注时长与目标达成情况")
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("完成") { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }
            .padding(24)

            Divider()

            ScrollView {
                VStack(spacing: 20) {
                    monthHeader

                    HStack(spacing: 12) {
                        metricCard(title: "总专注", value: longDuration(totalSeconds), icon: "timer")
                        metricCard(title: "月达成率", value: "\(Int((monthlyRate * 100).rounded()))%", icon: "target")
                        metricCard(title: "学习天数", value: "\(studyDays)/\(elapsedDayCount) 天", icon: "calendar.badge.checkmark")
                    }

                    VStack(alignment: .leading, spacing: 12) {
                        Text("每天专注时长")
                            .font(.system(size: 15, weight: .bold, design: .rounded))

                        Chart {
                            ForEach(stats) { stat in
                                BarMark(
                                    x: .value("日期", calendar.component(.day, from: stat.date)),
                                    y: .value("小时", stat.elapsedSeconds / 3600)
                                )
                                .foregroundStyle(stat.hasActivity ? accent.gradient : Color.secondary.opacity(0.15).gradient)
                                .cornerRadius(3)

                                LineMark(
                                    x: .value("日期", calendar.component(.day, from: stat.date)),
                                    y: .value("当天目标", Double(store.goalMinutes(on: stat.date)) / 60)
                                )
                                .foregroundStyle(Color.blue)
                                .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
                                .symbol {
                                    Circle().fill(Color.blue).frame(width: 4, height: 4)
                                }
                            }
                        }
                        .chartXAxis {
                            AxisMarks(values: .stride(by: 5))
                        }
                        .chartYAxis {
                            AxisMarks(position: .leading) {
                                AxisGridLine()
                                AxisValueLabel(format: Decimal.FormatStyle.number.precision(.fractionLength(1)))
                            }
                        }
                        .frame(height: 190)
                    }
                    .statSection()

                    VStack(alignment: .leading, spacing: 12) {
                        Text("任务时长排行")
                            .font(.system(size: 15, weight: .bold, design: .rounded))

                        if taskTotals.isEmpty {
                            Text("本月还没有计时记录")
                                .font(.system(size: 13, weight: .medium, design: .rounded))
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, minHeight: 70)
                        } else {
                            ForEach(Array(taskTotals.prefix(6).enumerated()), id: \.offset) { index, item in
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
        .frame(width: 700, height: 620)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var monthHeader: some View {
        HStack {
            Button { changeMonth(by: -1) } label: { Image(systemName: "chevron.left") }
                .buttonStyle(.borderless)
            Spacer()
            Text(visibleMonth.formatted(.dateTime.year().month(.wide)))
                .font(.system(size: 19, weight: .bold, design: .rounded))
            Spacer()
            Label("蓝色虚线：每天独立目标", systemImage: "chart.line.uptrend.xyaxis")
                .font(.system(size: 10, weight: .medium, design: .rounded))
                .foregroundStyle(.blue)

            Button { changeMonth(by: 1) } label: { Image(systemName: "chevron.right") }
                .buttonStyle(.borderless)
                .disabled(calendar.isDate(visibleMonth, equalTo: Date(), toGranularity: .month))
        }
    }

    private func metricCard(title: String, value: String, icon: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(accent)
                .frame(width: 36, height: 36)
                .background(Circle().fill(accent.opacity(0.1)))
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)
                Text(value)
                    .font(.system(size: 17, weight: .bold, design: .rounded))
            }
            Spacer(minLength: 0)
        }
        .padding(14)
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

    private func changeMonth(by value: Int) {
        guard let month = calendar.date(byAdding: .month, value: value, to: visibleMonth) else { return }
        visibleMonth = calendar.dateInterval(of: .month, for: month)?.start ?? month
    }

    private var elapsedDaysInVisibleMonth: Int {
        guard
            let interval = calendar.dateInterval(of: .month, for: visibleMonth),
            let range = calendar.range(of: .day, in: .month, for: visibleMonth)
        else { return 0 }

        if calendar.isDate(visibleMonth, equalTo: Date(), toGranularity: .month) {
            return max(1, calendar.dateComponents([.day], from: interval.start, to: Date()).day.map { $0 + 1 } ?? 1)
        }
        if visibleMonth < calendar.startOfDay(for: Date()) {
            return range.count
        }
        return 0
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
