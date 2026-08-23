import XCTest
@testable import L3270Core

final class RasterTests: XCTestCase {
    func get32(_ buf: [UInt8], _ offset: Int) -> Int {
        var value: UInt32 = 0
        for i in 0..<4 { value = (value << 8) | UInt32(buf[offset + i]) }
        return Int(value)
    }

    func testHeaderSizeMatchesLibcups() {
        XCTAssertEqual(PWGRaster.headerSize, 1796)
    }

    func testHeaderLayout() throws {
        let h = try pageHeader(
            width: 2976, height: 4209,
            colorSpace: PWGRaster.colorSpaceSRGB,
            mediaName: "iso_a4_210x297mm"
        )
        XCTAssertEqual(h.count, PWGRaster.headerSize)
        XCTAssertEqual(Array(h[0..<9]), Array("PwgRaster".utf8))
        XCTAssertEqual(get32(h, 276), 360)
        XCTAssertEqual(get32(h, 372), 2976)
        XCTAssertEqual(get32(h, 388), 24)
        XCTAssertEqual(get32(h, 392), 2976 * 3)
        let nameBytes = Array(h[1732..<1796])
        XCTAssertEqual(Array(nameBytes[0..<16]), Array("iso_a4_210x297mm".utf8))
    }

    func testPackbitsLiteralOnePixel() {
        let row: [UInt8] = [255, 0, 0, 0, 255, 0]
        let enc = packbitsRow(row, bpp: 3)
        XCTAssertEqual(enc[0], 0)
    }

    func testCompress2x2() {
        let row0: [UInt8] = [255, 0, 0, 255, 0, 0]
        let row1: [UInt8] = [0, 255, 0, 0, 0, 255]
        let raw = row0 + row1
        let stream = compressRows(raw: raw, width: 2, height: 2, bpp: 3)
        XCTAssertEqual(stream.count, 13)
    }

    func testWriteDocumentStructure() throws {
        let raw: [UInt8] = Array(repeating: 255, count: 4 * 3)
        let doc = try writePWGRaster(
            pages: [(raw, 2, 2)],
            colorSpace: PWGRaster.colorSpaceSRGB,
            mediaName: "iso_a4_210x297mm",
            mediaWidth: 595,
            mediaHeight: 841
        )
        XCTAssertEqual(Array(doc[0..<4]), Array("RaS2".utf8))
        XCTAssertEqual(doc.count, 4 + PWGRaster.headerSize + compressRows(raw: raw, width: 2, height: 2, bpp: 3).count)
    }

    func testInvalidColorSpace() {
        XCTAssertThrowsError(try pageHeader(width: 10, height: 10, colorSpace: 99))
    }
}
