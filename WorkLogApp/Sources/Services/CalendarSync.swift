import EventKit
import Foundation

enum CalendarSyncError: LocalizedError {
    case permissionDenied
    case noWritableCalendar

    var errorDescription: String? {
        switch self {
        case .permissionDenied:
            return "Calendar access was denied."
        case .noWritableCalendar:
            return "No writable calendar was found."
        }
    }
}

final class CalendarSync {
    private let eventStore = EKEventStore()

    func requestAccessIfNeeded() async throws {
        let status = EKEventStore.authorizationStatus(for: .event)
        switch status {
        case .authorized, .fullAccess, .writeOnly:
            return
        case .denied, .restricted:
            throw CalendarSyncError.permissionDenied
        case .notDetermined:
            let granted: Bool
            if #available(iOS 17.0, *) {
                granted = try await withCheckedThrowingContinuation { continuation in
                    eventStore.requestFullAccessToEvents { isGranted, error in
                        if let error {
                            continuation.resume(throwing: error)
                            return
                        }
                        continuation.resume(returning: isGranted)
                    }
                }
            } else {
                granted = try await withCheckedThrowingContinuation { continuation in
                    eventStore.requestAccess(to: .event) { isGranted, error in
                        if let error {
                            continuation.resume(throwing: error)
                            return
                        }
                        continuation.resume(returning: isGranted)
                    }
                }
            }

            if !granted {
                throw CalendarSyncError.permissionDenied
            }
        @unknown default:
            throw CalendarSyncError.permissionDenied
        }
    }

    func upsertEvent(for log: WorkLog) throws -> String {
        let calendar = findPreferredCalendar(named: "Arbete") ?? eventStore.defaultCalendarForNewEvents
        guard let calendar else {
            throw CalendarSyncError.noWritableCalendar
        }

        let event: EKEvent
        if let existingId = log.calendarEventIdentifier,
           let existing = eventStore.event(withIdentifier: existingId) {
            event = existing
        } else {
            event = EKEvent(eventStore: eventStore)
        }

        event.calendar = calendar
        event.title = "Labmedicin LU"
        event.location = "Akutgatan 8, Lund"
        event.startDate = log.start
        event.endDate = log.end

        try eventStore.save(event, span: .thisEvent, commit: true)
        return event.eventIdentifier
    }

    private func findPreferredCalendar(named name: String) -> EKCalendar? {
        let candidates = eventStore.calendars(for: .event)
            .filter { $0.title == name && $0.allowsContentModifications }

        if let caldav = candidates.first(where: { $0.type == .calDAV }) {
            return caldav
        }

        if let local = candidates.first(where: { $0.type == .local }) {
            return local
        }

        return candidates.first
    }
}
