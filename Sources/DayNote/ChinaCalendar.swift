import Foundation
import SwiftUI

struct OfficialHoliday {
    enum Kind {
        case holiday
        case adjustedWorkday
    }

    let name: String
    let kind: Kind

    var badge: String { kind == .holiday ? "休" : "班" }
}

enum ChinaCalendar {
    private static let gregorian: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Shanghai") ?? .current
        return calendar
    }()

    private static let lunar: Calendar = {
        var calendar = Calendar(identifier: .chinese)
        calendar.locale = Locale(identifier: "zh_CN")
        calendar.timeZone = TimeZone(identifier: "Asia/Shanghai") ?? .current
        return calendar
    }()

    private static let lunarDays = [
        "", "初一", "初二", "初三", "初四", "初五", "初六", "初七", "初八", "初九", "初十",
        "十一", "十二", "十三", "十四", "十五", "十六", "十七", "十八", "十九", "二十",
        "廿一", "廿二", "廿三", "廿四", "廿五", "廿六", "廿七", "廿八", "廿九", "三十"
    ]
    private static let lunarMonths = ["", "正月", "二月", "三月", "四月", "五月", "六月", "七月", "八月", "九月", "十月", "冬月", "腊月"]

    static func lunarText(for date: Date) -> String {
        let components = lunar.dateComponents([.month, .day, .isLeapMonth], from: date)
        guard let month = components.month, let day = components.day else { return "" }
        if day == 1, lunarMonths.indices.contains(month) {
            return (components.isLeapMonth == true ? "闰" : "") + lunarMonths[month]
        }
        return lunarDays.indices.contains(day) ? lunarDays[day] : ""
    }

    static func lunarDetail(for date: Date) -> String {
        let components = lunar.dateComponents([.year, .month, .day, .isLeapMonth], from: date)
        guard let month = components.month, let day = components.day else { return "农历" }
        let monthText = lunarMonths.indices.contains(month) ? lunarMonths[month] : ""
        let dayText = lunarDays.indices.contains(day) ? lunarDays[day] : ""
        return "农历\(components.isLeapMonth == true ? "闰" : "")\(monthText)\(dayText)"
    }

    static func traditionalFestival(for date: Date) -> String? {
        let components = lunar.dateComponents([.month, .day, .isLeapMonth], from: date)
        guard components.isLeapMonth != true, let month = components.month, let day = components.day else { return nil }
        switch (month, day) {
        case (1, 1): return "春节"
        case (1, 15): return "元宵节"
        case (5, 5): return "端午节"
        case (7, 7): return "七夕"
        case (8, 15): return "中秋节"
        case (9, 9): return "重阳节"
        case (12, 8): return "腊八节"
        case (12, 23): return "北方小年"
        case (12, 24): return "南方小年"
        default: return nil
        }
    }

    static func officialHoliday(for date: Date) -> OfficialHoliday? {
        officialHolidays[dayKey(date)]
    }

    static func hasOfficialSchedule(for year: Int) -> Bool {
        [2024, 2025, 2026].contains(year)
    }

    private static func dayKey(_ date: Date) -> String {
        let values = gregorian.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", values.year ?? 0, values.month ?? 0, values.day ?? 0)
    }

    private static let officialHolidays: [String: OfficialHoliday] = {
        var result: [String: OfficialHoliday] = [:]

        func add(_ dates: [String], _ name: String, _ kind: OfficialHoliday.Kind = .holiday) {
            for date in dates { result[date] = OfficialHoliday(name: name, kind: kind) }
        }

        func addRange(_ start: String, _ end: String, _ name: String) {
            let formatter = DateFormatter()
            formatter.calendar = gregorian
            formatter.timeZone = gregorian.timeZone
            formatter.dateFormat = "yyyy-MM-dd"
            guard let first = formatter.date(from: start), let last = formatter.date(from: end) else { return }
            var date = first
            while date <= last {
                result[formatter.string(from: date)] = OfficialHoliday(name: name, kind: .holiday)
                date = gregorian.date(byAdding: .day, value: 1, to: date) ?? last.addingTimeInterval(1)
            }
        }

        // 国务院办公厅 2024 年部分节假日安排（国办发明电〔2023〕7号）
        add(["2024-01-01"], "元旦")
        addRange("2024-02-10", "2024-02-17", "春节")
        add(["2024-02-04", "2024-02-18"], "春节调休", .adjustedWorkday)
        addRange("2024-04-04", "2024-04-06", "清明节")
        add(["2024-04-07"], "清明调休", .adjustedWorkday)
        addRange("2024-05-01", "2024-05-05", "劳动节")
        add(["2024-04-28", "2024-05-11"], "劳动节调休", .adjustedWorkday)
        add(["2024-06-10"], "端午节")
        addRange("2024-09-15", "2024-09-17", "中秋节")
        add(["2024-09-14"], "中秋调休", .adjustedWorkday)
        addRange("2024-10-01", "2024-10-07", "国庆节")
        add(["2024-09-29", "2024-10-12"], "国庆调休", .adjustedWorkday)

        // 国务院办公厅 2025 年部分节假日安排（国办发明电〔2024〕12号）
        add(["2025-01-01"], "元旦")
        addRange("2025-01-28", "2025-02-04", "春节")
        add(["2025-01-26", "2025-02-08"], "春节调休", .adjustedWorkday)
        addRange("2025-04-04", "2025-04-06", "清明节")
        addRange("2025-05-01", "2025-05-05", "劳动节")
        add(["2025-04-27"], "劳动节调休", .adjustedWorkday)
        addRange("2025-05-31", "2025-06-02", "端午节")
        addRange("2025-10-01", "2025-10-08", "国庆·中秋")
        add(["2025-09-28", "2025-10-11"], "国庆调休", .adjustedWorkday)

        // 国务院办公厅 2026 年部分节假日安排（国办发明电〔2025〕7号）
        addRange("2026-01-01", "2026-01-03", "元旦")
        add(["2026-01-04"], "元旦调休", .adjustedWorkday)
        addRange("2026-02-15", "2026-02-23", "春节")
        add(["2026-02-14", "2026-02-28"], "春节调休", .adjustedWorkday)
        addRange("2026-04-04", "2026-04-06", "清明节")
        addRange("2026-05-01", "2026-05-05", "劳动节")
        add(["2026-05-09"], "劳动节调休", .adjustedWorkday)
        addRange("2026-06-19", "2026-06-21", "端午节")
        addRange("2026-09-25", "2026-09-27", "中秋节")
        addRange("2026-10-01", "2026-10-07", "国庆节")
        add(["2026-09-20", "2026-10-10"], "国庆调休", .adjustedWorkday)

        return result
    }()
}

enum CalendarTagPalette {
    static let names = ["orange", "blue", "green", "purple", "pink", "gray"]

    static func color(named name: String) -> Color {
        switch name {
        case "blue": return .blue
        case "green": return .green
        case "purple": return .purple
        case "pink": return .pink
        case "gray": return .gray
        default: return Color(red: 0.96, green: 0.43, blue: 0.27)
        }
    }
}
