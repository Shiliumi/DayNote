import Foundation

@MainActor
final class TaskStore: ObservableObject {
    @Published private(set) var days: [String: [DailyTask]] = [:]
    @Published private(set) var activeDayKey: String?
    @Published private(set) var activeTaskID: UUID?
    @Published private(set) var timerStartedAt: Date?
    @Published private(set) var calendarTags: [String: [CalendarTag]] = [:]
    @Published private(set) var dailyGoals: [String: Int] = [:]

    private let archiveKey = "daynote.saved-archive.v2"
    private let legacyKey = "daynote.saved-note.v1"
    private let calendarTagsKey = "daynote.calendar-tags.v1"
    private let dailyGoalsKey = "daynote.daily-goals.v1"
    private let calendar = Calendar.autoupdatingCurrent
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        load()
        loadCalendarTags()
        loadDailyGoals()
        prepareForCurrentDay(at: Date())
    }

    func tasks(on date: Date) -> [DailyTask] {
        days[Self.dayKey(for: date)] ?? []
    }

    func completedCount(on date: Date) -> Int {
        tasks(on: date).lazy.filter(\.isCompleted).count
    }

    func tags(on date: Date) -> [CalendarTag] {
        calendarTags[Self.dayKey(for: date)] ?? []
    }

    func goalMinutes(on date: Date) -> Int {
        if let goal = dailyGoals[Self.dayKey(for: date)] {
            return goal
        }
        let legacyGoal = defaults.integer(forKey: StudyGoal.defaultsKey)
        return legacyGoal > 0 ? legacyGoal : StudyGoal.defaultMinutes
    }

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

    func addTask(title: String, on date: Date) {
        let cleaned = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return }
        prepareForCurrentDay(at: Date())

        let key = Self.dayKey(for: date)
        var dayTasks = days[key] ?? []
        dayTasks.append(DailyTask(title: cleaned))
        days[key] = dayTasks
        save()
    }

    func updateTask(
        id: UUID,
        on date: Date,
        title: String,
        isCompleted: Bool,
        elapsedSeconds: TimeInterval,
        at now: Date = Date()
    ) {
        let cleaned = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return }
        prepareForCurrentDay(at: now)

        let key = Self.dayKey(for: date)
        if activeDayKey == key, activeTaskID == id {
            stopActiveTimer(at: now)
        }
        guard var dayTasks = days[key], let index = dayTasks.firstIndex(where: { $0.id == id }) else { return }
        dayTasks[index].title = cleaned
        dayTasks[index].isCompleted = isCompleted
        dayTasks[index].elapsedSeconds = max(0, elapsedSeconds)
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
        timerStartedAt = now
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
        let titles = (days[key] ?? []).map(\.title)
        days[key] = titles.map { DailyTask(title: $0) }
        save()
    }

    func prepareForCurrentDay(at date: Date) {
        let todayKey = Self.dayKey(for: date)

        if let activeDayKey, activeDayKey != todayKey {
            closeTimerAtDayBoundary(now: date)
        }

        guard days[todayKey] == nil else { return }
        let template = mostRecentTasks(before: date)
        days[todayKey] = template.map { DailyTask(title: $0.title) }
        save()
    }

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

    func taskTimeTotals(inMonthContaining month: Date, at now: Date = Date()) -> [(title: String, seconds: TimeInterval)] {
        guard let interval = calendar.dateInterval(of: .month, for: month) else { return [] }
        var totals: [String: TimeInterval] = [:]

        for (key, dayTasks) in days {
            guard let date = Self.date(fromDayKey: key), interval.contains(date) else { continue }
            for task in dayTasks {
                totals[task.title, default: 0] += elapsed(for: task, on: date, at: now)
            }
        }

        return totals
            .map { (title: $0.key, seconds: $0.value) }
            .filter { $0.seconds > 0 }
            .sorted { $0.seconds > $1.seconds }
    }

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

    private func saveDailyGoals() {
        guard let data = try? JSONEncoder().encode(dailyGoals) else { return }
        defaults.set(data, forKey: dailyGoalsKey)
    }

    private func saveCalendarTags() {
        guard let data = try? JSONEncoder().encode(calendarTags) else { return }
        defaults.set(data, forKey: calendarTagsKey)
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
