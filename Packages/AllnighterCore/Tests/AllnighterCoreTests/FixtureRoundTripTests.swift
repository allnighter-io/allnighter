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

    func testCompleteRunHasSeatsAnalysisAndPlan() throws {
        let run = try Fixtures.run(.runComplete)
        XCTAssertEqual(run.status, .complete)
        XCTAssertEqual(run.panel.count, 6)
        XCTAssertEqual(run.answeredMembers.count, 6)
        XCTAssertNotNil(run.analysis)
        XCTAssertEqual(run.analysis?.consensus.count, 1)
        XCTAssertNotNil(run.masterPlan)
        XCTAssertEqual(run.origin, .gui)
        XCTAssertEqual(run.presetId, "preset_six_default")
        // seats are keyed independently
        XCTAssertEqual(Set(run.members.map(\.seatId)).count, 6)
    }

    func testPresetFixturesRoundTrip() throws {
        try assertRoundTrips(SynthesisInstructionPreset.self, .synthesisPresetDefault)
        try assertRoundTrips(PanelPreset.self, .panelPresetDefault)

        let preset = try Fixtures.panelPreset()
        XCTAssertEqual(preset.seats.count, 6)
        XCTAssertEqual(preset.synthesis.judgeWorkerId, "worker_opus")
        XCTAssertEqual(preset.synthesis.analysisDepth, .combined)
        XCTAssertEqual(preset.workerIds.count, 6)
    }

    func testPanelPresetBuiltInDefaultDefaultsJudgeToOpus() throws {
        let panel = try Fixtures.panel()
        let preset = PanelPreset.builtInDefault(panel: panel, analysisProfileId: "judge_analysis_v1", planProfileId: "judge_plan_v1")
        XCTAssertEqual(preset.synthesis.judgeWorkerId, "worker_opus")
        XCTAssertEqual(preset.seats.map(\.workerId), panel.map(\.id))
        XCTAssertTrue(preset.builtIn)
    }

    func testSelfDoubleSeatExpansion() {
        let seats = [PanelSeatSpec(workerId: "worker_opus", count: 3)].expandedSeats()
        XCTAssertEqual(seats.map(\.id), ["worker_opus#0", "worker_opus#1", "worker_opus#2"])
        XCTAssertEqual(Set(seats.map(\.id)).count, 3)
    }

    func testPartialRunIsUsableDespiteFailures() throws {
        let run = try Fixtures.run(.runPartial)
        XCTAssertEqual(run.status, .partial)
        XCTAssertNotNil(run.analysis)            // analysis succeeded
        XCTAssertNil(run.masterPlan)             // plan failed
        XCTAssertEqual(run.latestStage(.plan)?.status, .failed)
        XCTAssertGreaterThanOrEqual(run.answeredMembers.count, 3)
        XCTAssertEqual(run.failedMembers.count, 2)
    }

    func testStagePayloadRoundTrips() throws {
        let analysis = StageOutput(id: "a", purpose: .analysis, status: .done, payload: .analysis(JudgeAnalysis(blindSpots: ["x"])))
        let plan = StageOutput(id: "p", purpose: .plan, status: .done, payload: .plan(markdown: "# Plan"))
        for stage in [analysis, plan] {
            let data = try CoreJSON.encode(stage)
            let back = try CoreJSON.decode(StageOutput.self, from: data)
            XCTAssertEqual(stage, back)
        }
    }
}
