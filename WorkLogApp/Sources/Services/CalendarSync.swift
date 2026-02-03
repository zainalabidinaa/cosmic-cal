import CoreLocation
import EventKit
import Foundation
import MapKit

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

@MainActor
final class CalendarSync {
    private let eventStore = EKEventStore()
    private let locationClient = LocationClient()

    private let destinationAddress = "Akutgatan 8, Lund"
    private let fallbackTravelTime: TimeInterval = 45 * 60

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

    func upsertEvent(for log: WorkLog) async throws -> String {
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
        event.title = "LMB Lund"
        event.startDate = log.start
        event.endDate = log.end

        event.location = destinationAddress
        let structuredDestination = EKStructuredLocation(title: destinationAddress)

        if let destinationCoordinate = try? await geocode(address: destinationAddress) {
            structuredDestination.geoLocation = CLLocation(latitude: destinationCoordinate.latitude, longitude: destinationCoordinate.longitude)
        }

        event.structuredLocation = structuredDestination

        let travelTimeSeconds = await estimateTravelTimeSeconds(to: structuredDestination.geoLocation) ?? fallbackTravelTime
        event.travelTime = travelTimeSeconds

        applyDefaultAlarms(to: event, travelTime: travelTimeSeconds)

        try eventStore.save(event, span: .thisEvent, commit: true)
        return event.eventIdentifier
    }

    private func applyDefaultAlarms(to event: EKEvent, travelTime: TimeInterval) {
        let leaveTime = event.startDate.addingTimeInterval(-travelTime)

        let alarmDates: [Date] = [
            leaveTime.addingTimeInterval(-2 * 60 * 60),
            leaveTime.addingTimeInterval(-1 * 60 * 60),
            leaveTime.addingTimeInterval(-30 * 60),
            leaveTime
        ]

        event.alarms = alarmDates
            .sorted()
            .map { EKAlarm(absoluteDate: $0) }
    }

    private func geocode(address: String) async throws -> CLLocationCoordinate2D {
        let geocoder = CLGeocoder()
        return try await withCheckedThrowingContinuation { continuation in
            geocoder.geocodeAddressString(address) { placemarks, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }

                guard let coordinate = placemarks?.first?.location?.coordinate else {
                    continuation.resume(throwing: NSError(domain: "CalendarSync", code: 1))
                    return
                }

                continuation.resume(returning: coordinate)
            }
        }
    }

    private func estimateTravelTimeSeconds(to destination: CLLocation?) async -> TimeInterval? {
        guard let destination else {
            return nil
        }

        guard let current = try? await locationClient.fetchLocation() else {
            return nil
        }

        let request = MKDirections.Request()
        request.source = MKMapItem(placemark: MKPlacemark(coordinate: current.coordinate))
        request.destination = MKMapItem(placemark: MKPlacemark(coordinate: destination.coordinate))
        request.transportType = .automobile

        let directions = MKDirections(request: request)
        return await withCheckedContinuation { continuation in
            directions.calculate { response, _ in
                let best = response?.routes.min(by: { $0.expectedTravelTime < $1.expectedTravelTime })
                continuation.resume(returning: best?.expectedTravelTime)
            }
        }
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

@MainActor
private final class LocationClient: NSObject, CLLocationManagerDelegate {
    enum LocationError: Error {
        case denied
        case restricted
        case unavailable
    }

    private let manager = CLLocationManager()
    private var authorizationContinuation: CheckedContinuation<Void, Error>?
    private var locationContinuation: CheckedContinuation<CLLocation, Error>?

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
    }

    func fetchLocation() async throws -> CLLocation {
        guard CLLocationManager.locationServicesEnabled() else {
            throw LocationError.unavailable
        }

        switch manager.authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse:
            break
        case .notDetermined:
            try await requestAuthorization()
        case .denied:
            throw LocationError.denied
        case .restricted:
            throw LocationError.restricted
        @unknown default:
            throw LocationError.unavailable
        }

        return try await requestOneShotLocation()
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        guard let continuation = authorizationContinuation else { return }

        switch manager.authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse:
            authorizationContinuation = nil
            continuation.resume()
        case .denied:
            authorizationContinuation = nil
            continuation.resume(throwing: LocationError.denied)
        case .restricted:
            authorizationContinuation = nil
            continuation.resume(throwing: LocationError.restricted)
        case .notDetermined:
            break
        @unknown default:
            authorizationContinuation = nil
            continuation.resume(throwing: LocationError.unavailable)
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let continuation = locationContinuation else { return }
        locationContinuation = nil

        if let location = locations.first {
            continuation.resume(returning: location)
        } else {
            continuation.resume(throwing: LocationError.unavailable)
        }
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        guard let continuation = locationContinuation else { return }
        locationContinuation = nil
        continuation.resume(throwing: error)
    }

    private func requestAuthorization() async throws {
        try await withCheckedThrowingContinuation { continuation in
            authorizationContinuation = continuation
            manager.requestWhenInUseAuthorization()
        }
    }

    private func requestOneShotLocation() async throws -> CLLocation {
        try await withCheckedThrowingContinuation { continuation in
            locationContinuation = continuation
            manager.requestLocation()
        }
    }
}
