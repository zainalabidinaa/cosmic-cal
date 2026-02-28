import CoreLocation
import Foundation

enum ICSBuilder {
    // MARK: - Public API

    /// Builds a VCALENDAR string matching Apple Calendar's native travel-time format.
    ///
    /// Property order, parameter names, quoting, REFERENCEFRAME values, and line-folding
    /// are all derived from real VEVENT exports of Apple Calendar events that have travel
    /// time enabled — verified against /Users/zain/Documents/Arbete.ics (2026-02-24/25).
    ///
    /// - Parameters:
    ///   - uid: Unique event identifier (e.g. UUID + "@worklog")
    ///   - title: Event summary / title
    ///   - start: Event start date (will be emitted with Stockholm timezone)
    ///   - end: Event end date
    ///   - location: Destination address string (used for LOCATION and X-TITLE)
    ///   - locationCoordinate: Geocoded destination coordinate
    ///   - travelStartTitle: Short label for the origin (e.g. "Current Location" or street name)
    ///   - travelStartAddress: Full address of origin (nil for Current Location)
    ///   - travelStartCoordinate: Geocoded origin coordinate
    ///   - travelDurationMinutes: Estimated travel minutes (always emitted)
    ///   - travelStartIsCurrentLocation: true → omit X-ADDRESS and X-APPLE-RADIUS on origin
    ///   - creatorIdentity: Bundle ID + team suffix for X-APPLE-CREATOR-IDENTITY
    static func buildEvent(
        uid: String,
        title: String,
        start: Date,
        end: Date,
        location: String,
        locationCoordinate: CLLocationCoordinate2D?,
        travelStartTitle: String?,
        travelStartAddress: String?,
        travelStartCoordinate: CLLocationCoordinate2D?,
        travelDurationMinutes: Int,
        travelStartIsCurrentLocation: Bool,
        creatorIdentity: String = "com.zainalabidinaa.labmedicinlu.27FUHMHBAD"
    ) -> String {
        let dtstart = icsLocalDateString(from: start)
        let dtend   = icsLocalDateString(from: end)
        let dtstamp = icsUTCDateString(from: Date())

        var lines: [String] = [
            "BEGIN:VCALENDAR",
            "VERSION:2.0",
            "CALSCALE:GREGORIAN",
            "PRODID:-//WorkLog//LMBLund//EN",
            // VTIMEZONE is required by RFC 5545 whenever TZID is referenced.
            // Without it iCloud CalDAV returns a 400/207 error and the PUT fails,
            // which causes the silent fallthrough to EventKit → double events.
            "BEGIN:VTIMEZONE",
            "TZID:Europe/Stockholm",
            "BEGIN:STANDARD",
            "TZOFFSETFROM:+0200",
            "TZOFFSETTO:+0100",
            "TZNAME:CET",
            "DTSTART:19701025T030000",
            "RRULE:FREQ=YEARLY;BYDAY=-1SU;BYMONTH=10",
            "END:STANDARD",
            "BEGIN:DAYLIGHT",
            "TZOFFSETFROM:+0100",
            "TZOFFSETTO:+0200",
            "TZNAME:CEST",
            "DTSTART:19700329T020000",
            "RRULE:FREQ=YEARLY;BYDAY=-1SU;BYMONTH=3",
            "END:DAYLIGHT",
            "END:VTIMEZONE",
            "BEGIN:VEVENT",
            "CREATED:\(dtstamp)",
            "DTEND;TZID=Europe/Stockholm:\(dtend)",
            "DTSTAMP:\(dtstamp)",
            "DTSTART;TZID=Europe/Stockholm:\(dtstart)",
            "LAST-MODIFIED:\(dtstamp)",
            "LOCATION:\(icsEscape(location))",
            "SEQUENCE:0",
            "SUMMARY:\(icsEscape(title))",
            "TRANSP:OPAQUE",
            "UID:\(uid)",
            "X-APPLE-CREATOR-IDENTITY:\(creatorIdentity)",
            "X-APPLE-CREATOR-TEAM-IDENTITY:27FUHMHBAD",
        ]

        // X-APPLE-STRUCTURED-LOCATION (destination)
        // REFERENCEFRAME=0 on destination — verified from Apple Calendar export.
        // X-TITLE = the address string, quoted (it contains a comma).
        // No X-ADDRESS here — Apple doesn't put it on the destination property.
        if let coord = locationCoordinate {
            let locLine = "X-APPLE-STRUCTURED-LOCATION;VALUE=URI"
                + ";X-APPLE-REFERENCEFRAME=0"
                + ";X-TITLE=\(quotedParam(location))"
                + ":geo:\(coord.latitude),\(coord.longitude)"
            lines.append(contentsOf: foldLine(locLine))
        }

        // X-APPLE-TRAVEL-DURATION — always emitted (never omitted for dynamic mode either)
        lines.append("X-APPLE-TRAVEL-DURATION;VALUE=DURATION:PT\(travelDurationMinutes)M")

        // X-APPLE-TRAVEL-START (origin)
        // REFERENCEFRAME=1 on origin — verified from Apple Calendar export.
        // For Current Location: no X-ADDRESS, no X-APPLE-RADIUS.
        // For custom address: X-ADDRESS with \\n newlines, X-APPLE-RADIUS=100.
        if let coord = travelStartCoordinate {
            let originTitle = travelStartTitle ?? "Current Location"
            var travelLine = "X-APPLE-TRAVEL-START;VALUE=URI"
            if !travelStartIsCurrentLocation, let addr = travelStartAddress, !addr.isEmpty {
                // Address with \\n line separators (no quoting — Apple doesn't quote X-ADDRESS)
                let escapedAddr = addr
                    .replacingOccurrences(of: "\n", with: "\\n")
                    .replacingOccurrences(of: "\r\n", with: "\\n")
                travelLine += ";X-ADDRESS=\(escapedAddr)"
                travelLine += ";X-APPLE-RADIUS=100"
            }
            travelLine += ";X-APPLE-REFERENCEFRAME=1"
            // X-TITLE: quote only if it contains a comma
            travelLine += ";X-TITLE=\(quotedParam(originTitle))"
            travelLine += ":geo:\(coord.latitude),\(coord.longitude)"
            lines.append(contentsOf: foldLine(travelLine))
        }

        // Match the target run behavior: only 30m and 1h reminders.
        appendAlarm(to: &lines, trigger: "-PT30M")
        appendAlarm(to: &lines, trigger: "-PT1H")

        // Silent alarm marker (Apple Calendar always adds this)
        lines += [
            "BEGIN:VALARM",
            "ACTION:NONE",
            "TRIGGER;VALUE=DATE-TIME:19760401T005545Z",
            "END:VALARM",
        ]

        lines += [
            "END:VEVENT",
            "END:VCALENDAR",
        ]

        return lines.joined(separator: "\r\n")
    }

