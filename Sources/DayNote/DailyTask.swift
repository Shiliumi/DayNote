import Foundation

struct DailyTask: Identifiable, Codable, Equatable {
    let id: UUID
    var title: String
    var isCompleted: Bool
    var elapsedSeconds: TimeInterval
    var isRecurring: Bool

    enum CodingKeys: String, CodingKey {
        case id
        case title
        case isCompleted
        case elapsedSeconds
        case isRecurring
    }

    init(
        id: UUID = UUID(),
        title: String,
        isCompleted: Bool = false,
        elapsedSeconds: TimeInterval = 0,
        isRecurring: Bool = true
    ) {
        self.id = id
        self.title = title
        self.isCompleted = isCompleted
        self.elapsedSeconds = elapsedSeconds
        self.isRecurring = isRecurring
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        title = try container.decode(String.self, forKey: .title)
        isCompleted = try container.decode(Bool.self, forKey: .isCompleted)
        elapsedSeconds = try container.decode(TimeInterval.self, forKey: .elapsedSeconds)
        isRecurring = try container.decodeIfPresent(Bool.self, forKey: .isRecurring) ?? true
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

struct DayNoteBackup: Codable {
    var formatVersion: Int
    var exportedAt: Date
    var archive: StoredArchive
    var calendarTags: [String: [CalendarTag]]
    var dailyGoals: [String: Int]
    var countdowns: [CountdownEvent]
}

struct SleepRecoveryPrompt: Identifiable, Equatable {
    let id = UUID()
    let dayKey: String
    let taskID: UUID
    let taskTitle: String
    let awaySeconds: TimeInterval
}
