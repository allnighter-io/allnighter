import XCTest
@testable import AllnighterCore

final class TeachingSnippetTests: XCTestCase {
    func testContentHashIsStable() {
        let a = TeachingSnippet.contentHash
        let b = TeachingSnippet.hash(of: TeachingSnippet.body)
        XCTAssertEqual(a, b)
        XCTAssertEqual(a.count, 64, "SHA256 hex")
        XCTAssertEqual(TeachingSnippet.contentHash, a)
    }

    func testWrapUnwrapRoundTrip() {
        let marked = TeachingSnippet.wrap()
        XCTAssertTrue(marked.hasPrefix(TeachingSnippet.openMarkerPrefix))
        XCTAssertTrue(marked.hasSuffix(TeachingSnippet.closeMarker))
        let parsed = TeachingSnippet.parse(marked)
        XCTAssertEqual(parsed.state, .installed)
        XCTAssertEqual(parsed.version, TeachingSnippet.schemaVersion)
        XCTAssertEqual(parsed.hash, TeachingSnippet.contentHash)
        XCTAssertEqual(parsed.body, TeachingSnippet.body)
    }

    func testParseAbsent() {
        XCTAssertEqual(TeachingSnippet.parse(nil).state, .absent)
        XCTAssertEqual(TeachingSnippet.parse("").state, .absent)
        XCTAssertEqual(TeachingSnippet.parse("no markers here").state, .absent)
    }

    func testParseStaleOlderVersion() {
        let marked = TeachingSnippet.wrap(version: 0, hash: TeachingSnippet.contentHash)
        let parsed = TeachingSnippet.parse(marked)
        XCTAssertEqual(parsed.state, .stale)
        XCTAssertEqual(parsed.version, 0)
        XCTAssertTrue(parsed.detail.contains("older"))
    }

    func testParseModifiedHashMismatch() {
        let marked = TeachingSnippet.wrap(hash: String(repeating: "ab", count: 32))
        let parsed = TeachingSnippet.parse(marked)
        XCTAssertEqual(parsed.state, .modified)
        XCTAssertEqual(parsed.version, TeachingSnippet.schemaVersion)
    }

    func testParseModifiedBodyEdit() {
        let tampered = TeachingSnippet.body + "\n- Extra hand edit."
        let marked = TeachingSnippet.wrap(body: tampered, hash: TeachingSnippet.contentHash)
        let parsed = TeachingSnippet.parse(marked)
        XCTAssertEqual(parsed.state, .modified)
    }

    func testParseMalformedDuplicateMarkers() {
        let once = TeachingSnippet.wrap()
        let dup = once + "\n" + once
        XCTAssertEqual(TeachingSnippet.parse(dup).state, .malformed)
    }

    func testParseMalformedCloseOnly() {
        let text = "preamble\n\(TeachingSnippet.closeMarker)\n"
        XCTAssertEqual(TeachingSnippet.parse(text).state, .malformed)
    }

    func testBodyTeachesMenuNotPanel() {
        XCTAssertTrue(TeachingSnippet.body.contains("alln menu --json"))
        XCTAssertTrue(TeachingSnippet.body.contains("alln run --dry-run"))
        XCTAssertFalse(TeachingSnippet.body.contains("panel start"))
    }
}
