import Foundation

struct TaskCategory: Identifiable, Codable, Equatable {
    let id: UUID
    var name: String
    var colorName: String

    init(id: UUID = UUID(), name: String, colorName: String = "orange") {
        self.id = id
        self.name = name
        self.colorName = colorName
    }
}

struct DailyTask: Identifiable, Codable, Equatable {
    let id: UUID
    var title: String
    var isCompleted: Bool
    var elapsedSeconds: TimeInterval
    var isRecurring: Bool
    var categoryID: UUID?

    enum CodingKeys: String, CodingKey {
        case id
        case title
        case isCompleted
        case elapsedSeconds
        case isRecurring
        case categoryID
    }

    init(
        id: UUID = UUID(),
        title: String,
        isCompleted: Bool = false,
        elapsedSeconds: TimeInterval = 0,
        isRecurring: Bool = true,
        categoryID: UUID? = nil
    ) {
        self.id = id
        self.title = title
        self.isCompleted = isCompleted
        self.elapsedSeconds = elapsedSeconds
        self.isRecurring = isRecurring
        self.categoryID = categoryID
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        title = try container.decode(String.self, forKey: .title)
        isCompleted = try container.decode(Bool.self, forKey: .isCompleted)
        elapsedSeconds = try container.decode(TimeInterval.self, forKey: .elapsedSeconds)
        isRecurring = try container.decodeIfPresent(Bool.self, forKey: .isRecurring) ?? true
        categoryID = try container.decodeIfPresent(UUID.self, forKey: .categoryID)
    }
}

struct LegacyStoredNote: Codable {
    var dayKey: String
    var tasks: [DailyTask]
    var activeTaskID: UUID?
    var timerStartedAt: Date?
}

struct StoredArchive: Codable {
    var days: [String: [DailyTask]]
    var activeDayKey: String?
    var activeTaskID: UUID?
    var timerStartedAt: Date?
}

struct DayStats: Identifiable {
    let date: Date
    let taskCount: Int
    let completedCount: Int
    let elapsedSeconds: TimeInterval

    var id: Date { date }
    var hasActivity: Bool { completedCount > 0 || elapsedSeconds > 0 }
}

struct TaskTimeTotal: Identifiable {
    let title: String
    let seconds: TimeInterval
    let categoryID: UUID?

    var id: String { "\(title)-\(categoryID?.uuidString ?? "none")" }
}

struct CategoryTimeStat: Identifiable {
    let id: String
    let categoryID: UUID?
    let name: String
    let colorName: String
    let seconds: TimeInterval
    let share: Double
    let tasks: [TaskTimeTotal]
}

struct CalendarTag: Identifiable, Codable, Equatable {
    let id: UUID
    var title: String
    var colorName: String

    init(id: UUID = UUID(), title: String, colorName: String) {
        self.id = id
        self.title = title
        self.colorName = colorName
    }
}

struct CountdownEvent: Identifiable, Codable, Equatable {
    let id: UUID
    var title: String
    var targetDayKey: String
    var colorName: String

    init(id: UUID = UUID(), title: String, targetDayKey: String, colorName: String = "orange") {
        self.id = id
        self.title = title
        self.targetDayKey = targetDayKey
        self.colorName = colorName
    }
}

struct TaskTemplateItem: Identifiable, Codable, Equatable {
    let id: UUID
    var title: String
    var isRecurring: Bool
    var categoryID: UUID?

    enum CodingKeys: String, CodingKey {
        case id
        case title
        case isRecurring
        case categoryID
    }

    init(id: UUID = UUID(), title: String, isRecurring: Bool = true, categoryID: UUID? = nil) {
        self.id = id
        self.title = title
        self.isRecurring = isRecurring
        self.categoryID = categoryID
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        title = try c.decode(String.self, forKey: .title)
        isRecurring = try c.decodeIfPresent(Bool.self, forKey: .isRecurring) ?? true
        categoryID = try c.decodeIfPresent(UUID.self, forKey: .categoryID)
    }
}

struct TaskTemplate: Identifiable, Codable, Equatable {
    let id: UUID
    var name: String
    var items: [TaskTemplateItem]

    init(id: UUID = UUID(), name: String, items: [TaskTemplateItem]) {
        self.id = id
        self.name = name
        self.items = items
    }
}

struct HistorySearchMatch: Identifiable {
    let dayKey: String
    let date: Date
    let snippets: [String]
    let elapsedSeconds: TimeInterval

    var id: String { dayKey }
}

struct DayNoteBackup: Codable {
    var formatVersion: Int
    var exportedAt: Date
    var archive: StoredArchive
    var calendarTags: [String: [CalendarTag]]
    var dailyGoals: [String: Int]
    var countdowns: [CountdownEvent]
    var dailyNotes: [String: String]
    var taskTemplates: [TaskTemplate]
    var pomodoroCounts: [String: Int]
    var categories: [TaskCategory]

    enum CodingKeys: String, CodingKey {
        case formatVersion
        case exportedAt
        case archive
        case calendarTags
        case dailyGoals
        case countdowns
        case dailyNotes
        case taskTemplates
        case pomodoroCounts
        case categories
    }

    init(
        formatVersion: Int,
        exportedAt: Date,
        archive: StoredArchive,
        calendarTags: [String: [CalendarTag]],
        dailyGoals: [String: Int],
        countdowns: [CountdownEvent],
        dailyNotes: [String: String] = [:],
        taskTemplates: [TaskTemplate] = [],
        pomodoroCounts: [String: Int] = [:],
        categories: [TaskCategory] = []
    ) {
        self.formatVersion = formatVersion
        self.exportedAt = exportedAt
        self.archive = archive
        self.calendarTags = calendarTags
        self.dailyGoals = dailyGoals
        self.countdowns = countdowns
        self.dailyNotes = dailyNotes
        self.taskTemplates = taskTemplates
        self.pomodoroCounts = pomodoroCounts
        self.categories = categories
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        formatVersion = try c.decode(Int.self, forKey: .formatVersion)
        exportedAt = try c.decode(Date.self, forKey: .exportedAt)
        archive = try c.decode(StoredArchive.self, forKey: .archive)
        calendarTags = try c.decodeIfPresent([String: [CalendarTag]].self, forKey: .calendarTags) ?? [:]
        dailyGoals = try c.decodeIfPresent([String: Int].self, forKey: .dailyGoals) ?? [:]
        countdowns = try c.decodeIfPresent([CountdownEvent].self, forKey: .countdowns) ?? []
        dailyNotes = try c.decodeIfPresent([String: String].self, forKey: .dailyNotes) ?? [:]
        taskTemplates = try c.decodeIfPresent([TaskTemplate].self, forKey: .taskTemplates) ?? []
        pomodoroCounts = try c.decodeIfPresent([String: Int].self, forKey: .pomodoroCounts) ?? [:]
        categories = try c.decodeIfPresent([TaskCategory].self, forKey: .categories) ?? []
    }
}

struct SleepRecoveryPrompt: Identifiable, Equatable {
    let id = UUID()
    let dayKey: String
    let taskID: UUID
    let taskTitle: String
    let awaySeconds: TimeInterval
}
