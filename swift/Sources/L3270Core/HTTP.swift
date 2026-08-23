import Foundation
import Network

/// Shared HTTP transport helpers used by IPP (TLS) and Remote UI (plain).
enum HTTPTransport {
    final class Buffer {
        var data = [UInt8]()
    }

    static func send(
        address: NWEndpoint,
        request: [UInt8],
        parameters: NWParameters,
        connectTimeout: TimeInterval,
        totalTimeout: TimeInterval
    ) throws -> [UInt8] {
        let sem = DispatchSemaphore(value: 0)
        var failure: Error?
        let connection = NWConnection(to: address, using: parameters)
        let queue = DispatchQueue(label: "l3270.http")
        let buffer = Buffer()
        var connected = false

        queue.asyncAfter(deadline: .now() + connectTimeout) {
            if !connected {
                failure = IPPError.connectionFailed("connect timeout after \(connectTimeout)s")
                connection.cancel()
                sem.signal()
            }
        }

        connection.stateUpdateHandler = { state in
            switch state {
            case .ready:
                connected = true
                connection.send(
                    content: Data(request),
                    contentContext: .defaultMessage,
                    isComplete: true,
                    completion: .contentProcessed { error in
                        if let error {
                            failure = error
                            connection.cancel()
                            sem.signal()
                        } else {
                            receiveLoop(connection, into: buffer, sem: sem, queue: queue)
                        }
                    }
                )
            case .failed(let error):
                failure = error
                sem.signal()
            default:
                break
            }
        }
        connection.start(queue: queue)
        if sem.wait(timeout: .now() + totalTimeout) == .timedOut {
            connection.cancel()
            throw IPPError.connectionFailed("timeout after \(totalTimeout)s")
        }
        connection.cancel()
        if let failure { throw failure }

        let collected = buffer.data
        guard let (headerEnd, payload) = splitHTTP(collected) else {
            throw IPPError.badResponse("no HTTP header")
        }
        let head = String(decoding: collected[..<headerEnd], as: UTF8.self)
        var body = Array(payload)
        if head.lowercased().contains("transfer-encoding: chunked") {
            body = dechunk(body)
        }
        return body
    }

