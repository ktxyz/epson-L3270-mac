import Foundation
import Network

public enum IPPError: Error, Equatable, CustomStringConvertible {
    case connectionFailed(String)
    case badResponse(String)
    case printerRejected(status: Int, message: String)

    public var description: String {
        switch self {
        case .connectionFailed(let why): return "connection failed: \(why)"
        case .badResponse(let why): return "bad IPP response: \(why)"
        case .printerRejected(let status, let message):
            let detail = message.isEmpty ? "" : " (\(message))"
            return String(format: "printer rejected job: status 0x%04x%@", status, detail)
        }
    }
}

public enum IPP {
    static let version: UInt16 = 0x0101
    static let printJob: UInt16 = 0x0002
    static let getPrinterAttributes: UInt16 = 0x000B
    static let statusOK: UInt16 = 0x0000

    static let tagInteger: UInt8 = 0x21
    static let tagEnum: UInt8 = 0x23
    static let tagText: UInt8 = 0x41
    static let tagName: UInt8 = 0x42
    static let tagKeyword: UInt8 = 0x44
    static let tagURI: UInt8 = 0x45
    static let tagCharset: UInt8 = 0x47
    static let tagNaturalLanguage: UInt8 = 0x48
    static let tagMimeMediaType: UInt8 = 0x49

    static let groupOperation: UInt8 = 0x01
    static let groupJob: UInt8 = 0x02
    static let endTag: UInt8 = 0x03
}

struct Attribute {
    let tag: UInt8
    let name: String
    let value: [UInt8]
}

func attribute(_ tag: UInt8, _ name: String, _ value: String) -> Attribute {
    Attribute(tag: tag, name: name, value: Array(value.utf8))
}

func attribute(_ tag: UInt8, _ name: String, int: Int) -> Attribute {
    var be = UInt32(bitPattern: Int32(truncatingIfNeeded: int)).bigEndian
    return Attribute(tag: tag, name: name, value: withUnsafeBytes(of: &be) { Array($0) })
}

func encodeRequest(
    operation: UInt16,
    requestID: UInt32,
    operationAttrs: [Attribute],
    jobAttrs: [Attribute] = []
) -> [UInt8] {
    var out = [UInt8]()
    out.append(UInt8(IPP.version >> 8))
    out.append(UInt8(IPP.version & 0xFF))
    out.append(UInt8(operation >> 8))
    out.append(UInt8(operation & 0xFF))
    out.append(UInt8(requestID >> 24)); out.append(UInt8(requestID >> 16))
    out.append(UInt8(requestID >> 8)); out.append(UInt8(requestID & 0xFF))
    out.append(IPP.groupOperation)
    for attr in operationAttrs { out.append(contentsOf: encodeAttribute(attr)) }
    if !jobAttrs.isEmpty {
        out.append(IPP.groupJob)
        for attr in jobAttrs { out.append(contentsOf: encodeAttribute(attr)) }
    }
    out.append(IPP.endTag)
    return out
}

private func encodeAttribute(_ attr: Attribute) -> [UInt8] {
    var out = [UInt8]()
    out.append(attr.tag)
    let name = Array(attr.name.utf8)
    out.append(UInt8(name.count >> 8)); out.append(UInt8(name.count & 0xFF))
    out.append(contentsOf: name)
    out.append(UInt8(attr.value.count >> 8)); out.append(UInt8(attr.value.count & 0xFF))
    out.append(contentsOf: attr.value)
    return out
}

struct IPPResponse {
    let status: UInt16
    let attributes: [String: [String]]
}

