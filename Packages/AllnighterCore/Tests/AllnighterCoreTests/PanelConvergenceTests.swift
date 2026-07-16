import XCTest
@testable import AllnighterCore

/// PP-S03 — path-overlap convergence flag (`docs/phases/Panel_Polish.md` §1 decision 4).
final class PanelConvergenceTests: XCTestCase {

    // MARK: - Projection rules

    /// Two seats citing the same file in evidence → exactly one entry naming both.
    func testTwoSeatsCitingSameFileYieldsOneEntry() {
        let a = seat(
            "model_a",
            findings: [finding(claim: "boundary weak", evidence: "see docs/phases/Pilot_Panel.md:42")]
        )
        let b = seat(
            "model_b",
            findings: [finding(claim: "same file", evidence: "docs/phases/Pilot_Panel.md cites consent")]
        )
        let entries = PanelConvergence.project(from: [a, b])
        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entries[0].anchor, "docs/phases/Pilot_Panel.md")
        XCTAssertEqual(entries[0].seats, ["model_a", "model_b"])
    }

    /// One seat citing an anchor twice (two findings) is NOT convergence.
    func testSingleSeatRepeatingAnchorIsNotConvergence() {
        let solo = seat(
            "model_solo",
            findings: [
                finding(claim: "first hit on Foo.swift:10", evidence: "Foo.swift:10"),
                finding(claim: "second hit", evidence: "also Foo.swift:99"),
            ]
        )
        let entries = PanelConvergence.project(from: [solo])
        XCTAssertEqual(entries, [], "single-seat repeat must not produce a convergence entry")
    }

    /// Three+ anchors from multi-seat overlap sort lexically by anchor; seats sorted.
    func testDeterministicLexicalOrderingWithThreeAnchors() {
        let a = seat(
            "zeta",
            findings: [
                finding(claim: "z", evidence: "z/last.md"),
                finding(claim: "a", evidence: "a/first.swift:1"),
                finding(claim: "m", evidence: "m/mid.ts"),
            ]
        )
        let b = seat(
            "alpha",
            findings: [
                finding(claim: "mid", evidence: "m/mid.ts:3"),
                finding(claim: "first", evidence: "a/first.swift"),
                finding(claim: "last", evidence: "z/last.md:7"),
            ]
        )
        let entries = PanelConvergence.project(from: [a, b])
        XCTAssertEqual(entries.map(\.anchor), ["a/first.swift", "m/mid.ts", "z/last.md"])
        for entry in entries {
            XCTAssertEqual(entry.seats, ["alpha", "zeta"])
        }
    }

    /// Clean round keeps `convergence` present as `[]` (not nil / not omitted) on the envelope.
    func testCleanRoundConvergenceIsEmptyArrayPresentNotOmitted() throws {
        let clean = seat(
            "model_sonnet",
            findings: [finding(claim: "ok", evidence: "no shared path here")]
        )
        let entries = PanelConvergence.project(from: [clean])
        XCTAssertEqual(entries, [])

        let envelope = PanelRoundJSON(
            contractVersion: ContractRegistry.contractVersion,
            panel: PanelJSON.project(
                PanelState(
                    id: "panel_conv_clean", projectRoot: "/repo", projectId: "proj",
                    targetPath: "docs/spec.md", seats: [],
                    status: .awaitingPM, createdAt: Date()
                ),
                contractVersion: ContractRegistry.contractVersion
            ),
            round: 1,
            attempt: 1,
            targetHash: "def",
            briefSource: "builtin",
            seatResults: [SeatResultJSON(clean)],
            unstructuredSeats: [],
            convergence: entries
        )
        XCTAssertEqual(envelope.convergence, [])
        let encoded = try JSONEncoder().encode(envelope)
        let obj = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        let conv = try XCTUnwrap(obj["convergence"] as? [Any])
        XCTAssertEqual(conv.count, 0, "field must be present and empty, not nil/omitted")
    }

    // MARK: - Token extraction

    func testExtractStripsLineNumbersAndPunctuation() {
        let anchors = PanelConvergence.extractAnchors(
            from: "See (docs/phases/Panel_Polish.md:42) and Packages/AllnighterCore/Sources/AllnighterCore/PanelJSON.swift:10:3."
        )
        XCTAssertEqual(
            Set(anchors),
            Set([
                "docs/phases/Panel_Polish.md",
                "Packages/AllnighterCore/Sources/AllnighterCore/PanelJSON.swift",
            ])
        )
    }

    func testBareFilenameWithKnownSuffixIsPathShaped() {
        let anchors = PanelConvergence.extractAnchors(from: "problem is in PanelCLI.swift only")
        XCTAssertEqual(anchors, ["PanelCLI.swift"])
    }

    func testPlainWordsAreNotAnchors() {
        let anchors = PanelConvergence.extractAnchors(from: "the consent boundary is load-bearing")
        XCTAssertEqual(anchors, [])
    }

    // MARK: - Helpers

    private func finding(claim: String, evidence: String) -> Finding {
        Finding(claim: claim, severity: .medium, evidence: evidence)
    }

    private func seat(_ workerId: String, findings: [Finding]) -> SeatResult {
        SeatResult(
            workerId: workerId,
            lens: "adversary",
            status: .done,
            findings: findings,
            report: "structured"
        )
    }
}