    static func receiveLoop(
        _ connection: NWConnection,
        into buffer: Buffer,
        sem: DispatchSemaphore,
        queue: DispatchQueue
    ) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { data, _, isComplete, error in
            if let data, !data.isEmpty { buffer.data.append(contentsOf: data) }
            if isComplete || error != nil {
                sem.signal()
                return
            }
            receiveLoop(connection, into: buffer, sem: sem, queue: queue)
        }
    }

    static func splitHTTP(_ raw: [UInt8]) -> (Int, ArraySlice<UInt8>)? {
        var i = 0
        while i + 3 < raw.count {
            if raw[i] == 0x0D, raw[i + 1] == 0x0A, raw[i + 2] == 0x0D, raw[i + 3] == 0x0A {
                return (i + 4, raw[(i + 4)...])
            }
            i += 1
        }
        return nil
    }

    static func splitHTTPResponse(_ raw: [UInt8]) -> HTTPResponse? {
        guard let (headerEnd, bodySlice) = splitHTTP(raw) else { return nil }
        let headerText = String(decoding: raw[..<headerEnd], as: UTF8.self)
        var statusCode = 0
        if let firstLine = headerText.split(separator: "\r\n", maxSplits: 1).first {
            let parts = firstLine.split(separator: " ")
            if parts.count >= 2, let code = Int(parts[1]) { statusCode = code }
        }
        var headers: [String: String] = [:]
        for line in headerText.split(separator: "\r\n").dropFirst() {
            guard let colon = line.firstIndex(of: ":") else { continue }
            let key = line[..<colon].trimmingCharacters(in: .whitespaces).lowercased()
            let value = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
            headers[key] = value
        }
        var body = Array(bodySlice)
        if headers["transfer-encoding"]?.lowercased() == "chunked" {
            body = dechunk(body)
        }
        return HTTPResponse(statusCode: statusCode, headers: headers, body: body)
    }

    static func dechunk(_ data: [UInt8]) -> [UInt8] {
        var out = [UInt8]()
        var pos = 0
        while pos < data.count {
            guard let lineEnd = findCRLF(data, from: pos) else { break }
            let sizeHex = String(decoding: data[pos..<lineEnd], as: UTF8.self)
            guard let size = Int(sizeHex.split(separator: ";").first ?? "", radix: 16) else { break }
            if size == 0 { break }
            let start = lineEnd + 2
            guard start + size <= data.count else { break }
            out.append(contentsOf: data[start..<start + size])
            pos = start + size + 2
        }
        return out
    }

    static func findCRLF(_ data: [UInt8], from: Int) -> Int? {
        var i = from
        while i + 1 < data.count {
            if data[i] == 0x0D, data[i + 1] == 0x0A { return i }
            i += 1
        }
        return nil
    }

    static func getaddrinfoList(host: String, port: Int) throws -> [NWEndpoint] {
        var hints = addrinfo()
        hints.ai_socktype = SOCK_STREAM
        var infoPtr: UnsafeMutablePointer<addrinfo>?
        let status = getaddrinfo(host, String(port), &hints, &infoPtr)
        guard status == 0, let first = infoPtr else {
            throw IPPError.connectionFailed(
                "getaddrinfo failed for \(host): \(String(cString: gai_strerror(status)))"
            )
        }
        defer { freeaddrinfo(infoPtr) }

        var v4 = [NWEndpoint]()
        var v6 = [NWEndpoint]()
        var info: UnsafeMutablePointer<addrinfo>? = first
        while let current = info {
            defer { info = current.pointee.ai_next }
            guard let sa = current.pointee.ai_addr else { continue }
            var hostBuf = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            let niStatus = getnameinfo(
                sa, current.pointee.ai_addrlen,
                &hostBuf, socklen_t(NI_MAXHOST), nil, 0, NI_NUMERICHOST
            )
            guard niStatus == 0 else { continue }
            let ip = String(cString: hostBuf)
            let endpoint = NWEndpoint.hostPort(
                host: .init(ip), port: .init(rawValue: UInt16(port))!
            )
            if current.pointee.ai_family == AF_INET {
                v4.append(endpoint)
            } else {
                v6.append(endpoint)
            }
        }
        return v4 + v6
    }
}

struct HTTPResponse {
    let statusCode: Int
    let headers: [String: String]
    let body: [UInt8]
}

/// Synchronous HTTP/1.1 POST over implicit TLS for IPP.
enum HTTP {
    static func post(
        host: String,
        port: Int,
        resource: String,
        body: [UInt8],
        timeout: TimeInterval
    ) throws -> [UInt8] {
        let header = "POST \(resource) HTTP/1.1\r\n"
            + "Host: \(host):\(port)\r\n"
            + "Content-Type: application/ipp\r\n"
            + "Content-Length: \(body.count)\r\n"
            + "Connection: close\r\n\r\n"
        let request = Array(header.utf8) + body
        let addresses = try HTTPTransport.getaddrinfoList(host: host, port: port)
        guard !addresses.isEmpty else {
            throw IPPError.connectionFailed("cannot resolve \(host)")
        }

        var lastError: Error?
        let connectTimeout = min(10, timeout / 4)
        for address in addresses {
            do {
                return try HTTPTransport.send(
                    address: address,
                    request: request,
                    parameters: parametersWithTLS(),
                    connectTimeout: connectTimeout,
                    totalTimeout: timeout
                )
            } catch {
                lastError = error
            }
        }
        throw IPPError.connectionFailed("\(lastError.map(String.init(describing:)) ?? "unknown")")
    }

    static func resolve(host: String, port: Int) throws -> [NWEndpoint] {
        try HTTPTransport.getaddrinfoList(host: host, port: port)
    }

    static func parametersWithTLS() -> NWParameters {
        let tcp = NWParameters.tcp
        let tlsOptions = NWProtocolTLS.Options()
        sec_protocol_options_set_verify_block(
            tlsOptions.securityProtocolOptions,
            { _, _, complete in complete(true) },
            DispatchQueue.global()
        )
        tcp.defaultProtocolStack.applicationProtocols.insert(tlsOptions, at: 0)
        return tcp
    }
}
