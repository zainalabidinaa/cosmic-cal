import Foundation

struct CalDAVCredentials {
    let email: String
    let appPassword: String

    var authorizationHeader: String {
        let combined = "\(email):\(appPassword)"
        return "Basic \(Data(combined.utf8).base64EncodedString())"
    }

    var urlCredential: URLCredential {
        URLCredential(user: email, password: appPassword, persistence: .forSession)
    }
}

enum CalDAVError: LocalizedError {
    case invalidCredentials
    case calendarNotFound(String)
    case serverError(Int)
    case discoveryFailed
    case networkOffline
    case requestTimedOut
    case secureConnectionFailed
    case transportError(String)

    var errorDescription: String? {
        switch self {
        case .invalidCredentials: return "Invalid iCloud credentials. Check your Apple ID and app-specific password."
        case .calendarNotFound(let name): return "Calendar '\(name)' not found via CalDAV."
        case .serverError(let code): return "CalDAV server error (HTTP \(code))."
        case .discoveryFailed: return "CalDAV calendar discovery failed."
        case .networkOffline: return "No network connection. Check internet access and try again."
        case .requestTimedOut: return "CalDAV request timed out. Try again in a moment."
        case .secureConnectionFailed: return "Secure connection to iCloud failed. Check date/time and network security settings."
        case .transportError(let detail): return "CalDAV transport error: \(detail)"
        }
    }
}

