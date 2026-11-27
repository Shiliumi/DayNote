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

            // 1. Verify backward compatibility with v2.3.1 DailyTask JSON (no isRecurring key)
            let legacyTaskJSON = #"{"id":"11111111-1111-1111-1111-111111111111","title":"旧版任务","isCompleted":false,"elapsedSeconds":120}"#
            let decodedLegacy = try! JSONDecoder().decode(DailyTask.self, from: Data(legacyTaskJSON.utf8))
            precondition(decodedLegacy.isRecurring == true)
            precondition(decodedLegacy.elapsedSeconds == 120)

            let store = TaskStore(defaults: defaults)
            let today = Date()
            let yesterday = Calendar.autoupdatingCurrent.date(byAdding: .day, value: -1, to: today)!
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

            // 2. Recurring vs one-off task rollover
            store.addTask(title: "每日固定", on: yesterday, isRecurring: true)
            store.addTask(title: "仅昨日临时", on: yesterday, isRecurring: false)
            store.updateTask(
                id: store.tasks(on: yesterday)[0].id,
                on: yesterday,
                title: "每日固定",
                isCompleted: true,
                elapsedSeconds: 1_800,
                at: today
            )

            let nextWeekDay = Calendar.autoupdatingCurrent.date(byAdding: .day, value: 3, to: today)!
            store.addTask(title: "任务 A", on: today, isRecurring: true)
            store.addTask(title: "任务 B", on: today, isRecurring: false)
            let todayTasks = store.tasks(on: today)
            store.toggleTimer(for: todayTasks[0].id, on: today, at: today)
            store.toggleTimer(for: todayTasks[1].id, on: today, at: today.addingTimeInterval(65))

            precondition(store.completedCount(on: history) == 1)
            precondition(abs(store.totalElapsed(on: history, at: today) - 5_400) < 0.1)
            precondition(abs(store.tasks(on: today)[0].elapsedSeconds - 65) < 0.1)

            // 3. Inline rename, drag reorder, quick duration adjustment
            let taskA = store.tasks(on: today)[0]
            let taskB = store.tasks(on: today)[1]
            store.renameTask(id: taskA.id, on: today, title: "任务 A-改")
            precondition(store.tasks(on: today)[0].title == "任务 A-改")
            store.moveTask(draggedID: taskB.id, targetID: taskA.id, on: today)
            precondition(store.tasks(on: today)[0].id == taskB.id)
            store.adjustTaskDuration(id: taskA.id, on: today, deltaSeconds: 900, at: today)
            precondition(abs(store.tasks(on: today).first(where: { $0.id == taskA.id })!.elapsedSeconds - 965) < 0.1)

            // 4. Sleep away-time deduction
            store.deductAwayTime(taskID: taskA.id, dayKey: TaskStore.dayKey(for: today), seconds: 300, pauseTimer: true, at: today)
            precondition(abs(store.tasks(on: today).first(where: { $0.id == taskA.id })!.elapsedSeconds - 665) < 0.1)

            // 5. Rollover into a fresh future day carries ONLY recurring tasks
            store.prepareForCurrentDay(at: nextWeekDay)
            let futureTitles = store.tasks(on: nextWeekDay).map(\.title)
            precondition(futureTitles.contains("任务 A-改"))
            precondition(!futureTitles.contains("任务 B"))

            // 6. Streaks & Weekly stats
            precondition(store.currentStreak(at: today) >= 3)
            precondition(store.bestStreak(at: today) >= 3)
            precondition(store.weeklyStats(containing: today, at: today).count == 7)

            // 7. Reload persistence & StudyGoal
            let reloaded = TaskStore(defaults: defaults)
            precondition(reloaded.tasks(on: history).count == 1)
            precondition(reloaded.dayStats(inMonthContaining: history, at: today).contains { $0.completedCount == 1 })
            precondition(StudyGoal.percent(elapsedSeconds: 4 * 3_600, goalMinutes: 8 * 60) == 50)
            precondition(StudyGoal.percent(elapsedSeconds: 10 * 3_600, goalMinutes: 8 * 60) == 100)

            // 8. ChinaCalendar 2026 & 2027 official schedules
            let dateFormatter = DateFormatter()
            dateFormatter.dateFormat = "yyyy-MM-dd"
            dateFormatter.timeZone = TimeZone(identifier: "Asia/Shanghai")
            let nationalDay2026 = dateFormatter.date(from: "2026-10-01")!
            let adjustedWorkday2026 = dateFormatter.date(from: "2026-10-10")!
            let springFestival2027 = dateFormatter.date(from: "2027-02-05")!
            let springWorkday2027 = dateFormatter.date(from: "2027-01-31")!
            let laborDayEnd2027 = dateFormatter.date(from: "2027-05-05")!
            let laborWorkday2027 = dateFormatter.date(from: "2027-05-08")!
            precondition(ChinaCalendar.officialHoliday(for: nationalDay2026)?.badge == "休")
            precondition(ChinaCalendar.officialHoliday(for: adjustedWorkday2026)?.badge == "班")
            precondition(ChinaCalendar.officialHoliday(for: springFestival2027)?.badge == "休")
            precondition(ChinaCalendar.officialHoliday(for: springWorkday2027)?.badge == "班")
            precondition(ChinaCalendar.officialHoliday(for: laborDayEnd2027)?.badge == "休")
            precondition(ChinaCalendar.officialHoliday(for: laborWorkday2027)?.badge == "班")
            precondition(ChinaCalendar.hasOfficialSchedule(for: 2027))
            precondition(ChinaCalendar.lunarText(for: nationalDay2026).isEmpty == false)

            // 9. Tags, Goals, Countdowns
            store.addTag(title: "模拟考试", colorName: "purple", on: history)
            precondition(store.tags(on: history).first?.title == "模拟考试")
            let tagReloaded = TaskStore(defaults: defaults)
            precondition(tagReloaded.tags(on: history).first?.colorName == "purple")

            let tomorrow = Calendar.autoupdatingCurrent.date(byAdding: .day, value: 1, to: today)!
            store.setGoalMinutes(360, on: today)
            store.setGoalMinutes(600, on: tomorrow)
            precondition(store.goalMinutes(on: today) == 360)
            precondition(store.goalMinutes(on: tomorrow) == 600)

            let examDay = Calendar.autoupdatingCurrent.date(byAdding: .day, value: 20, to: today)!
            store.addCountdown(title: "考研初试", targetDate: examDay)
            precondition(store.upcomingCountdowns(from: today).first?.daysRemaining == 20)

            // 9.5 Daily Notes, Task Templates, Pomodoros, History Search, 12-week Heatmap
            store.setNote("今天408数据结构错题整理完成", on: history)
            precondition(store.hasNote(on: history))
            store.incrementPomodoro(on: today)
            precondition(store.pomodoroCount(on: today) == 1)

            store.saveDayAsTemplate(name: "冲刺日", from: today)
            precondition(store.taskTemplates.count == 1)
            let planDay = Calendar.autoupdatingCurrent.date(byAdding: .day, value: 7, to: today)!
            store.applyTemplate(store.taskTemplates[0], to: planDay, replaceExisting: true)
            precondition(store.tasks(on: planDay).count == store.tasks(on: today).count)

            let noteMatches = store.searchHistory(query: "数据结构", at: today)
            precondition(noteMatches.contains { $0.dayKey == TaskStore.dayKey(for: history) })
            let tagMatches = store.searchHistory(query: "模拟考试", at: today)
            precondition(tagMatches.contains { $0.dayKey == TaskStore.dayKey(for: history) })

            let heatmap = store.heatmapStats(weeks: 12, endingAt: today, at: today)
            precondition(heatmap.count == 12 && heatmap.allSatisfy { $0.count == 7 })

            // 9.6 Custom Categories, Bulk Categorize, Category Stats & Rollover Preservation
            let catAlpha = store.addCategory(name: "核心课", colorName: "blue")!
            let catBeta = store.addCategory(name: "练习", colorName: "green")!
            store.applyCategoryToAllTasksNamed("任务 A-改", categoryID: catAlpha.id)
            store.applyCategoryToAllTasksNamed("历史任务", categoryID: catBeta.id)
            let catStats = store.categoryTimeStatsAllTime(at: today)
            precondition(catStats.contains { $0.name == "核心课" && $0.seconds > 0 })
            precondition(catStats.contains { $0.name == "练习" && $0.seconds >= 5_400 })
            let catSearch = store.searchHistory(query: "核心课", at: today)
            precondition(!catSearch.isEmpty)

            // 10. Full JSON backup round-trip & CSV export
            let jsonData = try! store.exportJSONData(at: today)
            let csv = store.exportCSVString(at: today)
            precondition(csv.contains("任务 A-改"))
            precondition(csv.contains("模拟考试"))
            precondition(csv.contains("数据结构"))
            precondition(csv.contains("核心课"))

            let suite2 = "DayNote.StoreSmoke.Restore.\(UUID().uuidString)"
            let defaults2 = UserDefaults(suiteName: suite2)!
            defer { defaults2.removePersistentDomain(forName: suite2) }
            let restored = TaskStore(defaults: defaults2)
            try! restored.importBackup(from: jsonData)
            precondition(restored.goalMinutes(on: today) == 360)
            precondition(restored.tags(on: history).first?.title == "模拟考试")
            precondition(restored.upcomingCountdowns(from: today).first?.event.title == "考研初试")
            precondition(restored.note(on: history).contains("数据结构"))
            precondition(restored.taskTemplates.first?.name == "冲刺日")
            precondition(restored.pomodoroCount(on: today) == 1)
            precondition(restored.categories.count == 2)
            restored.deleteCategory(id: catBeta.id)
            precondition(restored.tasks(on: history).first?.categoryID == nil)

            print("Store smoke tests passed (all v3.2 checks)")
        }
    }
}
