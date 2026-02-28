import Foundation

@MainActor
final class WorkLogStore: ObservableObject {
    @Published private(set) var logs: [WorkLog] = []
    @Published var requestedEditDay: Date?

    @Published var lastSaveMessage: String?
    @Published var lastErrorMessage: String?

    let settings: AppSettings
    private let calendarSync: CalendarSync

    private let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()

    private let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()

    init(settings: AppSettings) {
        self.settings = settings
        self.calendarSync = CalendarSync(settings: settings)
        loadFromDisk()
    }

    func requestEdit(day: Date) {
        requestedEditDay = day.startOfLocalDay()
    }

    func log(for day: Date) -> WorkLog? {
        let key = DateKeyFormatter.shared.string(from: day.startOfLocalDay())
        return logs.first(where: { $0.dayKey == key })
    }

    func upsertLog(day: Date, start: Date, end: Date) async {
        lastSaveMessage = nil
        lastErrorMessage = nil

        let dayStart = day.startOfLocalDay()
        let startDate = Date.combining(day: dayStart, time: start)
        let endDate = Date.combining(day: dayStart, time: end)

        guard endDate > startDate else {
            lastErrorMessage = "End time must be after start time."
            return
        }

        var existing = log(for: dayStart)
        if existing != nil {
            existing?.start = startDate
            existing?.end = endDate
            existing?.updatedAt = Date()
        }

        let logToSave = existing ?? WorkLog(day: dayStart, start: startDate, end: endDate)

        do {
            let result = try await calendarSync.syncEvent(for: logToSave)

            var saved = logToSave
            switch result {
            case .eventKit(let eventId):
                if let legacyUID = saved.calDAVUID {
                    Task { await calendarSync.deleteCalDAVEvent(uid: legacyUID) }
                }
                saved.calendarEventIdentifier = eventId
                saved.calDAVUID = nil
            case .calDAV(let uid):
                saved.calDAVUID = uid
            }
            saved.updatedAt = Date()

            logs.removeAll(where: { $0.dayKey == saved.dayKey })
            logs.append(saved)
            logs.sort(by: { $0.day > $1.day })

            try persistToDisk()

            let method: String
            switch result {
            case .eventKit:
                method = "EventKit · \(settings.calendarName)"
            case .calDAV:
                method = settings.travelTimeMode == .dynamicDriving ? "CalDAV · dynamic driving" : "CalDAV · fixed estimate"
            }
            lastSaveMessage = "Saved and synced via \(method)."
        } catch {
            logs.removeAll(where: { $0.dayKey == logToSave.dayKey })
            logs.append(logToSave)
            logs.sort(by: { $0.day > $1.day })
            try? persistToDisk()

            lastErrorMessage = "Saved locally, but sync failed: \(error.localizedDescription)"
        }
    }

    func deleteLog(_ log: WorkLog) {
        if let uid = log.calDAVUID {
            Task { await calendarSync.deleteCalDAVEvent(uid: uid) }
        }
        if let eventId = log.calendarEventIdentifier {
            calendarSync.deleteEvent(identifier: eventId)
        }
        logs.removeAll(where: { $0.id == log.id })
        try? persistToDisk()
    }

    // MARK: - Disk

    private func loadFromDisk() {
        let url = storageURL()
        guard let data = try? Data(contentsOf: url) else {
            logs = []
            return
        }

        guard let decoded = try? decoder.decode([WorkLog].self, from: data) else {
            logs = []
            return
        }

        logs = decoded.sorted(by: { $0.day > $1.day })
    }

    private func persistToDisk() throws {
        let url = storageURL(creatingDirectories: true)
        let data = try encoder.encode(logs)
        try data.write(to: url, options: [.atomic])
    }

    private func storageURL(creatingDirectories: Bool = false) -> URL {
        let fileManager = FileManager.default
        let base = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = base.appendingPathComponent("WorkLog", isDirectory: true)

        if creatingDirectories {
            try? fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        }

        return dir.appendingPathComponent("worklogs.json", isDirectory: false)
    }
}