actor CalDAVClient {
    private let session: URLSession
    private let authDelegate: AuthChallengeDelegate
    private let baseURL = URL(string: "https://caldav.icloud.com/")!
    private var cachedCalendarURLs: [String: URL] = [:]

    init() {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 30
        let delegate = AuthChallengeDelegate()
        authDelegate = delegate
        session = URLSession(configuration: config, delegate: delegate, delegateQueue: nil)
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

        authDelegate.credential = credentials.urlCredential

        let response: URLResponse
        do {
            (_, response) = try await session.data(for: request)
        } catch {
            throw mappedTransportError(error)
        }

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

        authDelegate.credential = credentials.urlCredential

        let response: URLResponse
        do {
            (_, response) = try await session.data(for: request)
        } catch {
            throw mappedTransportError(error)
        }

        let code = (response as? HTTPURLResponse)?.statusCode ?? 0
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
        guard let href = hrefForProperty("current-user-principal", in: xml) else {
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
        guard let href = hrefForProperty("calendar-home-set", in: xml) else {
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
        let normalized = normalizeXMLNamespaces(xml)

        let responseBlocks = allCaptures(
            pattern: "<response\\b[^>]*>(.*?)</response>",
            in: normalized
        )

        var discoveredCalendars: [(name: String, href: String)] = []
        for block in responseBlocks {
            guard containsCalendarResourceType(block),
                  let href = firstCapture(pattern: "<href\\b[^>]*>(.*?)</href>", in: block)
            else {
                continue
            }

            let displayName = firstCapture(pattern: "<displayname\\b[^>]*>(.*?)</displayname>", in: block) ?? ""
            discoveredCalendars.append((
                name: decodeXMLEntities(displayName).trimmingCharacters(in: .whitespacesAndNewlines),
                href: decodeXMLEntities(href).trimmingCharacters(in: .whitespacesAndNewlines)
            ))
        }

        guard !discoveredCalendars.isEmpty else {
            throw CalDAVError.discoveryFailed
        }

        if let exact = discoveredCalendars.first(where: { $0.name == name }) {
            return resolveURL(exact.href)
        }

        let normalizedInput = normalizeCalendarName(name)
        if let fuzzy = discoveredCalendars.first(where: { normalizeCalendarName($0.name) == normalizedInput }) {
            return resolveURL(fuzzy.href)
        }

        throw CalDAVError.calendarNotFound(name)
    }

    private func normalizeCalendarName(_ value: String) -> String {
        value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
    }

    // MARK: - HTTP

    private func propfind(url: URL, body: String, depth: String, credentials: CalDAVCredentials) async throws -> String {
        var request = URLRequest(url: url)
        request.httpMethod = "PROPFIND"
        request.setValue("application/xml; charset=utf-8", forHTTPHeaderField: "Content-Type")
        request.setValue(depth, forHTTPHeaderField: "Depth")
        request.setValue(credentials.authorizationHeader, forHTTPHeaderField: "Authorization")
        request.httpBody = Data(body.utf8)

        authDelegate.credential = credentials.urlCredential

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw mappedTransportError(error)
        }

        let code = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard code == 207 || code == 200 else {
            if code == 401 { throw CalDAVError.invalidCredentials }
            throw CalDAVError.serverError(code)
        }

        let xml = String(data: data, encoding: .utf8) ?? ""
        let lowercase = xml.lowercased()
        if lowercase.contains("<unauthenticated") || lowercase.contains("authentication required") {
            throw CalDAVError.invalidCredentials
        }
        return xml
    }

    private func mappedTransportError(_ error: Error) -> Error {
        let urlCode: URLError.Code?
        if let urlError = error as? URLError {
            urlCode = urlError.code
        } else {
            let nsError = error as NSError
            if nsError.domain == NSURLErrorDomain {
                urlCode = URLError.Code(rawValue: nsError.code)
            } else {
                urlCode = nil
            }
        }

        guard let urlCode else {
            return error
        }

        switch urlCode {
        case .userAuthenticationRequired, .userCancelledAuthentication:
            return CalDAVError.invalidCredentials
        case .notConnectedToInternet, .networkConnectionLost:
            return CalDAVError.networkOffline
        case .timedOut:
            return CalDAVError.requestTimedOut
        case .secureConnectionFailed, .serverCertificateUntrusted, .serverCertificateHasBadDate, .serverCertificateHasUnknownRoot:
            return CalDAVError.secureConnectionFailed
        default:
            let nsError = error as NSError
            return CalDAVError.transportError("\(nsError.domain) code=\(nsError.code): \(nsError.localizedDescription)")
        }
    }

    // MARK: - XML Helpers

    private func normalizeXMLNamespaces(_ xml: String) -> String {
        xml.replacingOccurrences(
            of: "(<\\/?)([A-Za-z_][A-Za-z0-9_.-]*:)([A-Za-z_][A-Za-z0-9_.-]*)(\\b)",
            with: "$1$3$4",
            options: .regularExpression
        )
    }

    private func hrefForProperty(_ propertyTag: String, in xml: String) -> String? {
        let normalized = normalizeXMLNamespaces(xml)
        guard let href = firstCapture(
            pattern: "<\(propertyTag)\\b[^>]*>.*?<href\\b[^>]*>(.*?)</href>.*?</\(propertyTag)>",
            in: normalized
        ) else {
            return nil
        }
        return decodeXMLEntities(href).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func containsCalendarResourceType(_ responseBlock: String) -> Bool {
        firstCapture(
            pattern: "<resourcetype\\b[^>]*>.*?<calendar\\b[^>]*/?>.*?</resourcetype>",
            in: responseBlock
        ) != nil
    }

    private func firstCapture(pattern: String, in source: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators, .caseInsensitive]) else {
            return nil
        }
        let range = NSRange(source.startIndex..<source.endIndex, in: source)
        guard let match = regex.firstMatch(in: source, range: range), match.numberOfRanges > 1,
              let captureRange = Range(match.range(at: 1), in: source)
        else {
            return nil
        }
        return String(source[captureRange])
    }

    private func allCaptures(pattern: String, in source: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators, .caseInsensitive]) else {
            return []
        }
        let range = NSRange(source.startIndex..<source.endIndex, in: source)
        return regex.matches(in: source, range: range).compactMap { match in
            guard match.numberOfRanges > 1,
                  let captureRange = Range(match.range(at: 1), in: source)
            else {
                return nil
            }
            return String(source[captureRange])
        }
    }

    private func decodeXMLEntities(_ value: String) -> String {
        value
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&apos;", with: "'")
    }

    private func resolveURL(_ href: String) -> URL {
        if href.hasPrefix("http") {
            return URL(string: href) ?? baseURL
        }
        return URL(string: href, relativeTo: baseURL)?.absoluteURL ?? baseURL.appendingPathComponent(href)
    }
}

// MARK: - URLSession Auth Challenge Handler

private final class AuthChallengeDelegate: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    var credential: URLCredential?

    private func isICloudHost(_ host: String?) -> Bool {
        guard let host else { return false }
        return host.hasSuffix("icloud.com") || host.hasSuffix("apple.com")
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        guard let credential else {
            completionHandler(request)
            return
        }

        guard isICloudHost(request.url?.host) else {
            completionHandler(request)
            return
        }

        var redirected = request
        if redirected.value(forHTTPHeaderField: "Authorization") == nil {
            let combined = "\(credential.user ?? ""):\(credential.password ?? "")"
            redirected.setValue("Basic \(Data(combined.utf8).base64EncodedString())", forHTTPHeaderField: "Authorization")
        }
        completionHandler(redirected)
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        let method = challenge.protectionSpace.authenticationMethod

        if challenge.previousFailureCount > 1 {
            completionHandler(.cancelAuthenticationChallenge, nil)
            return
        }

        if method == NSURLAuthenticationMethodServerTrust {
            completionHandler(.performDefaultHandling, nil)
            return
        }

        if isICloudHost(challenge.protectionSpace.host), let credential {
            completionHandler(.useCredential, credential)
        } else {
            completionHandler(.performDefaultHandling, nil)
        }
    }
}
