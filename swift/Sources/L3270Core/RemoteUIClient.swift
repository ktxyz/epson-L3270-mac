import Foundation

public struct InkLevels: Equatable {
    public let black: Int?
    public let cyan: Int?
    public let magenta: Int?
    public let yellow: Int?
    public let waste: Int?

    public init(black: Int?, cyan: Int?, magenta: Int?, yellow: Int?, waste: Int? = nil) {
        self.black = black
        self.cyan = cyan
        self.magenta = magenta
        self.yellow = yellow
        self.waste = waste
    }

    public var hasAnyLevel: Bool {
        [black, cyan, magenta, yellow, waste].contains { $0 != nil }
    }
}

public struct PrinterStatus: Equatable {
    public let state: String
    public let ink: InkLevels
    public let firmware: String?

    public init(state: String, ink: InkLevels, firmware: String? = nil) {
        self.state = state
        self.ink = ink
        self.firmware = firmware
    }
}

public enum RemoteUIError: Error, Equatable, CustomStringConvertible {
    case authFailed
    case sessionExpired
    case parseFailed
    case connectionFailed(String)

    public var description: String {
        switch self {
        case .authFailed: return "Incorrect password."
        case .sessionExpired: return "Session expired; log in again."
        case .parseFailed: return "Could not parse printer status page."
        case .connectionFailed(let why): return "Connection failed: \(why)"
        }
    }
}

/// Client for the Epson embedded Remote UI (HTTP port 80).
public final class RemoteUIClient {
    public static let fullTankHeightPx = 50

    private let host: String
    private let http: RemoteHTTPClient
    private var password: String?

    public init(host: String) {
        self.host = host
        self.http = RemoteHTTPClient()
    }

    public func setPassword(_ password: String) {
        self.password = password
    }

    public func login(password: String) throws {
        let body = "session=\(urlEncode(password))&dummy=&from=top&trigger=set&access=https"
        let response = try http.post(host: host, path: "/PRESENTATION/PSWD", body: body)
        let html = String(decoding: response.body, as: UTF8.self)
        if html.contains("Incorrect password") {
            throw RemoteUIError.authFailed
        }
        if http.cookies["EPSON_COOKIE_SESSION"] == nil, !html.lowercased().contains("index") {
            throw RemoteUIError.authFailed
        }
        self.password = password
    }

    public func fetchStatus() throws -> PrinterStatus {
        if password == nil {
            throw RemoteUIError.authFailed
        }
        if http.cookies.isEmpty, let password {
            try login(password: password)
        }

        let paths = [
            "/PRESENTATION/HTML/TOP/PRTINFO.HTML",
            "/PRESENTATION/ADVANCED/INFO_PRTINFO/TOP",
        ]
        for path in paths {
            let response = try http.get(host: host, path: path)
            let html = String(decoding: response.body, as: UTF8.self)
            if html.contains("/PRESENTATION/PSWD") || html.contains("Incorrect password") {
                if let password {
                    try login(password: password)
                    continue
                }
                throw RemoteUIError.sessionExpired
            }
            if let status = RemoteUIParser.parse(html) {
                return status
            }
        }
        throw RemoteUIError.parseFailed
    }

    private func urlEncode(_ value: String) -> String {
        value.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? value
    }
}

/// Parses ink levels from Epson Remote UI HTML.
public enum RemoteUIParser {
    public static let fullTankHeightPx = RemoteUIClient.fullTankHeightPx

    public static func parse(_ html: String) -> PrinterStatus? {
        let ink = parseInkLevels(html)
        let state = parseState(html) ?? "Unknown"
        let firmware = parseFirmware(html)
        if !ink.hasAnyLevel, state == "Unknown", firmware == nil {
            return nil
        }
        return PrinterStatus(state: state, ink: ink, firmware: firmware)
    }

    public static func parseInkLevels(_ html: String) -> InkLevels {
        InkLevels(
            black: inkPercent(html, markers: ["Ink_K", "INK_K", "ink_k"]),
            cyan: inkPercent(html, markers: ["Ink_C", "INK_C", "ink_c"]),
            magenta: inkPercent(html, markers: ["Ink_M", "INK_M", "ink_m"]),
            yellow: inkPercent(html, markers: ["Ink_Y", "INK_Y", "ink_y"]),
            waste: inkPercent(html, markers: ["Ink_Waste", "INK_WASTE", "ink_waste"])
        )
    }

    private static func inkPercent(_ html: String, markers: [String]) -> Int? {
        for marker in markers {
            if let height = extractImageHeight(html, containing: marker) {
                return min(100, max(0, Int(round(Double(height) / Double(fullTankHeightPx) * 100.0))))
            }
        }
        return nil
    }

    static func extractImageHeight(_ html: String, containing marker: String) -> Int? {
        let lower = html.lowercased()
        let markerLower = marker.lowercased()
        var searchStart = lower.startIndex
        while let range = lower.range(of: markerLower, range: searchStart..<lower.endIndex) {
            let windowStart = lower.index(range.lowerBound, offsetBy: -120, limitedBy: lower.startIndex) ?? lower.startIndex
            let windowEnd = lower.index(range.upperBound, offsetBy: 120, limitedBy: lower.endIndex) ?? lower.endIndex
            let window = String(html[windowStart..<windowEnd])
            if let height = firstHeightAttribute(in: window) {
                return height
            }
            searchStart = range.upperBound
        }
        return nil
    }

    static func firstHeightAttribute(in fragment: String) -> Int? {
        let pattern = #"height\s*=\s*["']?(\d+)["']?"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else {
            return nil
        }
        let ns = fragment as NSString
        let range = NSRange(location: 0, length: ns.length)
        guard let match = regex.firstMatch(in: fragment, range: range),
              match.numberOfRanges >= 2 else { return nil }
        let capture = ns.substring(with: match.range(at: 1))
        return Int(capture)
    }

    static func parseState(_ html: String) -> String? {
        let patterns = [
            #"Printer\s+Status[^<]*</[^>]+>\s*<[^>]+>([^<]+)"#,
            #"Status[^<]*</[^>]+>\s*<[^>]+>([^<]+)"#,
            #"class=['\"]status['\"][^>]*>([^<]+)"#,
        ]
        for pattern in patterns {
            if let value = firstCapture(html, pattern: pattern)?.trimmingCharacters(in: .whitespacesAndNewlines),
               !value.isEmpty {
                return value
            }
        }
        if html.localizedCaseInsensitiveContains("Available") { return "Available" }
        if html.localizedCaseInsensitiveContains("Printing") { return "Printing" }
        return nil
    }

    static func parseFirmware(_ html: String) -> String? {
        firstCapture(html, pattern: #"Firmware[^<]*</[^>]+>\s*<[^>]+>([^<]+)"#)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func firstCapture(_ html: String, pattern: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive, .dotMatchesLineSeparators]) else {
            return nil
        }
        let ns = html as NSString
        let range = NSRange(location: 0, length: ns.length)
        guard let match = regex.firstMatch(in: html, range: range),
              match.numberOfRanges >= 2 else { return nil }
        return ns.substring(with: match.range(at: 1))
    }
}
