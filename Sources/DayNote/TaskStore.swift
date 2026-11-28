import Foundation

@MainActor
final class TaskStore: ObservableObject {
    @Published private(set) var days: [String: [DailyTask]] = [:]
    @Published private(set) var activeDayKey: String?
    @Published private(set) var activeTaskID: UUID?
    @Published private(set) var timerStartedAt: Date?
    @Published private(set) var calendarTags: [String: [CalendarTag]] = [:]
    @Published private(set) var dailyGoals: [String: Int] = [:]
    @Published private(set) var countdowns: [CountdownEvent] = []
    @Published private(set) var dailyNotes: [String: String] = [:]
    @Published private(set) var taskTemplates: [TaskTemplate] = []
    @Published private(set) var pomodoroCounts: [String: Int] = [:]
    @Published private(set) var categories: [TaskCategory] = []
    @Published var autoBackupDirectoryPath: String = "" {
        didSet {
            defaults.set(autoBackupDirectoryPath, forKey: autoBackupDirKey)
            if !autoBackupDirectoryPath.isEmpty {
                performAutoBackupIfConfigured()
            }
        }
    }

    private let archiveKey = "daynote.saved-archive.v2"
    private let legacyKey = "daynote.saved-note.v1"
    private let calendarTagsKey = "daynote.calendar-tags.v1"
    private let dailyGoalsKey = "daynote.daily-goals.v1"
    private let countdownsKey = "daynote.countdowns.v1"
    private let dailyNotesKey = "daynote.daily-notes.v1"
    private let taskTemplatesKey = "daynote.task-templates.v1"
    private let pomodoroCountsKey = "daynote.pomodoro-counts.v1"
    private let categoriesKey = "daynote.categories.v1"
    private let rolledOverDaysKey = "daynote.rolled-over-days.v1"
    private let autoBackupDirKey = "daynote.auto-backup-dir"
    private let calendar = Calendar.autoupdatingCurrent
    private let defaults: UserDefaults
    private var lastAutoBackupAt: Date?
    private var lastActiveTaskID: UUID?
    private var rolledOverDayKeys: Set<String> = []

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.autoBackupDirectoryPath = defaults.string(forKey: autoBackupDirKey) ?? ""
        load()
        loadCalendarTags()
        loadDailyGoals()
        loadCountdowns()
        loadDailyNotes()
        loadTaskTemplates()
        loadPomodoroCounts()
        loadCategories()
        loadRolledOverDays()
        prepareForCurrentDay(at: Date())
    }

    // MARK: - Categories (User-defined, never hardcoded)

    func category(for id: UUID?) -> TaskCategory? {
        guard let id else { return nil }
        return categories.first(where: { $0.id == id })
    }

    @discardableResult
    func addCategory(name: String, colorName: String = "orange") -> TaskCategory? {
        let cleaned = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return nil }
        if let existing = categories.first(where: { $0.name == cleaned }) {
            return existing
        }
        let category = TaskCategory(name: cleaned, colorName: colorName)
        categories.append(category)
        saveCategories()
        return category
    }

    func updateCategory(id: UUID, name: String, colorName: String) {
        let cleaned = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty, let idx = categories.firstIndex(where: { $0.id == id }) else { return }
        categories[idx].name = cleaned
        categories[idx].colorName = colorName
        saveCategories()
    }

    func deleteCategory(id: UUID) {
        categories.removeAll { $0.id == id }
        var daysModified = false
        for (key, var dayTasks) in days {
            var changed = false
            for idx in dayTasks.indices where dayTasks[idx].categoryID == id {
                dayTasks[idx].categoryID = nil
                changed = true
            }
            if changed {
                days[key] = dayTasks
                daysModified = true
            }
        }
        var templatesModified = false
        for tIdx in taskTemplates.indices {
            for iIdx in taskTemplates[tIdx].items.indices where taskTemplates[tIdx].items[iIdx].categoryID == id {
                taskTemplates[tIdx].items[iIdx].categoryID = nil
                templatesModified = true
            }
        }
        saveCategories()
        if daysModified { save() }
        if templatesModified { saveTaskTemplates() }
    }

    func setCategory(_ categoryID: UUID?, for taskID: UUID, on date: Date) {
        let key = Self.dayKey(for: date)
        guard var dayTasks = days[key], let index = dayTasks.firstIndex(where: { $0.id == taskID }) else { return }
        dayTasks[index].categoryID = categoryID
        days[key] = dayTasks
        save()
    }

    func applyCategoryToAllTasksNamed(_ title: String, categoryID: UUID?) {
        let cleaned = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return }
        var modified = false
        for (key, var dayTasks) in days {
            var changed = false
            for idx in dayTasks.indices where dayTasks[idx].title == cleaned {
                if dayTasks[idx].categoryID != categoryID {
                    dayTasks[idx].categoryID = categoryID
                    changed = true
                }
            }
            if changed {
                days[key] = dayTasks
                modified = true
            }
        }
        if modified { save() }
    }

    // MARK: - Queries

    func tasks(on date: Date) -> [DailyTask] {
        days[Self.dayKey(for: date)] ?? []
    }

    func completedCount(on date: Date) -> Int {
        tasks(on: date).lazy.filter(\.isCompleted).count
    }

    func tags(on date: Date) -> [CalendarTag] {
        calendarTags[Self.dayKey(for: date)] ?? []
    }

    func note(on date: Date) -> String {
        dailyNotes[Self.dayKey(for: date)] ?? ""
    }

    func hasNote(on date: Date) -> Bool {
        !note(on: date).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    func pomodoroCount(on date: Date) -> Int {
        pomodoroCounts[Self.dayKey(for: date)] ?? 0
    }

    func goalMinutes(on date: Date) -> Int {
        if let goal = dailyGoals[Self.dayKey(for: date)] {
            return goal
        }
        let legacyGoal = defaults.integer(forKey: StudyGoal.defaultsKey)
        return legacyGoal > 0 ? legacyGoal : StudyGoal.defaultMinutes
    }

    var activeTask: DailyTask? {
        guard let activeDayKey, let activeTaskID else { return nil }
        return days[activeDayKey]?.first(where: { $0.id == activeTaskID })
    }

    var isTimerRunning: Bool {
        activeDayKey != nil && activeTaskID != nil && timerStartedAt != nil
    }

    func activeElapsed(at now: Date = Date()) -> TimeInterval {
        guard let activeDayKey, let task = activeTask, let date = Self.date(fromDayKey: activeDayKey) else {
            return 0
        }
        return elapsed(for: task, on: date, at: now)
    }

    func currentSegmentElapsed(at now: Date = Date()) -> TimeInterval {
        guard let timerStartedAt else { return 0 }
        return max(0, now.timeIntervalSince(timerStartedAt))
    }

    // MARK: - Daily Notes & Pomodoros

    func setNote(_ text: String, on date: Date) {
        let key = Self.dayKey(for: date)
        if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            dailyNotes.removeValue(forKey: key)
        } else {
            dailyNotes[key] = text
        }
        saveDailyNotes()
    }

    func incrementPomodoro(on date: Date = Date()) {
        let key = Self.dayKey(for: date)
        pomodoroCounts[key, default: 0] += 1
        savePomodoroCounts()
    }

    // MARK: - Task Templates

    func saveDayAsTemplate(name: String, from date: Date) {
        let cleaned = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return }
        let items = tasks(on: date).map {
            TaskTemplateItem(title: $0.title, isRecurring: $0.isRecurring, categoryID: $0.categoryID)
        }
        guard !items.isEmpty else { return }
        if let idx = taskTemplates.firstIndex(where: { $0.name == cleaned }) {
            taskTemplates[idx].items = items
        } else {
            taskTemplates.append(TaskTemplate(name: cleaned, items: items))
        }
        saveTaskTemplates()
    }

    func addTemplate(name: String, items: [TaskTemplateItem]) {
        let cleaned = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty, !items.isEmpty else { return }
        taskTemplates.append(TaskTemplate(name: cleaned, items: items))
        saveTaskTemplates()
    }

    func deleteTemplate(id: UUID) {
        taskTemplates.removeAll { $0.id == id }
        saveTaskTemplates()
    }

    func applyTemplate(_ template: TaskTemplate, to date: Date, replaceExisting: Bool = false, at now: Date = Date()) {
        prepareForCurrentDay(at: now)
        let key = Self.dayKey(for: date)
        if replaceExisting {
            if activeDayKey == key {
                stopActiveTimer(at: now)
            }
            days[key] = template.items.map {
                DailyTask(title: $0.title, isRecurring: $0.isRecurring, categoryID: $0.categoryID)
            }
        } else {
            var current = days[key] ?? []
            let existingTitles = Set(current.map(\.title))
            for item in template.items where !existingTitles.contains(item.title) {
                current.append(DailyTask(title: item.title, isRecurring: item.isRecurring, categoryID: item.categoryID))
            }
            days[key] = current
        }
        save()
    }

    // MARK: - Goals & Tags

    func setGoalMinutes(_ minutes: Int, on date: Date) {
        dailyGoals[Self.dayKey(for: date)] = min(24 * 60, max(30, minutes))
        saveDailyGoals()
    }

    func addTag(title: String, colorName: String, on date: Date) {
        let cleaned = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return }
        let key = Self.dayKey(for: date)
        var tags = calendarTags[key] ?? []
        tags.append(CalendarTag(title: cleaned, colorName: colorName))
        calendarTags[key] = tags
        saveCalendarTags()
    }

    func setTags(_ tags: [CalendarTag], on date: Date) {
        let key = Self.dayKey(for: date)
        let cleaned = tags.compactMap { tag -> CalendarTag? in
            let title = tag.title.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !title.isEmpty else { return nil }
            return CalendarTag(id: tag.id, title: title, colorName: tag.colorName)
        }
        if cleaned.isEmpty {
            calendarTags.removeValue(forKey: key)
        } else {
            calendarTags[key] = cleaned
        }
        saveCalendarTags()
    }

    func updateTag(id: UUID, title: String, colorName: String, on date: Date) {
        let cleaned = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return }
        let key = Self.dayKey(for: date)
        guard var tags = calendarTags[key], let index = tags.firstIndex(where: { $0.id == id }) else { return }
        tags[index].title = cleaned
        tags[index].colorName = colorName
        calendarTags[key] = tags
        saveCalendarTags()
    }

    func deleteTag(id: UUID, on date: Date) {
        let key = Self.dayKey(for: date)
        var tags = calendarTags[key] ?? []
        tags.removeAll { $0.id == id }
        if tags.isEmpty {
            calendarTags.removeValue(forKey: key)
        } else {
            calendarTags[key] = tags
        }
        saveCalendarTags()
    }

    // MARK: - Countdowns

    func addCountdown(title: String, targetDate: Date, colorName: String = "orange") {
        let cleaned = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return }
        let key = Self.dayKey(for: targetDate)
        countdowns.append(CountdownEvent(title: cleaned, targetDayKey: key, colorName: colorName))
        sortCountdowns()
        saveCountdowns()
    }

    func deleteCountdown(id: UUID) {
        countdowns.removeAll { $0.id == id }
        saveCountdowns()
    }

    func daysRemaining(for event: CountdownEvent, from now: Date = Date()) -> Int? {
        guard let target = Self.date(fromDayKey: event.targetDayKey) else { return nil }
        let startToday = calendar.startOfDay(for: now)
        let startTarget = calendar.startOfDay(for: target)
        return calendar.dateComponents([.day], from: startToday, to: startTarget).day
    }

    func upcomingCountdowns(from now: Date = Date()) -> [(event: CountdownEvent, daysRemaining: Int)] {
        countdowns.compactMap { event in
            guard let remaining = daysRemaining(for: event, from: now), remaining >= 0 else { return nil }
            return (event, remaining)
        }
        .sorted { $0.daysRemaining < $1.daysRemaining }
    }

    private func sortCountdowns() {
        countdowns.sort { $0.targetDayKey < $1.targetDayKey }
    }

    // MARK: - Tasks & Timer

    func addTask(title: String, on date: Date, isRecurring: Bool = true, categoryID: UUID? = nil) {
        let cleaned = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return }
        prepareForCurrentDay(at: Date())

        let key = Self.dayKey(for: date)
        var dayTasks = days[key] ?? []
        dayTasks.append(DailyTask(title: cleaned, isRecurring: isRecurring, categoryID: categoryID))
        days[key] = dayTasks
        save()
    }

    func renameTask(id: UUID, on date: Date, title: String) {
        let cleaned = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return }
        let key = Self.dayKey(for: date)
        guard var dayTasks = days[key], let index = dayTasks.firstIndex(where: { $0.id == id }) else { return }
        dayTasks[index].title = cleaned
        days[key] = dayTasks
        save()
    }

    func toggleRecurring(for id: UUID, on date: Date) {
        let key = Self.dayKey(for: date)
        guard var dayTasks = days[key], let index = dayTasks.firstIndex(where: { $0.id == id }) else { return }
        dayTasks[index].isRecurring.toggle()
        days[key] = dayTasks
        save()
    }

    func moveTask(draggedID: UUID, targetID: UUID, on date: Date) {
        guard draggedID != targetID else { return }
        let key = Self.dayKey(for: date)
        guard
            var dayTasks = days[key],
            let fromIndex = dayTasks.firstIndex(where: { $0.id == draggedID }),
            let toIndex = dayTasks.firstIndex(where: { $0.id == targetID })
        else { return }
        let item = dayTasks.remove(at: fromIndex)
        dayTasks.insert(item, at: toIndex)
        days[key] = dayTasks
        save()
    }

    func adjustTaskDuration(id: UUID, on date: Date, deltaSeconds: TimeInterval, at now: Date = Date()) {
        prepareForCurrentDay(at: now)
        let key = Self.dayKey(for: date)
        let wasRunning = (activeDayKey == key && activeTaskID == id)
        if wasRunning {
            stopActiveTimer(at: now)
        }
        guard var dayTasks = days[key], let index = dayTasks.firstIndex(where: { $0.id == id }) else { return }
        dayTasks[index].elapsedSeconds = max(0, dayTasks[index].elapsedSeconds + deltaSeconds)
        days[key] = dayTasks
        if wasRunning, !dayTasks[index].isCompleted {
            activeDayKey = key
            activeTaskID = id
            timerStartedAt = now
        }
        save()
    }

    func updateTask(
        id: UUID,
        on date: Date,
        title: String,
        isCompleted: Bool,
        elapsedSeconds: TimeInterval?,
        isRecurring: Bool? = nil,
        categoryID: UUID?? = nil,
        at now: Date = Date()
    ) {
        let cleaned = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return }
        prepareForCurrentDay(at: now)

        let key = Self.dayKey(for: date)
        let isThisRunning = (activeDayKey == key && activeTaskID == id)
        if isThisRunning && (elapsedSeconds != nil || isCompleted) {
            stopActiveTimer(at: now)
        }
        guard var dayTasks = days[key], let index = dayTasks.firstIndex(where: { $0.id == id }) else { return }
        dayTasks[index].title = cleaned
        dayTasks[index].isCompleted = isCompleted
        if let elapsedSeconds {
            dayTasks[index].elapsedSeconds = max(0, elapsedSeconds)
        }
        if let isRecurring {
            dayTasks[index].isRecurring = isRecurring
        }
        if let categoryID {
            dayTasks[index].categoryID = categoryID
        }
        days[key] = dayTasks
        save()
    }

    func toggleCompletion(for id: UUID, on date: Date, at now: Date = Date()) {
        prepareForCurrentDay(at: now)
        let key = Self.dayKey(for: date)

        if activeDayKey == key, activeTaskID == id {
            stopActiveTimer(at: now)
        }
        guard var dayTasks = days[key], let index = dayTasks.firstIndex(where: { $0.id == id }) else { return }
        dayTasks[index].isCompleted.toggle()
        days[key] = dayTasks
        save()
    }

    func toggleTimer(for id: UUID, on date: Date, at now: Date = Date()) {
        prepareForCurrentDay(at: now)
        guard calendar.isDate(date, inSameDayAs: now) else { return }

        let key = Self.dayKey(for: date)
        guard let dayTasks = days[key], let task = dayTasks.first(where: { $0.id == id }), !task.isCompleted else { return }

        if activeDayKey == key, activeTaskID == id {
            stopActiveTimer(at: now)
            return
        }

        stopActiveTimer(at: now)
        activeDayKey = key
        activeTaskID = id
        lastActiveTaskID = id
        timerStartedAt = now
        save()
    }

    func pauseActiveTimer(at now: Date = Date()) {
        stopActiveTimer(at: now)
    }

    func toggleQuickTimer(at now: Date = Date()) {
        prepareForCurrentDay(at: now)
        if isTimerRunning {
            stopActiveTimer(at: now)
            return
        }
        let todayTasks = tasks(on: now)
        if let lastID = lastActiveTaskID,
           let resumed = todayTasks.first(where: { $0.id == lastID && !$0.isCompleted }) {
            toggleTimer(for: resumed.id, on: now, at: now)
            return
        }
        if let candidate = todayTasks.first(where: { !$0.isCompleted }) {
            toggleTimer(for: candidate.id, on: now, at: now)
        }
    }

    func deductAwayTime(taskID: UUID, dayKey: String, seconds: TimeInterval, pauseTimer: Bool, at now: Date = Date()) {
        let deduction = max(0, seconds)
        let wasRunningThis = (activeDayKey == dayKey && activeTaskID == taskID)
        if wasRunningThis {
            stopActiveTimer(at: now)
        }
        guard var dayTasks = days[dayKey], let index = dayTasks.firstIndex(where: { $0.id == taskID }) else { return }
        dayTasks[index].elapsedSeconds = max(0, dayTasks[index].elapsedSeconds - deduction)
        days[dayKey] = dayTasks
        if wasRunningThis && !pauseTimer && !dayTasks[index].isCompleted && dayKey == Self.dayKey(for: now) {
            activeDayKey = dayKey
            activeTaskID = taskID
            timerStartedAt = now
        }
        save()
    }

    func deleteTask(id: UUID, on date: Date, at now: Date = Date()) {
        prepareForCurrentDay(at: now)
        let key = Self.dayKey(for: date)
        if activeDayKey == key, activeTaskID == id {
            stopActiveTimer(at: now)
        }
        var dayTasks = days[key] ?? []
        dayTasks.removeAll { $0.id == id }
        days[key] = dayTasks
        save()
    }

    func resetDay(_ date: Date, at now: Date = Date()) {
        let key = Self.dayKey(for: date)
        if activeDayKey == key {
            activeDayKey = nil
            activeTaskID = nil
            timerStartedAt = nil
        }
        let existing = days[key] ?? []
        days[key] = existing.map {
            DailyTask(title: $0.title, isRecurring: $0.isRecurring, categoryID: $0.categoryID)
        }
        save()
    }

    func prepareForCurrentDay(at date: Date) {
        let todayKey = Self.dayKey(for: date)

        if let activeDayKey, activeDayKey != todayKey {
            closeTimerAtDayBoundary(now: date)
        }

        if days[todayKey] != nil && rolledOverDayKeys.contains(todayKey) {
            return
        }

        let template = mostRecentTasks(before: date).filter(\.isRecurring)
        var current = days[todayKey] ?? []
        let existingTitles = Set(current.map(\.title))
        var didChange = (days[todayKey] == nil)

        // Prepend recurring tasks that weren't already pre-planned for this day
        let toAdd = template
            .filter { !existingTitles.contains($0.title) }
            .map { DailyTask(title: $0.title, isRecurring: true, categoryID: $0.categoryID) }
        if !toAdd.isEmpty {
            current.insert(contentsOf: toAdd, at: 0)
            didChange = true
        }

        days[todayKey] = current
        rolledOverDayKeys.insert(todayKey)
        saveRolledOverDays()
        if didChange {
            save()
        }
    }

    // MARK: - History Search

    func searchHistory(query: String, at now: Date = Date()) -> [HistorySearchMatch] {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !needle.isEmpty else { return [] }

        let allKeys = Set(days.keys).union(calendarTags.keys).union(dailyNotes.keys)
        var results: [HistorySearchMatch] = []

        for key in allKeys {
            guard let date = Self.date(fromDayKey: key) else { continue }
            var snippets: [String] = []

            if let dayTasks = days[key] {
                for task in dayTasks {
                    let catName = category(for: task.categoryID)?.name ?? ""
                    if task.title.lowercased().contains(needle) || catName.lowercased().contains(needle) {
                        let prefix = catName.isEmpty ? "任务" : "[\(catName)]"
                        snippets.append("\(prefix) \(task.title)")
                    }
                }
            }
            if let tags = calendarTags[key] {
                for tag in tags where tag.title.lowercased().contains(needle) {
                    snippets.append("标签：#\(tag.title)")
                }
            }
            if let note = dailyNotes[key], note.lowercased().contains(needle) {
                let firstLine = note.split(separator: "\n").first.map(String.init) ?? note
                snippets.append("随记：\(firstLine)")
            }

            if !snippets.isEmpty {
                results.append(HistorySearchMatch(
                    dayKey: key,
                    date: date,
                    snippets: Array(snippets.prefix(3)),
                    elapsedSeconds: totalElapsed(on: date, at: now)
                ))
            }
        }
        return results.sorted { $0.dayKey > $1.dayKey }
    }

    // MARK: - Analytics & Stats

    func elapsed(for task: DailyTask, on date: Date, at now: Date) -> TimeInterval {
        let key = Self.dayKey(for: date)
        guard activeDayKey == key, activeTaskID == task.id, let timerStartedAt else {
            return task.elapsedSeconds
        }
        return task.elapsedSeconds + max(0, now.timeIntervalSince(timerStartedAt))
    }

    func totalElapsed(on date: Date, at now: Date = Date()) -> TimeInterval {
        tasks(on: date).reduce(0) { $0 + elapsed(for: $1, on: date, at: now) }
    }

    func hasPlannedTasks(on date: Date) -> Bool {
        !tasks(on: date).isEmpty
    }

    func hasActivity(on date: Date, at now: Date = Date()) -> Bool {
        completedCount(on: date) > 0 || totalElapsed(on: date, at: now) > 0
    }

    func allTimeDayStats(at now: Date = Date()) -> [DayStats] {
        let todayStart = calendar.startOfDay(for: now)
        return days.keys
            .compactMap { Self.date(fromDayKey: $0) }
            .filter { calendar.startOfDay(for: $0) <= todayStart }
            .sorted()
            .map { date in
                let dayTasks = tasks(on: date)
                return DayStats(
                    date: date,
                    taskCount: dayTasks.count,
                    completedCount: dayTasks.lazy.filter(\.isCompleted).count,
                    elapsedSeconds: totalElapsed(on: date, at: now)
                )
            }
    }

    func dayStats(inMonthContaining month: Date, at now: Date = Date()) -> [DayStats] {
        guard
            let interval = calendar.dateInterval(of: .month, for: month),
            let dayRange = calendar.range(of: .day, in: .month, for: month)
        else { return [] }

        return dayRange.compactMap { day -> DayStats? in
            guard let date = calendar.date(byAdding: .day, value: day - 1, to: interval.start) else { return nil }
            let dayTasks = tasks(on: date)
            return DayStats(
                date: date,
                taskCount: dayTasks.count,
                completedCount: dayTasks.lazy.filter(\.isCompleted).count,
                elapsedSeconds: totalElapsed(on: date, at: now)
            )
        }
    }

    func weeklyStats(containing referenceDate: Date, at now: Date = Date()) -> [DayStats] {
        var mondayCal = calendar
        mondayCal.firstWeekday = 2
        guard let interval = mondayCal.dateInterval(of: .weekOfYear, for: referenceDate) else { return [] }
        return (0..<7).compactMap { offset -> DayStats? in
            guard let date = mondayCal.date(byAdding: .day, value: offset, to: interval.start) else { return nil }
            let dayTasks = tasks(on: date)
            return DayStats(
                date: date,
                taskCount: dayTasks.count,
                completedCount: dayTasks.lazy.filter(\.isCompleted).count,
                elapsedSeconds: totalElapsed(on: date, at: now)
            )
        }
    }

    /// Returns `weeks` columns of 7 days (Mon..Sun) ending in the week containing `endDate`.
    func heatmapStats(weeks: Int = 12, endingAt endDate: Date = Date(), at now: Date = Date()) -> [[DayStats]] {
        var mondayCal = calendar
        mondayCal.firstWeekday = 2
        guard let currentWeekStart = mondayCal.dateInterval(of: .weekOfYear, for: endDate)?.start else { return [] }
        var columns: [[DayStats]] = []
        for weekOffset in stride(from: -(weeks - 1), through: 0, by: 1) {
            guard let weekStart = mondayCal.date(byAdding: .weekOfYear, value: weekOffset, to: currentWeekStart) else { continue }
            var col: [DayStats] = []
            for dayOffset in 0..<7 {
                guard let date = mondayCal.date(byAdding: .day, value: dayOffset, to: weekStart) else { continue }
                let dayTasks = tasks(on: date)
                col.append(DayStats(
                    date: date,
                    taskCount: dayTasks.count,
                    completedCount: dayTasks.lazy.filter(\.isCompleted).count,
                    elapsedSeconds: totalElapsed(on: date, at: now)
                ))
            }
            columns.append(col)
        }
        return columns
    }

    func taskTimeTotals(inMonthContaining month: Date, at now: Date = Date()) -> [TaskTimeTotal] {
        guard let interval = calendar.dateInterval(of: .month, for: month) else { return [] }
        return taskTimeTotals(in: interval, at: now)
    }

    func taskTimeTotals(inWeekContaining referenceDate: Date, at now: Date = Date()) -> [TaskTimeTotal] {
        var mondayCal = calendar
        mondayCal.firstWeekday = 2
        guard let interval = mondayCal.dateInterval(of: .weekOfYear, for: referenceDate) else { return [] }
        return taskTimeTotals(in: interval, at: now)
    }

    func taskTimeTotalsAllTime(at now: Date = Date()) -> [TaskTimeTotal] {
        taskTimeTotals(in: nil, at: now)
    }

    func categoryTimeStats(inMonthContaining month: Date, at now: Date = Date()) -> [CategoryTimeStat] {
        guard let interval = calendar.dateInterval(of: .month, for: month) else { return [] }
        return categoryTimeStats(in: interval, at: now)
    }

    func categoryTimeStats(inWeekContaining referenceDate: Date, at now: Date = Date()) -> [CategoryTimeStat] {
        var mondayCal = calendar
        mondayCal.firstWeekday = 2
        guard let interval = mondayCal.dateInterval(of: .weekOfYear, for: referenceDate) else { return [] }
        return categoryTimeStats(in: interval, at: now)
    }

    func categoryTimeStatsAllTime(at now: Date = Date()) -> [CategoryTimeStat] {
        categoryTimeStats(in: nil, at: now)
    }

    private func taskTimeTotals(in interval: DateInterval?, at now: Date) -> [TaskTimeTotal] {
        var totals: [String: (seconds: TimeInterval, categoryID: UUID?)] = [:]
        for key in days.keys.sorted() {
            guard let date = Self.date(fromDayKey: key) else { continue }
            if let interval, !interval.contains(date) { continue }
            for task in days[key] ?? [] {
                let sec = elapsed(for: task, on: date, at: now)
                guard sec > 0 else { continue }
                let existing = totals[task.title]
                totals[task.title] = (
                    seconds: (existing?.seconds ?? 0) + sec,
                    categoryID: task.categoryID ?? existing?.categoryID
                )
            }
        }
        return totals
            .map { TaskTimeTotal(title: $0.key, seconds: $0.value.seconds, categoryID: $0.value.categoryID) }
            .sorted { $0.seconds > $1.seconds }
    }

    private func categoryTimeStats(in interval: DateInterval?, at now: Date) -> [CategoryTimeStat] {
        var grouped: [UUID?: [String: TimeInterval]] = [:]
        var grandTotal: TimeInterval = 0

        for (key, dayTasks) in days {
            guard let date = Self.date(fromDayKey: key) else { continue }
            if let interval, !interval.contains(date) { continue }
            for task in dayTasks {
                let sec = elapsed(for: task, on: date, at: now)
                guard sec > 0 else { continue }
                let validCatID: UUID? = (task.categoryID != nil && category(for: task.categoryID) != nil) ? task.categoryID : nil
                grouped[validCatID, default: [:]][task.title, default: 0] += sec
                grandTotal += sec
            }
        }

        guard grandTotal > 0 else { return [] }

        return grouped.map { catID, taskDict -> CategoryTimeStat in
            let catSeconds = taskDict.values.reduce(0, +)
            let catObj = category(for: catID)
            let taskList = taskDict
                .map { TaskTimeTotal(title: $0.key, seconds: $0.value, categoryID: catID) }
                .sorted { $0.seconds > $1.seconds }
            return CategoryTimeStat(
                id: catID?.uuidString ?? "uncategorized",
                categoryID: catID,
                name: catObj?.name ?? "未分类",
                colorName: catObj?.colorName ?? "gray",
                seconds: catSeconds,
                share: catSeconds / grandTotal,
                tasks: taskList
            )
        }
        .sorted { $0.seconds > $1.seconds }
    }

    func currentStreak(at now: Date = Date()) -> Int {
        var cursor = calendar.startOfDay(for: now)
        if !hasActivity(on: cursor, at: now) {
            guard let yesterday = calendar.date(byAdding: .day, value: -1, to: cursor) else { return 0 }
            cursor = yesterday
        }
        var streak = 0
        while hasActivity(on: cursor, at: now) {
            streak += 1
            guard let prev = calendar.date(byAdding: .day, value: -1, to: cursor) else { break }
            cursor = prev
        }
        return streak
    }

    func bestStreak(at now: Date = Date()) -> Int {
        let activeDates = days.keys
            .compactMap { Self.date(fromDayKey: $0) }
            .filter { hasActivity(on: $0, at: now) }
            .map { calendar.startOfDay(for: $0) }
            .sorted()
        guard !activeDates.isEmpty else { return 0 }
        var best = 1
        var current = 1
        for i in 1..<activeDates.count {
            let diff = calendar.dateComponents([.day], from: activeDates[i - 1], to: activeDates[i]).day ?? 0
            if diff == 1 {
                current += 1
                best = max(best, current)
            } else if diff > 1 {
                current = 1
            }
        }
        return best
    }

    // MARK: - Backup & Export / Import

    func makeBackup(at now: Date = Date()) -> DayNoteBackup {
        let archive = StoredArchive(
            days: days,
            activeDayKey: activeDayKey,
            activeTaskID: activeTaskID,
            timerStartedAt: timerStartedAt
        )
        return DayNoteBackup(
            formatVersion: 5,
            exportedAt: now,
            archive: archive,
            calendarTags: calendarTags,
            dailyGoals: dailyGoals,
            countdowns: countdowns,
            dailyNotes: dailyNotes,
            taskTemplates: taskTemplates,
            pomodoroCounts: pomodoroCounts,
            categories: categories
        )
    }

    func exportJSONData(at now: Date = Date()) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(makeBackup(at: now))
    }

    func importBackup(from data: Data) throws {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let backup: DayNoteBackup
        if let decoded = try? decoder.decode(DayNoteBackup.self, from: data) {
            backup = decoded
        } else {
            let fallbackDecoder = JSONDecoder()
            backup = try fallbackDecoder.decode(DayNoteBackup.self, from: data)
        }
        days = backup.archive.days
        activeDayKey = backup.archive.activeDayKey
        activeTaskID = backup.archive.activeTaskID
        timerStartedAt = backup.archive.timerStartedAt
        calendarTags = backup.calendarTags
        dailyGoals = backup.dailyGoals
        countdowns = backup.countdowns
        dailyNotes = backup.dailyNotes
        taskTemplates = backup.taskTemplates
        pomodoroCounts = backup.pomodoroCounts
        categories = backup.categories
        let todayStart = calendar.startOfDay(for: Date())
        rolledOverDayKeys = Set(days.keys.filter { key in
            guard let d = Self.date(fromDayKey: key) else { return true }
            return calendar.startOfDay(for: d) <= todayStart
        })
        sortCountdowns()
        validateActiveTimer()
        save()
        saveCalendarTags()
        saveDailyGoals()
        saveCountdowns()
        saveDailyNotes()
        saveTaskTemplates()
        savePomodoroCounts()
        saveCategories()
        saveRolledOverDays()
    }

    func exportCSVString(at now: Date = Date()) -> String {
        var lines: [String] = ["\u{FEFF}日期,当天目标(分钟),当天总时长(分钟),达成率(%),分类,任务名称,已完成,任务时长(分钟),每日重复,标签,当日随记"]
        let allKeys = Set(days.keys).union(calendarTags.keys).union(dailyNotes.keys).sorted()
        for key in allKeys {
            guard let date = Self.date(fromDayKey: key) else { continue }
            let dayTasks = days[key] ?? []
            let goalMin = goalMinutes(on: date)
            let totalSec = totalElapsed(on: date, at: now)
            let totalMin = String(format: "%.1f", totalSec / 60.0)
            let pct = StudyGoal.percent(elapsedSeconds: totalSec, goalMinutes: goalMin)
            let tagText = (calendarTags[key] ?? []).map(\.title).joined(separator: " / ")
            let noteText = (dailyNotes[key] ?? "").replacingOccurrences(of: "\n", with: " ")
            if dayTasks.isEmpty {
                lines.append("\(key),\(goalMin),\(totalMin),\(pct)%,\"\",\"\",否,0.0,否,\"\(csvEscape(tagText))\",\"\(csvEscape(noteText))\"")
            } else {
                for task in dayTasks {
                    let taskMin = String(format: "%.1f", elapsed(for: task, on: date, at: now) / 60.0)
                    let done = task.isCompleted ? "是" : "否"
                    let rec = task.isRecurring ? "是" : "否"
                    let catName = category(for: task.categoryID)?.name ?? "未分类"
                    lines.append("\(key),\(goalMin),\(totalMin),\(pct)%,\"\(csvEscape(catName))\",\"\(csvEscape(task.title))\",\(done),\(taskMin),\(rec),\"\(csvEscape(tagText))\",\"\(csvEscape(noteText))\"")
                }
            }
        }
        return lines.joined(separator: "\n") + "\n"
    }

    func performAutoBackupIfConfigured(force: Bool = false) {
        let dirPath = autoBackupDirectoryPath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !dirPath.isEmpty else { return }
        let now = Date()
        if !force, let last = lastAutoBackupAt, now.timeIntervalSince(last) < 15 {
            return
        }
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: dirPath, isDirectory: &isDir), isDir.boolValue else { return }
        guard let data = try? exportJSONData(at: now) else { return }
        let targetURL = URL(fileURLWithPath: dirPath).appendingPathComponent("DayNote-AutoBackup.json")
        try? data.write(to: targetURL, options: .atomic)
        lastAutoBackupAt = now
    }

    private func csvEscape(_ text: String) -> String {
        text.replacingOccurrences(of: "\"", with: "\"\"")
    }

    // MARK: - Internal Timer & Persistence

    private func stopActiveTimer(at date: Date) {
        guard
            let activeDayKey,
            let activeTaskID,
            let timerStartedAt,
            var dayTasks = days[activeDayKey],
            let index = dayTasks.firstIndex(where: { $0.id == activeTaskID })
        else {
            self.activeDayKey = nil
            self.activeTaskID = nil
            self.timerStartedAt = nil
            return
        }

        dayTasks[index].elapsedSeconds += max(0, date.timeIntervalSince(timerStartedAt))
        days[activeDayKey] = dayTasks
        self.activeDayKey = nil
        self.activeTaskID = nil
        self.timerStartedAt = nil
        save()
    }

    private func closeTimerAtDayBoundary(now: Date) {
        guard
            let activeDayKey,
            let activeTaskID,
            let timerStartedAt,
            var dayTasks = days[activeDayKey],
            let index = dayTasks.firstIndex(where: { $0.id == activeTaskID })
        else {
            self.activeDayKey = nil
            self.activeTaskID = nil
            self.timerStartedAt = nil
            return
        }

        let activeDate = Self.date(fromDayKey: activeDayKey) ?? timerStartedAt
        let nextDayStart = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: activeDate)) ?? now
        let end = min(now, max(timerStartedAt, nextDayStart))
        dayTasks[index].elapsedSeconds += max(0, end.timeIntervalSince(timerStartedAt))
        days[activeDayKey] = dayTasks
        self.activeDayKey = nil
        self.activeTaskID = nil
        self.timerStartedAt = nil
        save()
    }

    private func mostRecentTasks(before date: Date) -> [DailyTask] {
        days.compactMap { key, tasks -> (Date, [DailyTask])? in
            guard let recordDate = Self.date(fromDayKey: key), recordDate < calendar.startOfDay(for: date) else { return nil }
            return (recordDate, tasks)
        }
        .max { $0.0 < $1.0 }?
        .1 ?? []
    }

    private func load() {
        if
            let data = defaults.data(forKey: archiveKey),
            let archive = try? JSONDecoder().decode(StoredArchive.self, from: data)
        {
            days = archive.days
            activeDayKey = archive.activeDayKey
            activeTaskID = archive.activeTaskID
            timerStartedAt = archive.timerStartedAt
            validateActiveTimer()
            return
        }

        guard
            let data = defaults.data(forKey: legacyKey),
            let note = try? JSONDecoder().decode(LegacyStoredNote.self, from: data)
        else { return }

        let migratedKey = Self.date(fromDayKey: note.dayKey).map(Self.dayKey(for:)) ?? Self.dayKey(for: Date())
        days[migratedKey] = note.tasks
        activeDayKey = note.activeTaskID == nil ? nil : migratedKey
        activeTaskID = note.activeTaskID
        timerStartedAt = note.timerStartedAt
        validateActiveTimer()
        save()
    }

    private func loadCalendarTags() {
        guard
            let data = defaults.data(forKey: calendarTagsKey),
            let tags = try? JSONDecoder().decode([String: [CalendarTag]].self, from: data)
        else { return }
        calendarTags = tags
    }

    private func loadDailyGoals() {
        guard
            let data = defaults.data(forKey: dailyGoalsKey),
            let goals = try? JSONDecoder().decode([String: Int].self, from: data)
        else { return }
        dailyGoals = goals
    }

    private func loadCountdowns() {
        guard
            let data = defaults.data(forKey: countdownsKey),
            let items = try? JSONDecoder().decode([CountdownEvent].self, from: data)
        else { return }
        countdowns = items
        sortCountdowns()
    }

    private func loadDailyNotes() {
        guard
            let data = defaults.data(forKey: dailyNotesKey),
            let notes = try? JSONDecoder().decode([String: String].self, from: data)
        else { return }
        dailyNotes = notes
    }

    private func loadTaskTemplates() {
        guard
            let data = defaults.data(forKey: taskTemplatesKey),
            let templates = try? JSONDecoder().decode([TaskTemplate].self, from: data)
        else { return }
        taskTemplates = templates
    }

    private func loadPomodoroCounts() {
        guard
            let data = defaults.data(forKey: pomodoroCountsKey),
            let counts = try? JSONDecoder().decode([String: Int].self, from: data)
        else { return }
        pomodoroCounts = counts
    }

    private func loadCategories() {
        guard
            let data = defaults.data(forKey: categoriesKey),
            let items = try? JSONDecoder().decode([TaskCategory].self, from: data)
        else { return }
        categories = items
    }

    private func loadRolledOverDays() {
        if let saved = defaults.stringArray(forKey: rolledOverDaysKey) {
            rolledOverDayKeys = Set(saved)
        } else {
            // Seed with existing past/today keys so historical days are never altered,
            // while future pre-planned days still receive recurring tasks when that day arrives.
            let todayStart = calendar.startOfDay(for: Date())
            rolledOverDayKeys = Set(days.keys.filter { key in
                guard let d = Self.date(fromDayKey: key) else { return true }
                return calendar.startOfDay(for: d) <= todayStart
            })
            saveRolledOverDays()
        }
    }

    private func saveRolledOverDays() {
        defaults.set(Array(rolledOverDayKeys), forKey: rolledOverDaysKey)
    }

    private func saveDailyGoals() {
        guard let data = try? JSONEncoder().encode(dailyGoals) else { return }
        defaults.set(data, forKey: dailyGoalsKey)
        performAutoBackupIfConfigured()
    }

    private func saveCalendarTags() {
        guard let data = try? JSONEncoder().encode(calendarTags) else { return }
        defaults.set(data, forKey: calendarTagsKey)
        performAutoBackupIfConfigured()
    }

    private func saveCountdowns() {
        guard let data = try? JSONEncoder().encode(countdowns) else { return }
        defaults.set(data, forKey: countdownsKey)
        performAutoBackupIfConfigured()
    }

    private func saveDailyNotes() {
        guard let data = try? JSONEncoder().encode(dailyNotes) else { return }
        defaults.set(data, forKey: dailyNotesKey)
        performAutoBackupIfConfigured()
    }

    private func saveTaskTemplates() {
        guard let data = try? JSONEncoder().encode(taskTemplates) else { return }
        defaults.set(data, forKey: taskTemplatesKey)
        performAutoBackupIfConfigured()
    }

    private func savePomodoroCounts() {
        guard let data = try? JSONEncoder().encode(pomodoroCounts) else { return }
        defaults.set(data, forKey: pomodoroCountsKey)
        performAutoBackupIfConfigured()
    }

    private func saveCategories() {
        guard let data = try? JSONEncoder().encode(categories) else { return }
        defaults.set(data, forKey: categoriesKey)
        performAutoBackupIfConfigured()
    }

    private func validateActiveTimer() {
        guard
            let activeDayKey,
            let activeTaskID,
            days[activeDayKey]?.contains(where: { $0.id == activeTaskID }) == true,
            timerStartedAt != nil
        else {
            self.activeDayKey = nil
            self.activeTaskID = nil
            self.timerStartedAt = nil
            return
        }
    }

    private func save() {
        let archive = StoredArchive(
            days: days,
            activeDayKey: activeDayKey,
            activeTaskID: activeTaskID,
            timerStartedAt: timerStartedAt
        )
        guard let data = try? JSONEncoder().encode(archive) else { return }
        defaults.set(data, forKey: archiveKey)
        performAutoBackupIfConfigured()
    }

    static func dayKey(for date: Date) -> String {
        let components = Calendar.autoupdatingCurrent.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", components.year ?? 0, components.month ?? 0, components.day ?? 0)
    }

    static func date(fromDayKey key: String) -> Date? {
        let parts = key.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        return Calendar.autoupdatingCurrent.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2]))
    }
}
