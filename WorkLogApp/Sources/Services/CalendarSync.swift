import CoreLocation
import EventKit
import Foundation
import MapKit
import ObjectiveC.runtime

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

    struct UpsertDiagnostics: Equatable {
        var didSetTravelRoutingMode: Bool = false
        var didSetTravelStartLocation: Bool = false
        var usedFallbackTravelTime: Bool = false
    }

    private(set) var lastUpsertDiagnostics = UpsertDiagnostics()

    private let destinationAddress = "Akutgatan 8, Lund"
    private let originFallbackAddress = "Traktörsgatan 11, Helsingborg"
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
        lastUpsertDiagnostics = UpsertDiagnostics()

        let calendar = findPreferredCalendar(named: "Arbete") ?? eventStore.defaultCalendarForNewEvents
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

        let origin = await resolveOriginLocation()
        if let origin {
            lastUpsertDiagnostics.didSetTravelStartLocation = setTravelStartLocationIfSupported(event: event, title: origin.title, location: origin.location)
        }
        lastUpsertDiagnostics.didSetTravelRoutingMode = setTravelRoutingModeIfSupported(event: event)

        // Compute travel time for alarm offsets, but do NOT persist a fixed travel time.
        // This keeps Calendar's travel time UI on "Based on location" (car) rather than
        // selecting a hardcoded minute value.
        let travelTimeSecondsRaw = await estimateTravelTimeSeconds(from: origin, to: structuredDestination.geoLocation, arrivalDate: log.start)

        let travelTimeSecondsRawOrFallback: TimeInterval
        if let travelTimeSecondsRaw {
            travelTimeSecondsRawOrFallback = travelTimeSecondsRaw
        } else {
            lastUpsertDiagnostics.usedFallbackTravelTime = true
            travelTimeSecondsRawOrFallback = fallbackTravelTime
        }

        let travelTimeSeconds = (travelTimeSecondsRawOrFallback / 60).rounded() * 60

        applyDefaultAlarms(to: event, travelTime: travelTimeSeconds)

        try eventStore.save(event, span: .thisEvent, commit: true)
        if let oldEvent {
            try? eventStore.remove(oldEvent, span: .thisEvent, commit: true)
        }
        return event.eventIdentifier
    }

    @discardableResult
    private func setTravelRoutingModeIfSupported(event: EKEvent) -> Bool {
        // Best-effort: prefer driving when Calendar computes "Based on location".
        // Avoid `perform` here; these selectors can exist with different signatures on new iOS.
        let setters: [Selector] = [
            Selector(("setTravelRoutingMode:")),
            Selector(("setTravelMode:")),
            Selector(("setTravelTransportType:"))
        ]

        for setter in setters {
            if ObjCInvocation.safeSetInteger(target: event, selector: setter, value: 0) { return true }
            if ObjCInvocation.safeSetObject(target: event, selector: setter, value: NSNumber(value: 0)) { return true }
        }

        return false
    }

    @discardableResult
    private func setTravelStartLocationIfSupported(event: EKEvent, title: String, location: CLLocation) -> Bool {
        let structured = EKStructuredLocation(title: title)
        structured.geoLocation = location

        let setterSelectors: [Selector] = [
            Selector(("setTravelStartLocation:")),
            Selector(("setStructuredTravelStartLocation:")),
            Selector(("setStructuredStartLocation:")),
            Selector(("setStartLocation:"))
        ]

        for setter in setterSelectors {
            if ObjCInvocation.safeSetObject(target: event, selector: setter, value: structured) { return true }
        }

        return false
    }

    private func resolveOriginLocation() async -> (title: String, location: CLLocation)? {
        if let current = try? await locationClient.fetchLocation() {
            return (title: "Current Location", location: current)
        }

        if let fallbackCoordinate = try? await geocode(address: originFallbackAddress) {
            let fallback = CLLocation(latitude: fallbackCoordinate.latitude, longitude: fallbackCoordinate.longitude)
            return (title: originFallbackAddress, location: fallback)
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

private enum ObjCInvocation {
    static func safeSetObject(target: NSObject, selector: Selector, value: NSObject) -> Bool {
        guard target.responds(to: selector),
              let method = class_getInstanceMethod(type(of: target), selector)
        else {
            return false
        }

        guard isVoidReturn(method: method), isObjectArgument(method: method, index: 2) else {
            return false
        }

        let imp = target.method(for: selector)
        typealias Fn = @convention(c) (AnyObject, Selector, AnyObject) -> Void
        let fn = unsafeBitCast(imp, to: Fn.self)
        fn(target, selector, value)
        return true
    }

    static func safeSetInteger(target: NSObject, selector: Selector, value: Int) -> Bool {
        guard target.responds(to: selector),
              let method = class_getInstanceMethod(type(of: target), selector)
        else {
            return false
        }

        guard isVoidReturn(method: method) else {
            return false
        }

        let argType = copyArgumentType(method: method, index: 2)
        guard let first = argType.first else { return false }

        switch first {
        case "q":
            let imp = target.method(for: selector)
            typealias Fn = @convention(c) (AnyObject, Selector, Int64) -> Void
            let fn = unsafeBitCast(imp, to: Fn.self)
            fn(target, selector, Int64(value))
            return true
        case "i":
            let imp = target.method(for: selector)
            typealias Fn = @convention(c) (AnyObject, Selector, Int32) -> Void
            let fn = unsafeBitCast(imp, to: Fn.self)
            fn(target, selector, Int32(value))
            return true
        case "Q":
            let imp = target.method(for: selector)
            typealias Fn = @convention(c) (AnyObject, Selector, UInt64) -> Void
            let fn = unsafeBitCast(imp, to: Fn.self)
            fn(target, selector, UInt64(value))
            return true
        case "I":
            let imp = target.method(for: selector)
            typealias Fn = @convention(c) (AnyObject, Selector, UInt32) -> Void
            let fn = unsafeBitCast(imp, to: Fn.self)
            fn(target, selector, UInt32(value))
            return true
        case "B":
            let imp = target.method(for: selector)
            typealias Fn = @convention(c) (AnyObject, Selector, Bool) -> Void
            let fn = unsafeBitCast(imp, to: Fn.self)
            fn(target, selector, value != 0)
            return true
        default:
            return false
        }
    }

    private static func isVoidReturn(method: Method) -> Bool {
        let c = method_copyReturnType(method)
        defer { free(c) }
        return String(cString: c) == "v"
    }

    private static func isObjectArgument(method: Method, index: UInt32) -> Bool {
        let type = copyArgumentType(method: method, index: index)
        guard let first = type.first else { return false }
        return first == "@"
    }

    private static func copyArgumentType(method: Method, index: UInt32) -> String {
        guard let c = method_copyArgumentType(method, index) else {
            return ""
        }
        defer { free(c) }
        return String(cString: c)
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
