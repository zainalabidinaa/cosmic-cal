import Foundation

struct CalDAVCredentials {
    let email: String
    let appPassword: String

    var authorizationHeader: String {
        let combined = "\(email):\(appPassword)"
        return "Basic \(Data(combined.utf8).base64EncodedString())"
    }
}

enum CalDAVError: LocalizedError {
    case invalidCredentials
    case calendarNotFound(String)
    case serverError(Int)
    case discoveryFailed

    var errorDescription: String? {
        switch self {
        case .invalidCredentials: return "Invalid iCloud credentials. Check your Apple ID and app-specific password."
        case .calendarNotFound(let name): return "Calendar '\(name)' not found via CalDAV."
        case .serverError(let code): return "CalDAV server error (HTTP \(code))."
        case .discoveryFailed: return "CalDAV calendar discovery failed."
        }
    }
}

actor CalDAVClient {
    private let session: URLSession
    private let baseURL = URL(string: "https://caldav.icloud.com/")!
    private var cachedCalendarURLs: [String: URL] = [:]

    init() {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 30
        self.session = URLSession(configuration: config)
    }

    func calendarURL(for calendarName: String, credentials: CalDAVCredentials) async throws -> URL {
        let cacheKey = "\(credentials.email):\(calendarName)"
        if let cached = cachedCalendarURLs[cacheKey] {
            return cached
        }

        let principalURL = try await findPrincipal(credentials: credentials)
        let homeURL = try await findCalendarHome(principalURL: principalURL, credentials: credentials)
        let calURL = try await findCalendar(named: calendarName, homeURL: homeURL, credentials: credentials)

        cachedCalendarURLs[cacheKey] = calURL
        return calURL
    }

    func putEvent(calendarURL: URL, uid: String, icsData: String, credentials: CalDAVCredentials) async throws {
        let eventURL = calendarURL.appendingPathComponent("\(uid).ics")
        var request = URLRequest(url: eventURL)
        request.httpMethod = "PUT"
        request.setValue("text/calendar; charset=utf-8", forHTTPHeaderField: "Content-Type")
        request.setValue(credentials.authorizationHeader, forHTTPHeaderField: "Authorization")
        request.httpBody = Data(icsData.utf8)

        let (_, response) = try await session.data(for: request)
        let code = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200...299).contains(code) else {
            if code == 401 { throw CalDAVError.invalidCredentials }
            throw CalDAVError.serverError(code)
        }
    }

    func deleteEvent(calendarURL: URL, uid: String, credentials: CalDAVCredentials) async throws {
        let eventURL = calendarURL.appendingPathComponent("\(uid).ics")
        var request = URLRequest(url: eventURL)
        request.httpMethod = "DELETE"
        request.setValue(credentials.authorizationHeader, forHTTPHeaderField: "Authorization")

        let (_, response) = try await session.data(for: request)
        let code = (response as? HTTPURLResponse)?.statusCode ?? 0
        // 204 No Content = success, 404 = already gone (both acceptable)
        guard code == 200 || code == 204 || code == 404 else {
            if code == 401 { throw CalDAVError.invalidCredentials }
            throw CalDAVError.serverError(code)
        }
    }

    func clearCache() {
        cachedCalendarURLs.removeAll()
    }

    // MARK: - Discovery

    private func findPrincipal(credentials: CalDAVCredentials) async throws -> URL {
        let body = """
        <?xml version="1.0" encoding="utf-8"?>
        <d:propfind xmlns:d="DAV:">
          <d:prop><d:current-user-principal/></d:prop>
        </d:propfind>
        """

        let xml = try await propfind(url: baseURL, body: body, depth: "0", credentials: credentials)
        guard let href = extractHref(from: xml, after: "current-user-principal") else {
            throw CalDAVError.discoveryFailed
        }
        return resolveURL(href)
    }

    private func findCalendarHome(principalURL: URL, credentials: CalDAVCredentials) async throws -> URL {
        let body = """
        <?xml version="1.0" encoding="utf-8"?>
        <d:propfind xmlns:d="DAV:" xmlns:c="urn:ietf:params:xml:ns:caldav">
          <d:prop><c:calendar-home-set/></d:prop>
        </d:propfind>
        """

        let xml = try await propfind(url: principalURL, body: body, depth: "0", credentials: credentials)
        guard let href = extractHref(from: xml, after: "calendar-home-set") else {
            throw CalDAVError.discoveryFailed
        }
        return resolveURL(href)
    }

    private func findCalendar(named name: String, homeURL: URL, credentials: CalDAVCredentials) async throws -> URL {
        let body = """
        <?xml version="1.0" encoding="utf-8"?>
        <d:propfind xmlns:d="DAV:">
          <d:prop>
            <d:displayname/>
            <d:resourcetype/>
          </d:prop>
        </d:propfind>
        """

        let xml = try await propfind(url: homeURL, body: body, depth: "1", credentials: credentials)
        let stripped = stripNamespacePrefixes(xml)

        // Split into <response> blocks and find the one that is a calendar with the right name.
        let blocks = stripped.components(separatedBy: "<response>").dropFirst()
        for block in blocks {
            let isCalendar = block.contains("<calendar")
            guard let displayName = textBetween("<displayname>", and: "</displayname>", in: block),
                  displayName == name,
                  isCalendar else { continue }

            guard let href = textBetween("<href>", and: "</href>", in: block) else { continue }
            return resolveURL(href)
        }

        throw CalDAVError.calendarNotFound(name)
    }

    // MARK: - HTTP

    private func propfind(url: URL, body: String, depth: String, credentials: CalDAVCredentials) async throws -> String {
        var request = URLRequest(url: url)
        request.httpMethod = "PROPFIND"
        request.setValue("application/xml; charset=utf-8", forHTTPHeaderField: "Content-Type")
        request.setValue(depth, forHTTPHeaderField: "Depth")
        request.setValue(credentials.authorizationHeader, forHTTPHeaderField: "Authorization")
        request.httpBody = Data(body.utf8)

        let (data, response) = try await session.data(for: request)
        let code = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard code == 207 || code == 200 else {
            if code == 401 { throw CalDAVError.invalidCredentials }
            throw CalDAVError.serverError(code)
        }
        return String(data: data, encoding: .utf8) ?? ""
    }

    // MARK: - XML Helpers

    private func stripNamespacePrefixes(_ xml: String) -> String {
        var result = xml
        for prefix in ["d:", "D:", "c:", "C:", "cs:", "CS:"] {
            result = result.replacingOccurrences(of: "<\(prefix)", with: "<")
            result = result.replacingOccurrences(of: "</\(prefix)", with: "</")
        }
        return result
    }

    private func extractHref(from xml: String, after tag: String) -> String? {
        let stripped = stripNamespacePrefixes(xml)
        guard let tagRange = stripped.range(of: tag) else { return nil }
        let remainder = stripped[tagRange.upperBound...]
        return textBetween("<href>", and: "</href>", in: String(remainder))
    }

    private func textBetween(_ open: String, and close: String, in source: String) -> String? {
        guard let openRange = source.range(of: open) else { return nil }
        let after = source[openRange.upperBound...]
        guard let closeRange = after.range(of: close) else { return nil }
        return String(after[..<closeRange.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func resolveURL(_ href: String) -> URL {
        if href.hasPrefix("http") {
            return URL(string: href) ?? baseURL
        }
        return URL(string: href, relativeTo: baseURL)?.absoluteURL ?? baseURL.appendingPathComponent(href)
    }
}
