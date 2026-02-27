import XCTest
@testable import WorkLog

final class WorkLogModelTests: XCTestCase {
    func testDayKeyFormat() {
        let date = makeDate(year: 2025, month: 6, day: 15)
        let log = WorkLog(day: date, start: date, end: date)
        XCTAssertEqual(log.dayKey, "2025-06-15")
    }

    func testDurationHoursAndMinutes() {
        let day = Date().startOfLocalDay()
        let start = Date.at(day: day, hour: 8, minute: 0)
        let end = Date.at(day: day, hour: 16, minute: 30)
        let log = WorkLog(day: day, start: start, end: end)
        XCTAssertEqual(log.duration, 8.5 * 3600, accuracy: 1)
        XCTAssertEqual(log.durationLabel, "8h 30m")
    }

    func testDurationHoursOnly() {
        let day = Date().startOfLocalDay()
        let start = Date.at(day: day, hour: 8, minute: 0)
        let end = Date.at(day: day, hour: 16, minute: 0)
        let log = WorkLog(day: day, start: start, end: end)
        XCTAssertEqual(log.durationLabel, "8h")
    }

    func testDurationMinutesOnly() {
        let day = Date().startOfLocalDay()
        let start = Date.at(day: day, hour: 8, minute: 0)
        let end = Date.at(day: day, hour: 8, minute: 45)
        let log = WorkLog(day: day, start: start, end: end)
        XCTAssertEqual(log.durationLabel, "45m")
    }

    func testCombiningDayAndTime() {
        let day = makeDate(year: 2025, month: 3, day: 10)
        let time = Date.at(day: Date(), hour: 14, minute: 30)
        let combined = Date.combining(day: day, time: time)
        let cal = Calendar.current
        XCTAssertEqual(cal.component(.year, from: combined), 2025)
        XCTAssertEqual(cal.component(.month, from: combined), 3)
        XCTAssertEqual(cal.component(.day, from: combined), 10)
        XCTAssertEqual(cal.component(.hour, from: combined), 14)
        XCTAssertEqual(cal.component(.minute, from: combined), 30)
    }

    func testStartOfLocalDay() {
        let date = Date.at(day: Date(), hour: 15, minute: 45)
        let start = date.startOfLocalDay()
        let cal = Calendar.current
        XCTAssertEqual(cal.component(.hour, from: start), 0)
        XCTAssertEqual(cal.component(.minute, from: start), 0)
    }

    func testAtDayHourMinute() {
        let day = makeDate(year: 2025, month: 1, day: 20)
        let result = Date.at(day: day, hour: 9, minute: 15)
        let cal = Calendar.current
        XCTAssertEqual(cal.component(.hour, from: result), 9)
        XCTAssertEqual(cal.component(.minute, from: result), 15)
        XCTAssertEqual(cal.component(.second, from: result), 0)
    }

    func testEquality() {
        let id = UUID()
        let day = Date().startOfLocalDay()
        let start = Date.at(day: day, hour: 8, minute: 0)
        let end = Date.at(day: day, hour: 16, minute: 0)
        let date = Date()
        let a = WorkLog(id: id, day: day, start: start, end: end, updatedAt: date)
        let b = WorkLog(id: id, day: day, start: start, end: end, updatedAt: date)
        XCTAssertEqual(a, b)
    }

    private func makeDate(year: Int, month: Int, day: Int) -> Date {
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        components.hour = 0
        components.minute = 0
        return Calendar.current.date(from: components)!
    }
}
