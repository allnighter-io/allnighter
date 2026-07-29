import XCTest
@testable import AllnighterCore

/// Auto-team assembly truth layer (docs/phases/setup/01 §8): only `ready` sources
/// qualify, plan writer is truthful. Pure; no detection here.
final class TeamAssemblerTests: XCTestCase {
    private let t = Date(timeIntervalSince1970: 0)
    private let models = [
        Model(id: "model_opus", displayName: "Opus", modelLabel: "opus", driverId: "claude_code", role: .both),
        Model(id: "model_sonnet", displayName: "Sonnet", modelLabel: "sonnet", driverId: "claude_code", role: .answerer),
        Model(id: "model_codex", displayName: "Codex", modelLabel: "gpt", driverId: "codex", role: .answerer),
        Model(id: "model_grok", displayName: "Grok", modelLabel: "grok", driverId: "grok", role: .answerer),
    ]

    func testAssemblesOnlyReadyModelsWithEligiblePlanWriter() {
        let a = TeamAssembler.assemble(models: models, readyDriverIds: ["claude_code", "codex"], now: t)
        XCTAssertEqual(Set(a.benchModelIds), ["model_opus", "model_sonnet", "model_codex"])  // grok excluded (not ready)
        XCTAssertEqual(a.workerSpecs.map(\.modelId).sorted(), ["model_codex", "model_opus", "model_sonnet"])
        XCTAssertEqual(a.planWriterModelId, "model_opus")   // the ready role-.both model
        XCTAssertEqual(a.assembledAt, t)
        XCTAssertFalse(a.isEmpty)
    }

    func testPlanWriterPrefersClaudeOpusOverAgyEvenWhenAgyListedFirst() {
        // Alphabetically model_agy_opus < model_opus; strength rank must still win.
        let mixed = [
            Model(id: "model_agy_opus", displayName: "Opus 4.6",
                  modelLabel: "Claude Opus 4.6 (Thinking)", driverId: "antigravity", role: .both),
            Model(id: "model_opus", displayName: "Opus 5", modelLabel: "opus",
                  driverId: "claude_code", role: .both),
        ]
        let a = TeamAssembler.assemble(
            models: mixed, readyDriverIds: ["antigravity", "claude_code"], now: t)
        XCTAssertEqual(a.planWriterModelId, "model_opus")
    }

    func testPlanWriterFallsBackToAgyWhenClaudeUnavailable() {
        let onlyAgy = [
            Model(id: "model_agy_opus", displayName: "Opus 4.6",
                  modelLabel: "Claude Opus 4.6 (Thinking)", driverId: "antigravity", role: .both),
            Model(id: "model_sonnet", displayName: "Sonnet", modelLabel: "sonnet",
                  driverId: "claude_code", role: .answerer),
        ]
        let a = TeamAssembler.assemble(models: onlyAgy, readyDriverIds: ["antigravity"], now: t)
        XCTAssertEqual(a.planWriterModelId, "model_agy_opus")
    }

    func testFallsBackToFirstReadyWhenNoEligiblePlanWriter() {
        let a = TeamAssembler.assemble(models: models, readyDriverIds: ["codex"], now: t)
        XCTAssertEqual(a.benchModelIds, ["model_codex"])
        XCTAssertEqual(a.planWriterModelId, "model_codex")  // no eligible → first ready, truthfully
    }

    func testEmptyWhenNothingReady() {
        let a = TeamAssembler.assemble(models: models, readyDriverIds: [], now: t)
        XCTAssertTrue(a.isEmpty)
        XCTAssertTrue(a.workerSpecs.isEmpty)
        XCTAssertNil(a.planWriterModelId)
    }

    func testReadyDriverIdsCountsOnlyReadyStatus() {
        let records = [
            ToolProbeRecord(driverId: "claude_code", status: .ready(version: "1"), lastProbeAt: t),
            ToolProbeRecord(driverId: "codex", status: .installedNotProbed(version: "1"), lastProbeAt: t),
            ToolProbeRecord(driverId: "grok", status: .notInstalled, lastProbeAt: t),
        ]
        XCTAssertEqual(TeamAssembler.readyDriverIds(from: records), ["claude_code"])
    }

    func testAssembledRoundTrips() throws {
        let a = TeamAssembler.assemble(models: models, readyDriverIds: ["claude_code"], now: t)
        let back = try CoreJSON.decode(TeamAssembler.Assembled.self, from: CoreJSON.encode(a))
        XCTAssertEqual(back, a)
    }
}
