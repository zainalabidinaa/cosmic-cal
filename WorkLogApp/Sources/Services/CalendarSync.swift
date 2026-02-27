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

enum SyncResult {
    case eventKit(String)
    case calDAV(String)
}

@MainActor
final class CalendarSync {
    private let eventStore = EKEventStore()
    private let locationClient = LocationClient()
    private let calDAVClient = CalDAVClient()
    private let settings: AppSettings

    private let fallbackTravelTime: TimeInterval = 45 * 60

    init(settings: AppSettings) {
        self.settings = settings
    }

    var calDAVAvailable: Bool { settings.calDAVConfigured }

    // MARK: - Unified Sync

    func syncEvent(for log: WorkLog) async throws -> SyncResult {
        // Prefer EventKit first for the most reliable travel-time behavior on device.
        do {
            try await requestAccessIfNeeded()
            let eventId = try await upsertEvent(for: log)
            return .eventKit(eventId)
        } catch {
            // If EventKit fails (e.g. permission denied), fall back to CalDAV when configured.
            if let credentials = makeCalDAVCredentials() {
                let uid = try await upsertViaCalDAV(for: log, credentials: credentials)
                return .calDAV(uid)
            }
            throw error
        }
    }

    func deleteCalDAVEvent(uid: String) async {
        guard let credentials = makeCalDAVCredentials() else { return }
        do {
            let calURL = try await calDAVClient.calendarURL(
                for: settings.calendarName,
                credentials: credentials
            )
            try await calDAVClient.deleteEvent(calendarURL: calURL, uid: uid, credentials: credentials)
        } catch {
            // Best-effort; the local log is still removed.
        }
    }

    private func makeCalDAVCredentials() -> CalDAVCredentials? {
        let email = settings.iCloudEmail
        guard !email.isEmpty, let password = KeychainHelper.loadPassword(account: email) else {
            return nil
        }
        return CalDAVCredentials(email: email, appPassword: password)
    }

    // MARK: - CalDAV Path

    private func upsertViaCalDAV(for log: WorkLog, credentials: CalDAVCredentials) async throws -> String {
        let uid = log.calDAVUID ?? (UUID().uuidString + "@worklog")

        let destinationCoord = try? await geocode(address: settings.destinationAddress)
        let origin = await resolveOriginLocation()
        let originCoord = origin?.location.coordinate

        let destinationLoc = destinationCoord.map {
            CLLocation(latitude: $0.latitude, longitude: $0.longitude)
        }
        let travelRaw = await estimateTravelTimeSeconds(
            from: origin, to: destinationLoc, arrivalDate: log.start
        ) ?? fallbackTravelTime
        let travelMinutes = max(1, Int((travelRaw / 60).rounded()))

        let ics = ICSBuilder.buildEvent(
            uid: uid,
            title: settings.eventTitle,
            start: log.start,
            end: log.end,
            location: settings.destinationAddress,
            locationCoordinate: destinationCoord,
            travelStartTitle: origin?.title,
            travelStartAddress: settings.originFallbackAddress,
            travelStartCoordinate: originCoord,
            travelDurationMinutes: travelMinutes
        )

        let calURL = try await calDAVClient.calendarURL(
            for: settings.calendarName,
            credentials: credentials
        )
        try await calDAVClient.putEvent(
            calendarURL: calURL, uid: uid, icsData: ics, credentials: credentials
        )

        return uid
    }

    // MARK: - EventKit Path

    func requestAccessIfNeeded() async throws {
        let status = EKEventStore.authorizationStatus(for: .event)
        switch status {
        case .authorized, .fullAccess, .writeOnly:
            return
        case .denied, .restricted:
            throw CalendarSyncError.permissionDenied
        case .notDetermined:
            let granted = try await eventStore.requestFullAccessToEvents()
            if !granted {
                throw CalendarSyncError.permissionDenied
            }
        @unknown default:
            throw CalendarSyncError.permissionDenied
        }
    }

    func deleteEvent(identifier: String) {
        guard let event = eventStore.event(withIdentifier: identifier) else { return }
        try? eventStore.remove(event, span: .thisEvent, commit: true)
    }

