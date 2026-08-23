import XCTest
import CoreGraphics
import PDFKit
@testable import L3270Core

final class RendererTests: XCTestCase {
    func testChannelOrderThroughRender() throws {
        let width = 100
        let height = 100
        let data = NSMutableData() as CFMutableData
        var mediaBox = CGRect(x: 0, y: 0, width: width, height: height)
        guard let consumer = CGDataConsumer(data: data),
              let context = CGContext(consumer: consumer, mediaBox: &mediaBox, nil)
        else {
            XCTFail("PDF context")
            return
        }
        context.beginPDFPage(nil)
        context.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 1))
        context.fill(CGRect(x: 10, y: 10, width: 30, height: 30))
        context.endPDFPage()
        context.closePDF()

        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("colors.pdf")
        try (data as Data).write(to: tmp)
        defer { try? FileManager.default.removeItem(at: tmp) }

        let geo = try geometry(for: "a4")
        let pages = try Renderer.renderPDF(url: tmp, geometry: geo, mono: false)
        XCTAssertEqual(pages.count, 1)
        let raw = pages[0].raw
        var foundRed = false
        for i in stride(from: 0, to: raw.count, by: 3) {
            if raw[i] > 200, raw[i + 1] < 80, raw[i + 2] < 80 {
                foundRed = true
                break
            }
        }
        XCTAssertTrue(foundRed, "expected red pixels in rendered output")
    }

    func testRealPDFRenderAndEncode() throws {
        let repoRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let pdf = repoRoot.appendingPathComponent("samples/test-page.pdf")
        guard FileManager.default.fileExists(atPath: pdf.path) else {
            throw XCTSkip("samples/test-page.pdf not present")
        }
        let geo = try geometry(for: "a4")
        let pages = try Renderer.renderFile(url: pdf, geometry: geo, mono: false)
        XCTAssertEqual(pages.count, 1)
        let doc = try writePWGRaster(
            pages: pages,
            colorSpace: PWGRaster.colorSpaceSRGB,
            mediaName: geo.media,
            mediaWidth: geo.sizeHW.width,
            mediaHeight: geo.sizeHW.height
        )
        XCTAssertGreaterThan(doc.count, 1000)
    }
}
