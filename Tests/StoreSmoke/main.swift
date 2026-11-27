import Foundation

@main
struct StoreSmokeTest {
    static func main() async {
        await MainActor.run {
            let suiteName = "DayNote.StoreSmoke.\(UUID().uuidString)"
            guard let defaults = UserDefaults(suiteName: suiteName) else {
                fatalError("Cannot create isolated defaults suite")
            }
            defer { defaults.removePersistentDomain(forName: suiteName) }

            let store = TaskStore(defaults: defaults)
            let today = Date()
            let history = Calendar.autoupdatingCurrent.date(byAdding: .day, value: -2, to: today)!

            store.addTask(title: "历史任务", on: history)
            let historicalTask = store.tasks(on: history)[0]
            store.updateTask(
                id: historicalTask.id,
                on: history,
                title: "历史任务",
                isCompleted: true,
                elapsedSeconds: 5_400,
                at: today
            )

            store.addTask(title: "任务 A", on: today)
            store.addTask(title: "任务 B", on: today)
            let todayTasks = store.tasks(on: today)
            store.toggleTimer(for: todayTasks[0].id, on: today, at: today)
            store.toggleTimer(for: todayTasks[1].id, on: today, at: today.addingTimeInterval(65))

            precondition(store.completedCount(on: history) == 1)
            precondition(abs(store.totalElapsed(on: history, at: today) - 5_400) < 0.1)
            precondition(abs(store.tasks(on: today)[0].elapsedSeconds - 65) < 0.1)

            let reloaded = TaskStore(defaults: defaults)
            precondition(reloaded.tasks(on: history).count == 1)
            precondition(reloaded.dayStats(inMonthContaining: history, at: today).contains { $0.completedCount == 1 })
            precondition(StudyGoal.percent(elapsedSeconds: 4 * 3_600, goalMinutes: 8 * 60) == 50)
            precondition(StudyGoal.percent(elapsedSeconds: 10 * 3_600, goalMinutes: 8 * 60) == 100)

            let dateFormatter = DateFormatter()
            dateFormatter.dateFormat = "yyyy-MM-dd"
            dateFormatter.timeZone = TimeZone(identifier: "Asia/Shanghai")
            let nationalDay = dateFormatter.date(from: "2026-10-01")!
            let adjustedWorkday = dateFormatter.date(from: "2026-10-10")!
            precondition(ChinaCalendar.officialHoliday(for: nationalDay)?.badge == "休")
            precondition(ChinaCalendar.officialHoliday(for: adjustedWorkday)?.badge == "班")
            precondition(ChinaCalendar.lunarText(for: nationalDay).isEmpty == false)

            store.addTag(title: "模拟考试", colorName: "purple", on: history)
            precondition(store.tags(on: history).first?.title == "模拟考试")
            let tagReloaded = TaskStore(defaults: defaults)
            precondition(tagReloaded.tags(on: history).first?.colorName == "purple")

            let tomorrow = Calendar.autoupdatingCurrent.date(byAdding: .day, value: 1, to: today)!
            store.setGoalMinutes(360, on: today)
            store.setGoalMinutes(600, on: tomorrow)
            precondition(store.goalMinutes(on: today) == 360)
            precondition(store.goalMinutes(on: tomorrow) == 600)
            let goalsReloaded = TaskStore(defaults: defaults)
            precondition(goalsReloaded.goalMinutes(on: today) == 360)
            precondition(goalsReloaded.goalMinutes(on: tomorrow) == 600)
            print("Store smoke tests passed")
        }
    }
}
