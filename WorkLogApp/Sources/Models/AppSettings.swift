import Foundation

enum TravelOriginMode: String, Codable, CaseIterable, Identifiable {
    case currentLocation
    case customAddress

    var id: String { rawValue }

    var title: String {
        switch self {
        case .currentLocation:
            return "Current"
        case .customAddress:
            return "Custom"
        }
    }
}

struct ShiftTemplate: Identifiable, Codable, Equatable {
    var id = UUID()
    var startHour: Int
    var startMinute: Int
    var endHour: Int
    var endMinute: Int

    var label: String {
        String(format: "%02d:%02d–%02d:%02d", startHour, startMinute, endHour, endMinute)
    }

    static let defaults: [ShiftTemplate] = [
        ShiftTemplate(startHour: 8, startMinute: 0, endHour: 16, endMinute: 30),
        ShiftTemplate(startHour: 8, startMinute: 30, endHour: 17, endMinute: 0),
        ShiftTemplate(startHour: 10, startMinute: 10, endHour: 19, endMinute: 0),
    ]
}

@MainActor
final class AppSettings: ObservableObject {
    @Published var destinationAddress: String { didSet { persistIfReady() } }
    @Published var travelOriginMode: TravelOriginMode { didSet { persistIfReady() } }
    @Published var originFallbackAddress: String { didSet { persistIfReady() } }
    @Published var calendarName: String { didSet { persistIfReady() } }
    @Published var eventTitle: String { didSet { persistIfReady() } }
    @Published var shiftTemplates: [ShiftTemplate] { didSet { persistIfReady() } }
    @Published var iCloudEmail: String { didSet { persistIfReady() } }

    var calDAVConfigured: Bool {
        !iCloudEmail.isEmpty && KeychainHelper.loadPassword(account: iCloudEmail) != nil
    }

    private var ready = false

    init() {
        let stored = Self.loadFromDisk()
        let normalizedEventTitle = stored.eventTitle == "LMB Lund" ? "LMB" : stored.eventTitle
        _destinationAddress = Published(initialValue: stored.destinationAddress)
        _travelOriginMode = Published(initialValue: stored.travelOriginMode)
        _originFallbackAddress = Published(initialValue: stored.originFallbackAddress)
        _calendarName = Published(initialValue: stored.calendarName)
        _eventTitle = Published(initialValue: normalizedEventTitle)
        _shiftTemplates = Published(initialValue: stored.shiftTemplates)
        _iCloudEmail = Published(initialValue: stored.iCloudEmail)
        ready = true
    }

    func resetToDefaults() {
        if !iCloudEmail.isEmpty {
            KeychainHelper.deletePassword(account: iCloudEmail)
        }
        let defaults = SettingsData()
        destinationAddress = defaults.destinationAddress
        travelOriginMode = defaults.travelOriginMode
        originFallbackAddress = defaults.originFallbackAddress
        calendarName = defaults.calendarName
        eventTitle = defaults.eventTitle
        shiftTemplates = defaults.shiftTemplates
        iCloudEmail = defaults.iCloudEmail
    }

    private func persistIfReady() {
        guard ready else { return }
        let payload = SettingsData(
            destinationAddress: destinationAddress,
            travelOriginMode: travelOriginMode,
            originFallbackAddress: originFallbackAddress,
            calendarName: calendarName,
            eventTitle: eventTitle,
            shiftTemplates: shiftTemplates,
            iCloudEmail: iCloudEmail
        )
        guard let encoded = try? JSONEncoder().encode(payload) else { return }
        UserDefaults.standard.set(encoded, forKey: "AppSettingsV1")
    }

    private static func loadFromDisk() -> SettingsData {
        guard let data = UserDefaults.standard.data(forKey: "AppSettingsV1"),
              let decoded = try? JSONDecoder().decode(SettingsData.self, from: data) else {
            return SettingsData()
        }
        return decoded
    }
}

private struct SettingsData: Codable {
    var destinationAddress = "Akutgatan 8, Lund"
    var travelOriginMode: TravelOriginMode = .currentLocation
    var originFallbackAddress = "Traktörsgatan 11, Helsingborg"
    var calendarName = "Arbete"
    var eventTitle = "LMB"
    var shiftTemplates = ShiftTemplate.defaults
    var iCloudEmail = ""
}
