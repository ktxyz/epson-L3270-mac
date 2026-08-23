import XCTest
@testable import L3270Core

final class IPPTests: XCTestCase {
    func testPrintJobRequestEncoding() {
        let body = encodeRequest(
            operation: IPP.printJob,
            requestID: 7,
            operationAttrs: [
                attribute(IPP.tagCharset, "attributes-charset", "utf-8"),
                attribute(IPP.tagURI, "printer-uri", "ipp://x.local:631/ipp/print"),
                attribute(IPP.tagMimeMediaType, "document-format", "image/pwg-raster"),
            ],
            jobAttrs: [attribute(IPP.tagInteger, "copies", int: 2)]
        )
        XCTAssertEqual(body[2], 0x00)
        XCTAssertEqual(body[3], 0x02)
        XCTAssertEqual(body.last, IPP.endTag)
    }

    func testResponseParsing() throws {
        var body: [UInt8] = [0x01, 0x01, 0x00, 0x00, 0, 0, 0, 1, 0x01]
        func attr(_ tag: UInt8, _ name: String, _ value: [UInt8]) {
            let nameBytes = Array(name.utf8)
            body.append(tag)
            body.append(UInt8(nameBytes.count >> 8))
            body.append(UInt8(nameBytes.count & 0xFF))
            body.append(contentsOf: nameBytes)
            body.append(UInt8(value.count >> 8))
            body.append(UInt8(value.count & 0xFF))
            body.append(contentsOf: value)
        }
        attr(IPP.tagText, "printer-state", Array("3".utf8))
        body.append(IPP.endTag)
        let parsed = try parseResponse(body)
        XCTAssertEqual(parsed.status, 0)
        XCTAssertEqual(parsed.attributes["printer-state"], ["3"])
    }
}
