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

    func testBodyTeachesLiveMenuReflexAndDetachedDelivery() {
        XCTAssertEqual(TeachingSnippet.schemaVersion, 8)
        XCTAssertEqual(TeachingSnippet.reflexLines.count, 11)
        XCTAssertTrue(
            TeachingSnippet.reflexLines.contains { $0.contains("pmTurn.report") },
            "agents must learn where the pilot dev report lives"
        )
        XCTAssertTrue(
            TeachingSnippet.reflexLines.contains { $0.contains("artifact.path") },
            "agents must surface the team artifact after a terminal run"
        )
        XCTAssertEqual(TeachingSnippet.body, TeachingSnippet.reflexLines.joined(separator: "\n"))
        XCTAssertTrue(TeachingSnippet.body.contains("alln menu --json"))
        XCTAssertTrue(TeachingSnippet.body.contains("useWhen"))
        XCTAssertTrue(TeachingSnippet.body.contains("dontUseWhen"))
        XCTAssertTrue(TeachingSnippet.body.contains("validation template"))
        XCTAssertTrue(TeachingSnippet.body.contains("never trust a pasted catalog"))
        XCTAssertTrue(TeachingSnippet.body.contains("nextAction.command"))
        XCTAssertTrue(TeachingSnippet.body.contains("alln show <id> --stream"))
        XCTAssertTrue(TeachingSnippet.body.contains("never poll or resume"))
        // CD-S03: relay aggregate ≠ dev leg.
        XCTAssertTrue(TeachingSnippet.body.contains("devRunId"))
        XCTAssertTrue(TeachingSnippet.body.contains("Relay running"))
        // AVQ-S04: parallel feedback lock policy.
        XCTAssertTrue(TeachingSnippet.body.contains("--read-only"))
        XCTAssertTrue(TeachingSnippet.body.contains("--no-commit"))
        // AVQ-S03: one mutator + running ≠ progress; observation block replaces progressStale.
        XCTAssertTrue(TeachingSnippet.body.contains("One mutator"))
        XCTAssertTrue(TeachingSnippet.body.contains("observation"))
        XCTAssertTrue(TeachingSnippet.body.contains("alln show <id> --json"))
        // Capacity print contract: user-visible verbatim table, not shell-tool summary.
        XCTAssertTrue(
            TeachingSnippet.body.contains("alln capacity"),
            "agents must know bare alln capacity is the print path"
        )
        XCTAssertTrue(
            TeachingSnippet.body.contains("COMPLETE human-readable stdout table verbatim"),
            "agents must paste the full capacity table in the final response"
        )
        XCTAssertTrue(
            TeachingSnippet.body.contains("shown above"),
            "agents must be told never to say shown above instead of pasting the table"
        )
        XCTAssertTrue(
            TeachingSnippet.body.contains("Use `--json` only when the user explicitly requests"),
            "JSON is opt-in on explicit request only"
        )
        XCTAssertFalse(TeachingSnippet.body.contains("progressStale"))
        XCTAssertFalse(TeachingSnippet.body.contains("delivery command"))
        XCTAssertFalse(TeachingSnippet.body.contains("team hello"))
        XCTAssertFalse(TeachingSnippet.body.contains("route --for"))
        XCTAssertFalse(TeachingSnippet.body.contains("resolve --for"))
        XCTAssertFalse(TeachingSnippet.body.contains("panel start"))
        // No embedded catalog rows.
        XCTAssertFalse(TeachingSnippet.body.contains("model_sonnet"))
        XCTAssertFalse(TeachingSnippet.body.contains("code_growth"))
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
}
