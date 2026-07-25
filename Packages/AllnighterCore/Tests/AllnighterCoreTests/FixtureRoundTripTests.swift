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
        try assertRoundTrips(DriverManifest.self, .manifestCursor)
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
        XCTAssertEqual(Set(run.workerAnswers.map(\.memberId)).count, 6)
    }

    func testPresetFixturesRoundTrip() throws {
        try assertRoundTrips(SynthesisInstructionPreset.self, .synthesisPresetDefault)
        try assertRoundTrips(PanelPreset.self, .teamPresetDefault)

        let preset = try Fixtures.panelPreset()
        XCTAssertEqual(preset.workerSpecs.count, 6)
        XCTAssertEqual(preset.synthesis.planWriterModelId, "model_opus")
        XCTAssertEqual(preset.synthesis.analysisDepth, .combined)
        XCTAssertEqual(preset.workerIds.count, 6)
    }

    func testPanelPresetBuiltInDefaultDefaultsPlanWriterToOpus() throws {
        let models = try Fixtures.models()
        let preset = PanelPreset.builtInDefault(models: models, analysisProfileId: "plan_analysis_v1", planProfileId: "plan_writer_v1")
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

    /// Keystone: the public `TeamRunJSON` contract decodes from the bundled
    /// fixture, round-trips, and honors the contract invariants
    /// (docs/phases/CLI_Implementation_Contract.md §TeamRunJSON).
    func testTeamRunJSONContractRoundTrips() throws {
        try assertRoundTrips(TeamRunJSON.self, .teamRunJSON)

        let trj = try Fixtures.decode(TeamRunJSON.self, .teamRunJSON)
        XCTAssertEqual(trj.schemaVersion, 2)
        // Contract bumped 3.0.0 → 3.4.0 in 12fcd8a2 (fix(team): make persisted
        // status explicit); the SSOT (ContractRegistry.contractVersion) and the
        // bundled team_run.json fixture both carry 3.4.0 — only this golden lagged.
        XCTAssertEqual(trj.contractVersion, "4.0.4")
        XCTAssertEqual(trj.teamRun.status, .done)   // public word is "done", not internal "complete"
        XCTAssertEqual(trj.teamRun.origin, .cli)
        XCTAssertEqual(trj.workers.count, 1)
        XCTAssertEqual(trj.workerAnswers.count, 1)
        XCTAssertNil(trj.workerAnswers.first?.markdown)  // Law 2: markdown moved to answer
        let answer = try XCTUnwrap(trj.answer)
        XCTAssertEqual(answer.markdown, "success")
        XCTAssertEqual(answer.source.kind, .worker)
        XCTAssertLessThanOrEqual(answer.markdown?.utf8.count ?? 0, 256)

        // No catalog models on the run envelope (SH-S02).
        let encoded = try CoreJSON.encode(trj)
        let root = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        XCTAssertNil(root["models"])
        XCTAssertNotNil(root["answer"])

        // Required top-level contract objects are present.
        XCTAssertEqual(trj.usage.cliCalls, 1)
        XCTAssertFalse(trj.audit.traceId.isEmpty)
        XCTAssertFalse(trj.audit.runJournalPath.isEmpty)

        // nextActions.kind is a closed enum (registry-owned at step 2).
        XCTAssertEqual(trj.nextActions.map(\.kind), [.showRun, .export])

        // SH-S08 — exact observed timing on the one-worker fixture.
        let answerRow = try XCTUnwrap(trj.workerAnswers.first)
        XCTAssertEqual(answerRow.queueMs, 1000)
        XCTAssertEqual(answerRow.ttftMs, 500)
        XCTAssertEqual(answerRow.durationMs, 4000)
        XCTAssertEqual(trj.outcome?.timing?.wallMs, 5000)
        XCTAssertEqual(
            trj.outcome?.headline,
            "worker model_sonnet · lane code · mutating · queue 1000ms · ttft 500ms · duration 4000ms · wall 5000ms"
        )
    }

    /// SH-S08: generated teaching surfaces must not use estimate vocabulary.
    func testObservedTimingDocsOmitEstimateVocabulary() {
        let md = ContractDocs.markdown().lowercased()
        XCTAssertFalse(md.contains("estimate"), "ContractDocs leaked estimate vocabulary")
        XCTAssertTrue(md.contains("queuems"), "docs must name queueMs")
        XCTAssertTrue(md.contains("ttftms"), "docs must name ttftMs")
        XCTAssertTrue(md.contains("wallms") || md.contains("wall ms"), "docs must name wallMs")
        XCTAssertFalse(md.contains("alln overhead"))
    }

    /// SH-S02 envelope budget: one-worker terminal overhead stays within the
    /// measured budget recorded in archived Alln_Sharpening.md.
    func testOneWorkerEnvelopeOverheadWithinBudget() throws {
        let trj = try Fixtures.decode(TeamRunJSON.self, .teamRunJSON)
        let answerMarkdown = try XCTUnwrap(trj.answer?.markdown)
        let encoded = try CoreJSON.encode(trj)
        let overhead = encoded.count - answerMarkdown.utf8.count
        // Measured 2026-07-20: CoreJSON pretty+sortedKeys overhead = 2293 bytes
        // against this fixture. Budget = 4096 (measured + headroom).
        let budget = 4096
        XCTAssertLessThanOrEqual(
            overhead, budget,
            "one-worker envelope overhead \(overhead) exceeds budget \(budget)"
        )
        XCTAssertFalse(String(decoding: encoded, as: UTF8.self).contains("\"models\""))
    }

    /// The shared error envelope decodes from its fixture and round-trips
    /// (docs/phases/CLI_Implementation_Contract.md §Error Envelope).
    func testErrorEnvelopeRoundTrips() throws {
        try assertRoundTrips(ErrorEnvelope.self, .errorEnvelope)
        let err = try Fixtures.decode(ErrorEnvelope.self, .errorEnvelope)
        XCTAssertEqual(err.code, "SOURCE_AUTH_EXPIRED")
        XCTAssertTrue(err.requiresManual)
        XCTAssertFalse(err.retryable)
        XCTAssertEqual(err.fixCommand, "claude auth login")
    }

    /// `DoctorResult` decodes from its fixture, round-trips, and reuses the shared
    /// `ErrorEnvelope` for fixes (docs/phases/CLI_Implementation_Contract.md
    /// §Doctor Contract).
    func testDoctorResultRoundTrips() throws {
        try assertRoundTrips(DoctorResult.self, .doctorResult)
        let doc = try Fixtures.decode(DoctorResult.self, .doctorResult)
        XCTAssertEqual(doc.status, .degraded)
        XCTAssertFalse(doc.coordinator.available)
        XCTAssertEqual(doc.coordinator.state, .foregroundOnly)
        XCTAssertTrue(doc.checks.contains { $0.name == "source.claude_code.auth" && $0.status == .degraded })
        XCTAssertEqual(doc.fixes.first?.code, "SOURCE_AUTH_EXPIRED")
        XCTAssertEqual(doc.models.first?.sourceName, "Claude Code")
    }

    func testPendingItemJSONRoundTrips() throws {
        try assertRoundTrips(PendingItemJSON.self, .pendingItemJSON)
        try assertRoundTrips(PendingItemJSON.self, .pendingItemCoolingJSON)
    }
}
