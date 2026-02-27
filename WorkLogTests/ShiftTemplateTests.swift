import XCTest
@testable import WorkLog

final class ShiftTemplateTests: XCTestCase {
    func testLabel() {
        let template = ShiftTemplate(startHour: 8, startMinute: 0, endHour: 16, endMinute: 30)
        XCTAssertEqual(template.label, "08:00–16:30")
    }

    func testLabelLeadingZeros() {
        let template = ShiftTemplate(startHour: 7, startMinute: 5, endHour: 15, endMinute: 0)
        XCTAssertEqual(template.label, "07:05–15:00")
    }

    func testDefaultTemplatesCount() {
        XCTAssertEqual(ShiftTemplate.defaults.count, 3)
    }

    func testDefaultTemplatesAreUnique() {
        let ids = ShiftTemplate.defaults.map(\.id)
        XCTAssertEqual(Set(ids).count, ids.count)
    }

    func testCodableRoundTrip() throws {
        let original = ShiftTemplate(startHour: 10, startMinute: 10, endHour: 19, endMinute: 0)
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(ShiftTemplate.self, from: data)
        XCTAssertEqual(original, decoded)
    }
}
