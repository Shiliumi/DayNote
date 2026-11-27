import Foundation

struct DailyTask: Identifiable, Codable, Equatable {
    let id: UUID
    var title: String
    var isCompleted: Bool
    var elapsedSeconds: TimeInterval

    init(
        id: UUID = UUID(),
        title: String,
        isCompleted: Bool = false,
        elapsedSeconds: TimeInterval = 0
    ) {
        self.id = id
        self.title = title
        self.isCompleted = isCompleted
        self.elapsedSeconds = elapsedSeconds
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
