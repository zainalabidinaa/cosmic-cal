import Foundation

struct WorkLog: Identifiable, Codable, Equatable {
    var id: UUID
    /// Local-time start of day; used for sorting and day uniqueness.
    var day: Date
    var start: Date
    var end: Date
    var calendarEventIdentifier: String?
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        day: Date,
        start: Date,
        end: Date,
        calendarEventIdentifier: String? = nil,
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.day = day
        self.start = start
        self.end = end
        self.calendarEventIdentifier = calendarEventIdentifier
        self.updatedAt = updatedAt
    }

    var dayKey: String {
        DateKeyFormatter.shared.string(from: day)
    }
}

final class DateKeyFormatter {
    static let shared = DateKeyFormatter()

    private let formatter: DateFormatter

    private init() {
        let formatter = DateFormatter()
        formatter.calendar = .current
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd"
        self.formatter = formatter
    }

    func string(from date: Date) -> String {
        formatter.string(from: date)
    }
}

extension Date {
    func startOfLocalDay() -> Date {
        Calendar.current.startOfDay(for: self)
    }

    static func at(day: Date, hour: Int, minute: Int) -> Date {
        let calendar = Calendar.current
        var components = calendar.dateComponents([.year, .month, .day], from: day)
        components.hour = hour
        components.minute = minute
        components.second = 0
        return calendar.date(from: components) ?? day
    }

    static func combining(day: Date, time: Date) -> Date {
        let calendar = Calendar.current
        let dayComponents = calendar.dateComponents([.year, .month, .day], from: day)
        let timeComponents = calendar.dateComponents([.hour, .minute], from: time)
        var components = DateComponents()
        components.year = dayComponents.year
        components.month = dayComponents.month
        components.day = dayComponents.day
        components.hour = timeComponents.hour
        components.minute = timeComponents.minute
        components.second = 0
        return calendar.date(from: components) ?? day
    }
}
