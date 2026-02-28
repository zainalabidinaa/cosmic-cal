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

    private let fallbackTravelTime: TimeInterval = 30 * 60
    private let fixedTravelTimeSeconds: TimeInterval = 30 * 60

    init(settings: AppSettings) {
        self.settings = settings
    }

    // MARK: - Unified Sync

    func syncEvent(for log: WorkLog) async throws -> SyncResult {
        // Keep saves reliable: EventKit is the primary sync path.
        // CalDAV remains explicit/optional via the travel metadata test action.
        try await requestAccessIfNeeded()
        let eventId = try await upsertEvent(for: log)
        return .eventKit(eventId)
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
        makeCalDAVCredentialCandidates().first
    }

    private func makeCalDAVCredentialCandidates() -> [CalDAVCredentials] {
        let rawEmail = settings.iCloudEmail
        let trimmedEmail = rawEmail.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedEmail = trimmedEmail.lowercased()

        let accountKeys = [rawEmail, trimmedEmail, normalizedEmail]
            .filter { !$0.isEmpty }

        var loadedPassword: String?
        for account in accountKeys {
            if let value = KeychainHelper.loadPassword(account: account), !value.isEmpty {
                loadedPassword = value
                break
            }
        }

        guard !trimmedEmail.isEmpty, let loadedPassword else {
            return []
        }

        let trimmedPassword = loadedPassword.trimmingCharacters(in: .whitespacesAndNewlines)
        let noWhitespacePassword = trimmedPassword
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "\n", with: "")
            .replacingOccurrences(of: "\r", with: "")
        let noHyphenPassword = noWhitespacePassword.replacingOccurrences(of: "-", with: "")

        var passwordVariants: [String] = []
        for variant in [loadedPassword, trimmedPassword, noWhitespacePassword, noHyphenPassword] {
            guard !variant.isEmpty, !passwordVariants.contains(variant) else { continue }
            passwordVariants.append(variant)
        }

        return passwordVariants.map { variant in
            CalDAVCredentials(email: trimmedEmail, appPassword: variant)
        }
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
        let useCurrentLocationStart = settings.travelOriginMode == .currentLocation
        // For current location: pass nil address (no X-ADDRESS / X-APPLE-RADIUS on origin)
        // For custom address: pass the configured fallback address string
        let travelStartAddress: String? = useCurrentLocationStart ? nil : settings.originFallbackAddress
        let travelRaw = await estimateTravelTimeSeconds(
            from: origin, to: destinationLoc, arrivalDate: log.start
        ) ?? fallbackTravelTime
        // Always emit travel duration — even in "based on driving" mode Apple includes it
        let travelMinutes = max(1, Int((travelRaw / 60).rounded()))

        let ics = ICSBuilder.buildEvent(
            uid: uid,
            title: settings.eventTitle,
            start: log.start,
            end: log.end,
            location: settings.destinationAddress,
            locationCoordinate: destinationCoord,
            travelStartTitle: origin?.title,
            travelStartAddress: travelStartAddress,
            travelStartCoordinate: originCoord,
            travelDurationMinutes: travelMinutes,
            travelStartIsCurrentLocation: useCurrentLocationStart
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
            _ = setTravelStartLocationIfSupported(event: event, title: origin.title, location: origin.location)
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
            let rawTravelSeconds = estimatedTravelSeconds ?? fixedTravelTimeSeconds
            let roundedTravelSeconds = (rawTravelSeconds / 60).rounded() * 60
            _ = setFixedTravelTimeIfSupported(event: event, seconds: roundedTravelSeconds)
        }

        applyDefaultAlarms(to: event)

        try eventStore.save(event, span: .thisEvent, commit: true)
        if let oldEvent {
            try? eventStore.remove(oldEvent, span: .thisEvent, commit: true)
        }
        return event.eventIdentifier
    }

    func runTravelMetadataTest() async -> String {
        var lines: [String] = []
        lines.append("Sync configured: EventKit primary")
        lines.append("CalDAV credentials: \(settings.calDAVConfigured ? "available" : "missing")")
        lines.append("Travel origin: \(settings.travelOriginMode.title)")
        lines.append("Travel mode: \(settings.travelTimeMode.title)")
        lines.append("Calendar: \(settings.calendarName)")

        if let calendar = findPreferredCalendar(named: settings.calendarName) {
            lines.append("Calendar type: \(calendarTypeLabel(calendar.type))")
        } else {
            lines.append("Calendar type: not found")
        }

        let destinationResolved = (try? await geocode(address: settings.destinationAddress)) != nil
        lines.append("Destination geocode: \(destinationResolved ? "ok" : "failed")")

        let originResolved = await resolveOriginLocation() != nil
        lines.append("Origin resolution: \(originResolved ? "ok" : "failed")")

        let now = Date()
        let testStart = Calendar.current.date(byAdding: .minute, value: 90, to: now) ?? now
        let testEnd = Calendar.current.date(byAdding: .minute, value: 120, to: now) ?? now.addingTimeInterval(1800)
        let testLog = WorkLog(day: testStart.startOfLocalDay(), start: testStart, end: testEnd)
        let uid = UUID().uuidString + "@worklog-test"
        let destinationCoord = try? await geocode(address: settings.destinationAddress)
        let origin = await resolveOriginLocation()
        let originCoord = origin?.location.coordinate
        let destinationLoc = destinationCoord.map { CLLocation(latitude: $0.latitude, longitude: $0.longitude) }
        let useCurrentLocationStart = settings.travelOriginMode == .currentLocation
        let travelStartAddress: String? = useCurrentLocationStart ? nil : settings.originFallbackAddress
        let travelRaw = await estimateTravelTimeSeconds(from: origin, to: destinationLoc, arrivalDate: testStart) ?? fallbackTravelTime
        let travelMinutes = max(1, Int((travelRaw / 60).rounded()))
        let ics = ICSBuilder.buildEvent(
            uid: uid,
            title: settings.eventTitle,
            start: testStart,
            end: testEnd,
            location: settings.destinationAddress,
            locationCoordinate: destinationCoord,
            travelStartTitle: origin?.title,
            travelStartAddress: travelStartAddress,
            travelStartCoordinate: originCoord,
            travelDurationMinutes: travelMinutes,
            travelStartIsCurrentLocation: useCurrentLocationStart
        )

        let importantICSLines = ics
            .components(separatedBy: "\r\n")
            .filter {
                $0.hasPrefix("DTSTART")
                    || $0.hasPrefix("DTEND")
                    || $0.hasPrefix("X-APPLE-STRUCTURED-LOCATION")
                    || $0.hasPrefix("X-APPLE-TRAVEL-DURATION")
                    || $0.hasPrefix("X-APPLE-TRAVEL-START")
                    || $0.hasPrefix("TRIGGER;VALUE=DATE-TIME")
            }

        lines.append("ICS check: found \(importantICSLines.count) key travel lines")
        for line in importantICSLines {
            lines.append("ICS: \(line)")
        }

        let credentialCandidates = makeCalDAVCredentialCandidates()
        if let credentials = credentialCandidates.first {
            var step1 = false
            var step2 = false
            var step3 = false

            step1 = true
            lines.append("CalDAV step 1/3: credentials loaded (ok)")
            lines.append("CalDAV credential variants: \(credentialCandidates.count)")

            do {
                let calURL = try await calDAVClient.calendarURL(
                    for: settings.calendarName,
                    credentials: credentials
                )
                step2 = true
                lines.append("CalDAV step 2/3: calendar discovery (ok)")

                try await calDAVClient.putEvent(
                    calendarURL: calURL,
                    uid: uid,
                    icsData: ics,
                    credentials: credentials
                )
                step3 = true
                lines.append("CalDAV step 3/3: PUT event (ok)")
                lines.append("Test event sync: CalDAV uid=\(uid)")
                lines.append("Result: success. Open Calendar and inspect the new event.")
            } catch {
                lines.append("Result: failed during CalDAV step (\(error.localizedDescription))")
            }

            lines.append("CalDAV summary: step1=\(step1 ? "ok" : "no") step2=\(step2 ? "ok" : "no") step3=\(step3 ? "ok" : "no")")

            return lines.joined(separator: "\n")
        }

        lines.append("CalDAV credentials missing; running EventKit primary test.")
        do {
            let result = try await syncEvent(for: testLog)
            switch result {
            case .calDAV(let syncedUID):
                lines.append("Test event sync: CalDAV uid=\(syncedUID)")
            case .eventKit(let eventId):
                lines.append("Test event sync: EventKit id=\(eventId)")
            }
            lines.append("Result: success. Open Calendar and inspect the new event.")
        } catch {
            lines.append("Result: failed (\(error.localizedDescription))")
        }

        return lines.joined(separator: "\n")
    }

    @discardableResult
    private func setTravelRoutingModeIfSupported(event: EKEvent) -> Bool {
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
        let selectors: [Selector] = [
            Selector(("setTravelTimeMode:")),
            Selector(("setTravelTimeType:")),
            Selector(("setTravelTimeOption:"))
        ]

        for selector in selectors {
            for value in [1, 2] {
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

        for setter in setterSelectors where event.responds(to: setter) {
            _ = event.perform(setter, with: structured)
            return true
        }

        return false
    }

    private func resolveOriginLocation() async -> (title: String, location: CLLocation)? {
        switch settings.travelOriginMode {
        case .currentLocation:
            if let current = try? await locationClient.fetchLocation() {
                return (title: "Current Location", location: current)
            }
            return nil

        case .customAddress:
            let fallbackAddress = settings.originFallbackAddress
            if let fallbackCoordinate = try? await geocode(address: fallbackAddress) {
                let fallback = CLLocation(latitude: fallbackCoordinate.latitude, longitude: fallbackCoordinate.longitude)
                return (title: fallbackAddress, location: fallback)
            }
            return nil
        }
    }

    private func applyDefaultAlarms(to event: EKEvent) {
        let offsets: [TimeInterval] = [
            -30 * 60,
            -60 * 60
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

    private func calendarTypeLabel(_ type: EKCalendarType) -> String {
        switch type {
        case .local:
            return "Local"
        case .calDAV:
            return "CalDAV"
        case .exchange:
            return "Exchange"
        case .subscription:
            return "Subscription"
        case .birthday:
            return "Birthday"
        @unknown default:
            return "Unknown"
        }
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