func parseResponse(_ data: [UInt8]) throws -> IPPResponse {
    guard data.count >= 8 else { throw IPPError.badResponse("too short") }
    let status = UInt16(data[2]) << 8 | UInt16(data[3])
    var attrs: [String: [String]] = [:]
    var currentName: String?
    var pos = 8
    while pos < data.count {
        let tag = data[pos]
        pos += 1
        if tag == IPP.endTag { break }
        if tag < 0x10 { currentName = nil; continue }
        guard pos + 2 <= data.count else { break }
        let nameLen = Int(data[pos]) << 8 | Int(data[pos + 1])
        pos += 2
        let name = String(decoding: data[pos..<min(pos + nameLen, data.count)], as: UTF8.self)
        pos += nameLen
        guard pos + 2 <= data.count else { break }
        let valueLen = Int(data[pos]) << 8 | Int(data[pos + 1])
        pos += 2
        let value = Array(data[pos..<min(pos + valueLen, data.count)])
        pos += valueLen
        if !name.isEmpty { currentName = name }
        guard let key = currentName else { continue }
        let decoded: String
        if (tag == IPP.tagInteger || tag == IPP.tagEnum) && value.count == 4 {
            let v = Int32(value[0]) << 24 | Int32(value[1]) << 16 | Int32(value[2]) << 8 | Int32(value[3])
            decoded = String(Int(v))
        } else {
            decoded = String(decoding: value, as: UTF8.self)
        }
        attrs[key, default: []].append(decoded)
    }
    return IPPResponse(status: status, attributes: attrs)
}

public final class IPPClient {
    public let host: String
    public let port: Int
    public let resource: String
    private var requestID: UInt32 = 0

    public init(host: String, port: Int = 631, resource: String = "/ipp/print") {
        self.host = host
        self.port = port
        self.resource = resource
    }

    public var uri: String { "ipp://\(host):\(port)\(resource)" }

    private func nextID() -> UInt32 {
        requestID = requestID &+ 1
        return requestID
    }

    public func getPrinterAttributes(timeout: TimeInterval = 10) throws -> [String: [String]] {
        let body = encodeRequest(
            operation: IPP.getPrinterAttributes,
            requestID: nextID(),
            operationAttrs: [
                attribute(IPP.tagCharset, "attributes-charset", "utf-8"),
                attribute(IPP.tagNaturalLanguage, "attributes-natural-language", "en"),
                attribute(IPP.tagURI, "printer-uri", uri),
                attribute(IPP.tagName, "requesting-user-name", "epson-print"),
                attribute(IPP.tagKeyword, "requested-attributes", "all"),
            ]
        )
        let response = try HTTP.post(
            host: host, port: port, resource: resource, body: body, timeout: timeout
        )
        let parsed = try parseResponse(response)
        guard parsed.status == IPP.statusOK else {
            throw IPPError.printerRejected(status: Int(parsed.status), message: "")
        }
        return parsed.attributes
    }

    public func printJob(
        document: [UInt8],
        jobName: String = "epson-print",
        copies: Int = 1,
        media: String? = nil,
        colorMode: String? = nil,
        quality: Int? = nil,
        timeout: TimeInterval = 120
    ) throws -> [String: [String]] {
        var jobAttrs = [attribute(IPP.tagInteger, "copies", int: copies)]
        if let media { jobAttrs.append(attribute(IPP.tagKeyword, "media", media)) }
        if let colorMode { jobAttrs.append(attribute(IPP.tagKeyword, "print-color-mode", colorMode)) }
        if let quality { jobAttrs.append(attribute(IPP.tagEnum, "print-quality", int: quality)) }

        let body = encodeRequest(
            operation: IPP.printJob,
            requestID: nextID(),
            operationAttrs: [
                attribute(IPP.tagCharset, "attributes-charset", "utf-8"),
                attribute(IPP.tagNaturalLanguage, "attributes-natural-language", "en"),
                attribute(IPP.tagURI, "printer-uri", uri),
                attribute(IPP.tagName, "requesting-user-name", "epson-print"),
                attribute(IPP.tagName, "job-name", jobName),
                attribute(IPP.tagMimeMediaType, "document-format", "image/pwg-raster"),
            ],
            jobAttrs: jobAttrs
        )
        let response = try HTTP.post(
            host: host, port: port, resource: resource,
            body: body + document, timeout: timeout
        )
        let parsed = try parseResponse(response)
        guard parsed.status == IPP.statusOK else {
            let messages = (parsed.attributes["status-message"] ?? [])
                + (parsed.attributes["detailed-status-message"] ?? [])
            throw IPPError.printerRejected(
                status: Int(parsed.status), message: messages.joined(separator: "; ")
            )
        }
        return parsed.attributes
    }
}
