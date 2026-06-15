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
        try assertRoundTrips([Model].self, .modelsSix)
        let models = try Fixtures.models()
        XCTAssertEqual(models.count, 6)
        XCTAssertEqual(models.first(where: { $0.id == "model_opus" })?.role, .both)
        let composer = models.first { $0.id == "model_composer" }
        let grok = models.first { $0.id == "model_grok" }
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
        try assertRoundTrips(TeamRun.self, .runInflight)
        try assertRoundTrips(TeamRun.self, .runComplete)
        try assertRoundTrips(TeamRun.self, .runPartial)
    }

    func testCompleteRunHasSeatsAnalysisAndPlan() throws {
        let run = try Fixtures.run(.runComplete)
        XCTAssertEqual(run.status, .complete)
        XCTAssertEqual(run.workers.count, 6)
        XCTAssertEqual(run.answeredWorkers.count, 6)
        XCTAssertNotNil(run.analysis)
        XCTAssertEqual(run.analysis?.consensus.count, 1)
        XCTAssertNotNil(run.plan)
        XCTAssertEqual(run.origin, .gui)
        XCTAssertEqual(run.presetId, "preset_six_default")
        // seats are keyed independently
        XCTAssertEqual(Set(run.workerAnswers.map(\.workerId)).count, 6)
    }

    func testPresetFixturesRoundTrip() throws {
        try assertRoundTrips(SynthesisInstructionPreset.self, .synthesisPresetDefault)
        try assertRoundTrips(TeamPreset.self, .teamPresetDefault)

        let preset = try Fixtures.teamPreset()
        XCTAssertEqual(preset.workerSpecs.count, 6)
        XCTAssertEqual(preset.synthesis.planWriterModelId, "model_opus")
        XCTAssertEqual(preset.synthesis.analysisDepth, .combined)
        XCTAssertEqual(preset.workerIds.count, 6)
    }

    func testTeamPresetBuiltInDefaultDefaultsJudgeToOpus() throws {
        let models = try Fixtures.models()
        let preset = TeamPreset.builtInDefault(models: models, analysisProfileId: "plan_analysis_v1", planProfileId: "plan_writer_v1")
        XCTAssertEqual(preset.synthesis.planWriterModelId, "model_opus")
        XCTAssertEqual(preset.workerSpecs.map(\.modelId), models.map(\.id))
        XCTAssertTrue(preset.builtIn)
    }

    func testSelfDoubleSeatExpansion() {
        let seats = [WorkerSpec(modelId: "model_opus", count: 3)].expandedWorkers()
        XCTAssertEqual(seats.map(\.id), ["model_opus#0", "model_opus#1", "model_opus#2"])
        XCTAssertEqual(Set(seats.map(\.id)).count, 3)
    }

    func testPartialRunIsUsableDespiteFailures() throws {
        let run = try Fixtures.run(.runPartial)
        XCTAssertEqual(run.status, .partial)
        XCTAssertNotNil(run.analysis)            // analysis succeeded
        XCTAssertNil(run.plan)             // plan failed
        XCTAssertEqual(run.latestStage(.plan)?.status, .failed)
        XCTAssertGreaterThanOrEqual(run.answeredWorkers.count, 3)
        XCTAssertEqual(run.failedWorkerAnswers.count, 2)
    }

    func testStagePayloadRoundTrips() throws {
        let analysis = StageOutput(id: "a", purpose: .analysis, status: .done, payload: .analysis(PlanAnalysis(blindSpots: ["x"])))
        let plan = StageOutput(id: "p", purpose: .plan, status: .done, payload: .plan(markdown: "# Plan"))
        for stage in [analysis, plan] {
            let data = try CoreJSON.encode(stage)
            let back = try CoreJSON.decode(StageOutput.self, from: data)
            XCTAssertEqual(stage, back)
        }
    }
}