    // MARK: - Alarm helper

    private static func appendAlarm(
        to lines: inout [String],
        trigger: String
    ) {
        let uuid = UUID().uuidString.uppercased()
        lines += [
            "BEGIN:VALARM",
            "ACTION:DISPLAY",
            "DESCRIPTION:Reminder",
            "TRIGGER:\(trigger)",
            "UID:\(uuid)",
            "X-WR-ALARMUID:\(uuid)",
            "END:VALARM",
        ]
    }

    // MARK: - RFC 5545 line folding

    /// Folds a long ICS property line at 75 octets (UTF-8 bytes).
    /// Continuation lines start with a single SPACE character.
    /// Returns an array of line strings that will be joined with CRLF.
    private static func foldLine(_ line: String) -> [String] {
        var result: [String] = []
        var remaining = line
        var isFirst = true

        while !remaining.isEmpty {
            let limit = isFirst ? 75 : 74  // first line: 75, continuation: 74 + leading space
            var chunk = ""
            var byteCount = 0

            for char in remaining {
                let charBytes = String(char).utf8.count
                if byteCount + charBytes > limit {
                    break
                }
                chunk.append(char)
                byteCount += charBytes
            }

            if chunk.isEmpty {
                // Single character longer than limit — take it anyway to avoid infinite loop
                chunk = String(remaining.prefix(1))
            }

            result.append(isFirst ? chunk : " " + chunk)
            remaining = String(remaining.dropFirst(chunk.count))
            isFirst = false
        }

        return result.isEmpty ? [line] : result
    }

    // MARK: - Parameter quoting

    /// Returns the value quoted with double-quotes if it contains a comma,
    /// otherwise returns it unquoted. Matches Apple Calendar's selective quoting.
    private static func quotedParam(_ value: String) -> String {
        if value.contains(",") {
            // Escape any existing double-quotes inside
            let escaped = value.replacingOccurrences(of: "\"", with: "\\\"")
            return "\"\(escaped)\""
        }
        return value
    }

    // MARK: - Value escaping (for SUMMARY, LOCATION, DESCRIPTION)

    private static func icsEscape(_ text: String) -> String {
        text
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: ",", with: "\\,")
            .replacingOccurrences(of: ";", with: "\\;")
            .replacingOccurrences(of: "\n", with: "\\n")
    }

    // MARK: - Date formatters

    private static let utcFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyyMMdd'T'HHmmss'Z'"
        f.timeZone = TimeZone(identifier: "UTC")
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()

    private static let localFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyyMMdd'T'HHmmss"
        f.timeZone = TimeZone(identifier: "Europe/Stockholm")
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()

    private static func icsUTCDateString(from date: Date) -> String {
        utcFormatter.string(from: date)
    }

    private static func icsLocalDateString(from date: Date) -> String {
        localFormatter.string(from: date)
    }
}
