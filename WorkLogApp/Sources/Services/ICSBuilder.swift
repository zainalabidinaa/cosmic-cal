import CoreLocation
import Foundation

enum ICSBuilder {
    /// Builds a VCALENDAR string with Apple-proprietary travel time properties.
    ///
    /// The generated iCalendar includes `X-APPLE-TRAVEL-START`, `X-APPLE-TRAVEL-DURATION`,
    /// `X-APPLE-STRUCTURED-LOCATION`, and travel-aware `VALARM` triggers so that Apple Calendar
    /// displays "Based on location" driving travel time natively.
    static func buildEvent(
        uid: String,
        title: String,
        start: Date,
        end: Date,
        location: String,
        locationCoordinate: CLLocationCoordinate2D?,
        travelStartTitle: String?,
        travelStartAddress: String,
        travelStartCoordinate: CLLocationCoordinate2D?,
        travelDurationMinutes: Int?,
        travelStartIsCurrentLocation: Bool
    ) -> String {
        let dtstart = icsDateString(from: start)
        let dtend = icsDateString(from: end)
        let dtstamp = icsDateString(from: Date())

        var lines = [
            "BEGIN:VCALENDAR",
            "VERSION:2.0",
            "CALSCALE:GREGORIAN",
            "PRODID:-//WorkLog//LMBLund//EN",
            "BEGIN:VEVENT",
            "UID:\(uid)",
            "DTSTAMP:\(dtstamp)",
            "DTSTART:\(dtstart)",
            "DTEND:\(dtend)",
            "SUMMARY:\(icsEscape(title))",
            "LOCATION:\(icsEscape(location))",
        ]

        if let coord = locationCoordinate {
            let locLine = "X-APPLE-STRUCTURED-LOCATION;VALUE=URI"
                + ";X-ADDRESS=\(icsParamEscape(location))"
                + ";X-APPLE-RADIUS=70"
                + ";X-TITLE=\(icsParamEscape(title))"
                + ":geo:\(coord.latitude),\(coord.longitude)"
            lines.append(locLine)
        }

        let startTitle = travelStartTitle ?? travelStartAddress
        var travelLine = "X-APPLE-TRAVEL-START;ROUTING=CAR;VALUE=URI"
            + ";X-ADDRESS=\(icsParamEscape(travelStartAddress))"
            + ";X-TITLE=\(icsParamEscape(startTitle))"
            + ":"
        if travelStartIsCurrentLocation {
            travelLine += "current-location"
        } else if let coord = travelStartCoordinate {
            travelLine += "geo:\(coord.latitude),\(coord.longitude)"
        }
        lines.append(travelLine)

        if let travelDurationMinutes {
            lines.append("X-APPLE-TRAVEL-DURATION;VALUE=DURATION:PT\(travelDurationMinutes)M")

            // Alarm: at travel time start (time to leave)
            appendAlarm(to: &lines, beforeTravelMinutes: 0, travelMinutes: travelDurationMinutes)
            // Alarm: 30 min before travel
            appendAlarm(to: &lines, beforeTravelMinutes: 30, travelMinutes: travelDurationMinutes)
            // Alarm: 1 hour before travel
            appendAlarm(to: &lines, beforeTravelMinutes: 60, travelMinutes: travelDurationMinutes)
        }

        lines.append("END:VEVENT")
        lines.append("END:VCALENDAR")

        return lines.joined(separator: "\r\n")
    }

    // MARK: - Helpers

    private static func appendAlarm(to lines: inout [String], beforeTravelMinutes: Int, travelMinutes: Int) {
        let totalMinutes = travelMinutes + beforeTravelMinutes
        lines.append("BEGIN:VALARM")
        lines.append("ACTION:DISPLAY")
        lines.append("DESCRIPTION:Event reminder")
        lines.append("TRIGGER;X-APPLE-RELATED-TRAVEL=-PT\(beforeTravelMinutes)M:-PT\(totalMinutes)M")
        lines.append("END:VALARM")
    }

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyyMMdd'T'HHmmss'Z'"
        f.timeZone = TimeZone(identifier: "UTC")
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()

    private static func icsDateString(from date: Date) -> String {
        dateFormatter.string(from: date)
    }

    private static func icsEscape(_ text: String) -> String {
        text.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: ",", with: "\\,")
            .replacingOccurrences(of: ";", with: "\\;")
            .replacingOccurrences(of: "\n", with: "\\n")
    }

    private static func icsParamEscape(_ text: String) -> String {
        text.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\n", with: "\\n")
    }
}