    func upsertEvent(for log: WorkLog) async throws -> String {
        let calendarName = settings.calendarName
        let calendar = findPreferredCalendar(named: calendarName) ?? eventStore.defaultCalendarForNewEvents
        guard let calendar else {
            throw CalendarSyncError.noWritableCalendar
        }

        let oldEvent: EKEvent?
        if let existingId = log.calendarEventIdentifier {
            oldEvent = eventStore.event(withIdentifier: existingId)
        } else {
            oldEvent = nil
        }

        let event = EKEvent(eventStore: eventStore)

        let destinationAddress = settings.destinationAddress
        event.calendar = calendar
        event.title = settings.eventTitle
        event.startDate = log.start
        event.endDate = log.end

        event.location = destinationAddress
        let structuredDestination = EKStructuredLocation(title: destinationAddress)

        if let destinationCoordinate = try? await geocode(address: destinationAddress) {
            structuredDestination.geoLocation = CLLocation(latitude: destinationCoordinate.latitude, longitude: destinationCoordinate.longitude)
        }

        event.structuredLocation = structuredDestination

        let origin = await resolveOriginLocation()
        if let origin {
            setTravelStartLocationIfSupported(event: event, title: origin.title, location: origin.location)
        }
        setTravelRoutingModeIfSupported(event: event)

        // Compute travel time for alarm offsets, but do NOT persist a fixed travel time.
        // This keeps Calendar's travel time UI on "Based on location" (car) rather than
        // selecting a hardcoded minute value.
        let travelTimeSecondsRaw = await estimateTravelTimeSeconds(from: origin, to: structuredDestination.geoLocation, arrivalDate: log.start) ?? fallbackTravelTime
        let travelTimeSeconds = (travelTimeSecondsRaw / 60).rounded() * 60
        event.travelTime = travelTimeSeconds

        applyDefaultAlarms(to: event, travelTime: travelTimeSeconds)

        try eventStore.save(event, span: .thisEvent, commit: true)
        if let oldEvent {
            try? eventStore.remove(oldEvent, span: .thisEvent, commit: true)
        }
        return event.eventIdentifier
    }

    private func setTravelRoutingModeIfSupported(event: EKEvent) {
        // Best-effort: prefer driving when Calendar computes "Based on location".
        let keys = ["setTravelRoutingMode:", "setTravelMode:", "setTravelTransportType:"]
        let drivingValue = NSNumber(value: 0)

        for key in keys {
            let setter = Selector(key)
            if event.responds(to: setter) {
                _ = event.perform(setter, with: drivingValue)
                return
            }
        }
    }

    private func setTravelStartLocationIfSupported(event: EKEvent, title: String, location: CLLocation) {
        let structured = EKStructuredLocation(title: title)
        structured.geoLocation = location

        let setterSelectors: [Selector] = [
            Selector(("setTravelStartLocation:")),
            Selector(("setStructuredTravelStartLocation:")),
            Selector(("setStructuredStartLocation:")),
            Selector(("setStartLocation:"))
        ]

        for setter in setterSelectors where event.responds(to: setter) {
            _ = event.perform(setter, with: structured)
            return
        }

    }

    private func resolveOriginLocation() async -> (title: String, location: CLLocation)? {
        if let current = try? await locationClient.fetchLocation() {
            return (title: "Current Location", location: current)
        }

        let fallbackAddress = settings.originFallbackAddress
        if let fallbackCoordinate = try? await geocode(address: fallbackAddress) {
            let fallback = CLLocation(latitude: fallbackCoordinate.latitude, longitude: fallbackCoordinate.longitude)
            return (title: fallbackAddress, location: fallback)
        }

        return nil
    }

    private func applyDefaultAlarms(to event: EKEvent, travelTime: TimeInterval) {
        // Travel-time-relative alarms (Calendar menu: "... before travel time").
        // These offsets are relative to the event start date.
        let offsets: [TimeInterval] = [
            -(travelTime + 30 * 60),
            -(travelTime + 1 * 60 * 60),
            -travelTime
        ]

        event.alarms = offsets.map { EKAlarm(relativeOffset: $0) }
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

    private func estimateTravelTimeSeconds(
        from origin: (title: String, location: CLLocation)?,
        to destination: CLLocation?,
        arrivalDate: Date?
    ) async -> TimeInterval? {
        guard let destination else {
            return nil
        }

        let request = MKDirections.Request()

        if origin?.title == "Current Location" {
            request.source = MKMapItem.forCurrentLocation()
        } else if let origin {
            request.source = MKMapItem(placemark: MKPlacemark(coordinate: origin.location.coordinate))
        } else {
            return nil
        }

        request.destination = MKMapItem(placemark: MKPlacemark(coordinate: destination.coordinate))
        request.transportType = .automobile
        request.arrivalDate = arrivalDate

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
private final class LocationClient: NSObject, @preconcurrency CLLocationManagerDelegate {
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

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in
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
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        Task { @MainActor in
            guard let continuation = locationContinuation else { return }
            locationContinuation = nil

            if let location = locations.first {
                continuation.resume(returning: location)
            } else {
                continuation.resume(throwing: LocationError.unavailable)
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in
            guard let continuation = locationContinuation else { return }
            locationContinuation = nil
            continuation.resume(throwing: error)
        }
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
