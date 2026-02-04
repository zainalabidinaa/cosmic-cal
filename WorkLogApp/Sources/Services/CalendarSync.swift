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

    private let destinationAddress = "Akutgatan 8, Lund"
    private let originFallbackAddress = "Traktörsgatan 11, Helsingborg"
    private let fixedTravelTimeSeconds: TimeInterval = 30 * 60

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

        let oldEvent: EKEvent?
        if let existingId = log.calendarEventIdentifier {
            oldEvent = eventStore.event(withIdentifier: existingId)
        } else {
            oldEvent = nil
        }

        let event = EKEvent(eventStore: eventStore)

        event.calendar = calendar
        event.title = "Labmedicin Bas Lund"
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
            _ = setTravelStartLocationIfSupported(
                event: event,
                title: origin.title,
                location: origin.location
            )
        }
        _ = setTravelTimeEnabledIfSupported(event: event)
        _ = setTravelRoutingModeIfSupported(event: event)
        let basedOnLocationApplied = setTravelTimeModeIfSupported(event: event)
            || setTravelTimeBasedOnLocationIfSupported(event: event)

        if !basedOnLocationApplied {
            let estimatedTravelSeconds = await estimateTravelTimeSeconds(
                from: origin,
                to: structuredDestination.geoLocation,
                arrivalDate: log.start
            )
            let travelSeconds = estimatedTravelSeconds ?? fixedTravelTimeSeconds
            _ = setFixedTravelTimeIfSupported(event: event, seconds: travelSeconds)
        }

        // Do NOT estimate or persist travel time.
        // We want Calendar's UI to stay on "Based on location" (Driving), and we want
        // the alarms to be chosen as "30 minutes before travel time" and
        // "1 hour before travel time".
        applyDefaultAlarms(to: event)

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
    private func setTravelTimeBasedOnLocationIfSupported(event: EKEvent) -> Bool {
        // Best-effort: nudge Calendar into the "Based on location" travel-time mode.
        // There is no public EventKit API for this; we try a few known private-style
        // selectors, guarded by runtime signature checks.
        let boolSetters: [Selector] = [
            Selector(("setTravelTimeBasedOnLocation:")),
            Selector(("setTravelTimeIsBasedOnLocation:")),
            Selector(("setUsesTravelTimeBasedOnLocation:")),
            Selector(("setUseTravelTimeBasedOnLocation:")),
            Selector(("setTravelTimeIsEstimated:"))
        ]

        for selector in boolSetters {
            if ObjCInvocation.safeSetBool(target: event, selector: selector, value: true) { return true }
            if ObjCInvocation.safeSetInteger(target: event, selector: selector, value: 1) { return true }
            if ObjCInvocation.safeSetObject(target: event, selector: selector, value: NSNumber(value: true)) { return true }
        }

        return false
    }

    @discardableResult
    private func setTravelTimeModeIfSupported(event: EKEvent) -> Bool {
        // Best-effort: attempt to select "Based on location" travel-time mode.
        // Values are unknown; we try a couple common integer options.
        let selectors: [Selector] = [
            Selector(("setTravelTimeMode:")),
            Selector(("setTravelTimeType:")),
            Selector(("setTravelTimeOption:"))
        ]

        let candidates = [1, 2]
        for selector in selectors {
            for value in candidates {
                if ObjCInvocation.safeSetInteger(target: event, selector: selector, value: value) { return true }
                if ObjCInvocation.safeSetObject(target: event, selector: selector, value: NSNumber(value: value)) { return true }
            }
        }

        return false
    }

    @discardableResult
    private func setFixedTravelTimeIfSupported(event: EKEvent, seconds: TimeInterval) -> Bool {
        let selectors: [Selector] = [
            Selector(("setTravelTime:")),
            Selector(("setTravelTimeInterval:")),
            Selector(("setTravelTimeInSeconds:"))
        ]

        for selector in selectors {
            if ObjCInvocation.safeSetDouble(target: event, selector: selector, value: seconds) { return true }
            if ObjCInvocation.safeSetInteger(target: event, selector: selector, value: Int(seconds)) { return true }
            if ObjCInvocation.safeSetObject(target: event, selector: selector, value: NSNumber(value: seconds)) { return true }
        }

        return false
    }

    @discardableResult
    private func setTravelTimeEnabledIfSupported(event: EKEvent) -> Bool {
        // Best-effort: toggle travel time ON.
        // Calendar's UI has a dedicated on/off toggle; EventKit does not expose this publicly.
        // We try a few likely private-style setters.
        let setters: [Selector] = [
            Selector(("setTravelTimeEnabled:")),
            Selector(("setTravelTimeIsEnabled:")),
            Selector(("setHasTravelTime:")),
            Selector(("setTravelTimeActive:")),
            Selector(("setShouldIncludeTravelTime:")),
            Selector(("setIncludeTravelTime:")),
            Selector(("setTravelTimeOn:")),
            Selector(("setIncludesTravelTime:"))
        ]

        for selector in setters {
            if ObjCInvocation.safeSetBool(target: event, selector: selector, value: true) { return true }
            if ObjCInvocation.safeSetInteger(target: event, selector: selector, value: 1) { return true }
            if ObjCInvocation.safeSetObject(target: event, selector: selector, value: NSNumber(value: true)) { return true }
        }

        return false
    }

    private func setTravelStartLocationIfSupported(event: EKEvent, title: String, location: CLLocation) -> Bool {
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
            return true
        }

        // Fallback to KVC if the runtime exposes a key.
        let keys = ["travelStartLocation", "structuredTravelStartLocation", "structuredStartLocation", "startLocation"]
        for key in keys {
            let getter = Selector((key))
            if event.responds(to: getter) {
                event.setValue(structured, forKey: key)
                return true
            }
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

    private func applyDefaultAlarms(to event: EKEvent) {
        // Travel-time-relative alarms (Calendar menu: "... before travel time").
        // When travel is enabled (start + destination + routing mode), Calendar will
        // display these offsets relative to travel time.
        let offsets: [TimeInterval] = [
            -30 * 60,
            -60 * 60
        ]

        event.alarms = offsets.map { EKAlarm(relativeOffset: $0) }
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

        guard let originLocation = origin?.location else { return nil }
        request.source = MKMapItem(placemark: MKPlacemark(coordinate: originLocation.coordinate))

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
    static func safeSetOptionalObject(target: NSObject, selector: Selector, value: NSObject?) -> Bool {
        guard target.responds(to: selector),
              let method = class_getInstanceMethod(type(of: target), selector)
        else {
            return false
        }

        guard isVoidReturn(method: method), isObjectArgument(method: method, index: 2) else {
            return false
        }

        let imp = target.method(for: selector)
        typealias Fn = @convention(c) (AnyObject, Selector, AnyObject?) -> Void
        let fn = unsafeBitCast(imp, to: Fn.self)
        fn(target, selector, value)
        return true
    }

    static func safeSetObject(target: NSObject, selector: Selector, value: NSObject) -> Bool {
        safeSetOptionalObject(target: target, selector: selector, value: value)
    }

    static func safeSetBool(target: NSObject, selector: Selector, value: Bool) -> Bool {
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
        case "B":
            let imp = target.method(for: selector)
            typealias Fn = @convention(c) (AnyObject, Selector, Bool) -> Void
            let fn = unsafeBitCast(imp, to: Fn.self)
            fn(target, selector, value)
            return true
        case "c":
            let imp = target.method(for: selector)
            typealias Fn = @convention(c) (AnyObject, Selector, Int8) -> Void
            let fn = unsafeBitCast(imp, to: Fn.self)
            fn(target, selector, value ? 1 : 0)
            return true
        default:
            return false
        }
    }

    static func safeSetDouble(target: NSObject, selector: Selector, value: Double) -> Bool {
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
        case "d":
            let imp = target.method(for: selector)
            typealias Fn = @convention(c) (AnyObject, Selector, Double) -> Void
            let fn = unsafeBitCast(imp, to: Fn.self)
            fn(target, selector, value)
            return true
        case "f":
            let imp = target.method(for: selector)
            typealias Fn = @convention(c) (AnyObject, Selector, Float) -> Void
            let fn = unsafeBitCast(imp, to: Fn.self)
            fn(target, selector, Float(value))
            return true
        default:
            return false
        }
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
