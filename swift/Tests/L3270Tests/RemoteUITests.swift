import XCTest
@testable import L3270Core

final class RemoteUITests: XCTestCase {
    func testParseInkLevelsFromFixture() throws {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "prtinfo-authenticated", withExtension: "html"))
        let html = try String(contentsOf: url, encoding: .utf8)
        let status = try XCTUnwrap(RemoteUIParser.parse(html))
        XCTAssertEqual(status.state, "Available")
        XCTAssertEqual(status.firmware, "TEST-FW-1.0.0")
        XCTAssertEqual(status.ink.black, 80)
        XCTAssertEqual(status.ink.cyan, 70)
        XCTAssertEqual(status.ink.magenta, 50)
        XCTAssertEqual(status.ink.yellow, 90)
        XCTAssertEqual(status.ink.waste, 20)
    }

    func testExtractImageHeight() {
        let fragment = #"<img src="/IMAGE/Ink_K.PNG" height="42" class="color">"#
        XCTAssertEqual(RemoteUIParser.extractImageHeight(fragment, containing: "Ink_K"), 42)
    }

    func testParseMissingInkReturnsNilOverall() {
        XCTAssertNil(RemoteUIParser.parse("<html><body>no data</body></html>"))
    }
}
