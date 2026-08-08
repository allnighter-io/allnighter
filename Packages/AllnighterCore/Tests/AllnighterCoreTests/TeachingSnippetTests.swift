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
        XCTAssertEqual(TeachingSnippet.schemaVersion, 11)
        XCTAssertEqual(TeachingSnippet.reflexLines.count, 3)
        XCTAssertEqual(TeachingSnippet.body, TeachingSnippet.reflexLines.joined(separator: "\n"))
        // 1 — the front door, and the reflex to re-read it.
        XCTAssertTrue(TeachingSnippet.body.contains("alln menu --json"))
        XCTAssertTrue(TeachingSnippet.body.contains("Never a pasted catalog"))
        // 2 — the status field reads as progress; contradict it. v11 scopes
        // the rule to in-flight runs and routes terminal readers to the verdict,
        // because `observation.ownerState: dead` is what a FINISHED worker looks
        // like and the v10 wording made a cold agent call a Ready run a crash.
        XCTAssertTrue(TeachingSnippet.body.contains("observation"))
        XCTAssertTrue(TeachingSnippet.body.contains("alln show <id> --json"))
        XCTAssertTrue(TeachingSnippet.body.contains("outcome.headline"),
                      "terminal readers must be routed to the verdict, not to process state")
        XCTAssertTrue(TeachingSnippet.body.contains("while running"),
                      "the observation rule must be scoped to in-flight runs")
        // 3 — detached delivery: run the waiter once, do not poll.
        XCTAssertTrue(TeachingSnippet.body.contains("nextAction.command"))
        XCTAssertTrue(TeachingSnippet.body.contains("Never poll"))

        // v10 subtractions — anything the menu already carries must stay out.
        XCTAssertFalse(TeachingSnippet.body.contains("canonical id"), "menu ships every id verbatim")
        XCTAssertFalse(TeachingSnippet.body.contains("validation template"), "menu ships validateExample")
        XCTAssertFalse(TeachingSnippet.body.lowercased().contains("invent"), "anti-hallucination folklore")
        XCTAssertFalse(TeachingSnippet.body.contains("mutating worker"), "teams[].mutating + the write lock say it")
        XCTAssertFalse(TeachingSnippet.body.contains("progressStale"))
        XCTAssertFalse(TeachingSnippet.body.contains("delivery command"))
        XCTAssertFalse(TeachingSnippet.body.contains("team hello"))
        XCTAssertFalse(TeachingSnippet.body.contains("route --for"))
        XCTAssertFalse(TeachingSnippet.body.contains("resolve --for"))
        XCTAssertFalse(TeachingSnippet.body.contains("panel start"))
    }

    /// The seam that let retired vocabulary ship for months.
    ///
    /// `RetiredVocabulary` denies *command* spellings (`pair relay`, `pair
    /// pilot`), but the v8 rules used the bare prose nouns — "Relay running",
    /// "Pilot/relay dev report" — so no gate could see them, and a test
    /// requiring `pmTurn.report` pinned one of them in place. Deny the nouns in
    /// the one body that gets pasted into every host on earth.
    func testBodyIsFreeOfRetiredVocabulary() {
        let lowered = TeachingSnippet.body.lowercased()
        for noun in ["relay", "pilot", "devrunid", "pmturn", "devleg", "panel", "council"] {
            XCTAssertFalse(
                lowered.contains(noun),
                "teaching body ships retired vocabulary '\(noun)' — the loop grammar replaced it"
            )
        }
        for term in RetiredVocabulary.denyTerms {
            XCTAssertFalse(
                lowered.contains(term.lowercased()),
                "teaching body ships denied term '\(term)'"
            )
        }
    }

    /// The block is pasted permanently into files the user owns and guards. Size
    /// is a product constraint, not a style note: the v8 body was 95% of the
    /// founder's entire global CLAUDE.md, which is how a block gets deleted
    /// wholesale. Founder ruling: "a few lines that matter is all it takes."
    func testBodyStaysSmallEnoughToSurviveInSomeoneElsesFile() {
        XCTAssertLessThanOrEqual(
            TeachingSnippet.reflexLines.count, 4,
            "teaching body is growing back — every added rule must beat 'put it in the live menu'"
        )
        XCTAssertLessThanOrEqual(
            TeachingSnippet.body.count, 320,
            "teaching body is \(TeachingSnippet.body.count) chars; it competes with the user's own instructions"
        )
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
