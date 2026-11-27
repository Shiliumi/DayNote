import SwiftUI

enum StudyGoal {
    static let defaultsKey = "daynote.daily-goal-minutes"
    static let defaultMinutes = 8 * 60

    static func rate(elapsedSeconds: TimeInterval, goalMinutes: Int) -> Double {
        let goalSeconds = TimeInterval(max(1, goalMinutes) * 60)
        return min(1, max(0, elapsedSeconds) / goalSeconds)
    }

    static func percent(elapsedSeconds: TimeInterval, goalMinutes: Int) -> Int {
        Int((rate(elapsedSeconds: elapsedSeconds, goalMinutes: goalMinutes) * 100).rounded())
    }

    static func durationLabel(minutes: Int) -> String {
        let safeMinutes = max(0, minutes)
        let hours = safeMinutes / 60
        let remainingMinutes = safeMinutes % 60
        if remainingMinutes == 0 { return "\(hours)小时" }
        if hours == 0 { return "\(remainingMinutes)分钟" }
        return "\(hours)小时\(remainingMinutes)分"
    }

    static func compactDurationLabel(minutes: Int) -> String {
        let safeMinutes = max(0, minutes)
        let hours = safeMinutes / 60
        let remainingMinutes = safeMinutes % 60
        if remainingMinutes == 0 { return "\(hours)h" }
        return "\(hours)h\(remainingMinutes)m"
    }
}

struct StudyGoalEditor: View {
    @Binding var goalMinutes: Int
    let date: Date
    let accent: Color

    private let presets = [240, 360, 480, 600]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 3) {
                Text("当天学习目标")
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                Text(date.formatted(.dateTime.year().month().day().weekday(.wide)))
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
                Text("仅影响这一天，其他日期保持不变")
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .foregroundStyle(.tertiary)
            }

            Stepper(value: $goalMinutes, in: 30...(24 * 60), step: 30) {
                Text(StudyGoal.durationLabel(minutes: goalMinutes))
                    .font(.system(size: 17, weight: .bold, design: .rounded))
            }

            HStack(spacing: 6) {
                ForEach(presets, id: \.self) { minutes in
                    Button(StudyGoal.durationLabel(minutes: minutes)) {
                        goalMinutes = minutes
                    }
                    .buttonStyle(.bordered)
                    .tint(goalMinutes == minutes ? accent : .secondary)
                }
            }
        }
        .padding(16)
        .frame(width: 310)
    }
}
