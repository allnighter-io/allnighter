import XCTest
@testable import AllnighterCore

/// Every bundled fixture must decode, and re-encode/decode to an equal value.
final class FixtureRoundTripTests: XCTestCase {

    private func assertRoundTrips<T: Codable & Equatable>(_ type: T.Type, _ name: Fixtures.Name) throws {
        let decoded = try Fixtures.decode(type, name)
        let reEncoded = try CoreJSON.encode(decoded)
        let reDecoded = try CoreJSON.decode(type, from: reEncoded)
        XCTAssertEqual(decoded, reDecoded, "Round-trip mismatch for \(name.rawValue)")
    }

    func testPanelRoundTrips() throws {
        try assertRoundTrips([Worker].self, .panelSix)
        let panel = try Fixtures.panel()
        XCTAssertEqual(panel.count, 6)
        XCTAssertEqual(panel.first(where: { $0.id == "worker_opus" })?.role, .both)
        // Composer 2.5 and Grok Build share the `grok` driver.
        let composer = panel.first { $0.id == "worker_composer" }
        let grok = panel.first { $0.id == "worker_grok" }
        XCTAssertEqual(composer?.driverId, "grok")
        XCTAssertEqual(grok?.driverId, "grok")
    }

    func testManifestsRoundTrip() throws {
        try assertRoundTrips(DriverManifest.self, .manifestClaude)
        try assertRoundTrips(DriverManifest.self, .manifestGrok)
        try assertRoundTrips(DriverManifest.self, .manifestManual)
    }

    func testManualManifestHasNoInvoke() throws {
        let manual = try Fixtures.manifest(.manifestManual)
        XCTAssertEqual(manual.kind, .manualPaste)
        XCTAssertNil(manual.invoke)
        XCTAssertNil(manual.output)
    }

    func testRunsRoundTrip() throws {
        try assertRoundTrips(CouncilRun.self, .runInflight)
        try assertRoundTrips(CouncilRun.self, .runComplete)
        try assertRoundTrips(CouncilRun.self, .runPartial)
    }

    func testCompleteRunHasMasterPlan() throws {
        let run = try Fixtures.run(.runComplete)
        XCTAssertEqual(run.status, .complete)
        XCTAssertEqual(run.answeredMembers.count, 6)
        XCTAssertNotNil(run.synthesis?.masterPlanMarkdown)
    }

    func testPartialRunIsUsableDespiteFailures() throws {
        let run = try Fixtures.run(.runPartial)
        XCTAssertEqual(run.status, .partial)
        XCTAssertEqual(run.synthesis?.status, .failed)
        XCTAssertNil(run.synthesis?.masterPlanMarkdown)
        // Some members still answered; the run is readable.
        XCTAssertGreaterThanOrEqual(run.answeredMembers.count, 3)
        XCTAssertEqual(run.failedMembers.count, 2)
    }
}
