import Foundation
import Network

/// Plain HTTP client for the Epson Remote UI (port 80).
public final class RemoteHTTPClient {
    public var cookies: [String: String] = [:]

    public init() {}

    public func get(host: String, path: String, timeout: TimeInterval = 15) throws -> HTTPResponse {
        var header = "GET \(path) HTTP/1.1\r\n"
            + "Host: \(host)\r\n"
            + "Connection: close\r\n"
        if !cookies.isEmpty {
            let cookieHeader = cookies.map { "\($0.key)=\($0.value)" }.joined(separator: "; ")
            header += "Cookie: \(cookieHeader)\r\n"
        }
        header += "\r\n"
        return try send(host: host, port: 80, request: Array(header.utf8), timeout: timeout)
    }

    public func post(
        host: String,
        path: String,
        body: String,
        contentType: String = "application/x-www-form-urlencoded",
        timeout: TimeInterval = 15
    ) throws -> HTTPResponse {
        let bodyBytes = Array(body.utf8)
        var header = "POST \(path) HTTP/1.1\r\n"
            + "Host: \(host)\r\n"
            + "Content-Type: \(contentType)\r\n"
            + "Content-Length: \(bodyBytes.count)\r\n"
            + "Connection: close\r\n"
        if !cookies.isEmpty {
            let cookieHeader = cookies.map { "\($0.key)=\($0.value)" }.joined(separator: "; ")
            header += "Cookie: \(cookieHeader)\r\n"
        }
        header += "\r\n"
        return try send(host: host, port: 80, request: Array(header.utf8) + bodyBytes, timeout: timeout)
    }

    private func send(host: String, port: Int, request: [UInt8], timeout: TimeInterval) throws -> HTTPResponse {
        let addresses = try HTTPTransport.getaddrinfoList(host: host, port: port)
        guard !addresses.isEmpty else {
            throw RemoteUIError.connectionFailed("cannot resolve \(host)")
        }
        var lastError: Error?
        let connectTimeout = min(10, timeout / 4)
        for address in addresses {
            do {
                let raw = try HTTPTransport.send(
                    address: address,
                    request: request,
                    parameters: .tcp,
                    connectTimeout: connectTimeout,
                    totalTimeout: timeout
                )
                guard let response = HTTPTransport.splitHTTPResponse(raw) else {
                    throw RemoteUIError.connectionFailed("invalid HTTP response")
                }
                storeCookies(from: response.headers)
                return response
            } catch {
                lastError = error
            }
        }
        throw RemoteUIError.connectionFailed("\(lastError.map(String.init(describing:)) ?? "unknown")")
    }

    private func storeCookies(from headers: [String: String]) {
        guard let setCookie = headers["set-cookie"] else { return }
        for part in setCookie.split(separator: ";") {
            let pair = part.split(separator: "=", maxSplits: 1)
            guard pair.count == 2 else { continue }
            let key = String(pair[0]).trimmingCharacters(in: .whitespaces)
            let value = String(pair[1]).trimmingCharacters(in: .whitespaces)
            cookies[key] = value
        }
    }
}
