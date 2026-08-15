import XCTest
@testable import AllnighterCore

/// LR-S04b — run ready-set observes Ollama; local-pin substitution is loud.
/// Fixture-only: never opens a socket, never writes the real catalog.
final class LocalRuntimeSurfaceS04bTests: XCTestCase {
    private var modelsRoot: URL!
    private let now = Date(timeIntervalSince1970: 1_754_000_000)
    private let localId = "custom_claude_code_qwen38_27b_local"
    private let localLabel = "ollama/qwen3.8:27b-mlx"

    override func setUp() {
        super.setUp()
        let base = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        modelsRoot = base.appendingPathComponent("models", isDirectory: true)
        CatalogRoots.overrideForTesting(
            teams: base.appendingPathComponent("teams", isDirectory: true),
            skills: base.appendingPathComponent("skills", isDirectory: true),
            models: modelsRoot)
        ModelCatalog.overrideRosterForTesting(
            fileURL: base.appendingPathComponent("model_roster.json"))
    }

    override func tearDown() {
        CatalogRoots.resetTestingOverrides()
        ModelCatalog.resetTestingOverrides()
        try? FileManager.default.removeItem(at: modelsRoot.deletingLastPathComponent())
        super.tearDown()
    }

    // MARK: - S00 Q3

    /// Team with preferredModelId on a seated local id, Ollama observed
    /// reachable, resolves to the LOCAL seat and not to Opus.
    func testS00Q3PinnedLocalResolvesWhenOllamaObserved() throws {
        let local = seatedLocal()
        let opus = opusModel()
        let snapshot = reachableSnapshot(tags: ["qwen3.8:27b-mlx"])
        let ready = BenchReadiness.readyModels(
            models: [local, opus],
            probeRecords: [claudeInstalledRecord()],
            ollamaLocal: snapshot
        )
        XCTAssertTrue(ready.contains(where: { $0.id == localId }),
                      "seated+enabled local must enter the ready-set when Ollama is observed")
        XCTAssertTrue(ready.contains(where: { $0.id == "model_opus" }))

        let team = pinnedDocReview(preferred: localId)
        let resolved = TeamResolver.resolve(
            team: team,
            requestLane: .code,
            requestEffort: .med,
            readyModels: ready,
            capabilities: capabilities,
            catalogModels: [local, opus],
            ollamaLocal: snapshot
        )
        XCTAssertTrue(resolved.isRunnable)
        XCTAssertEqual(resolved.answerWorkers.first?.modelId, localId)
        XCTAssertNotEqual(resolved.answerWorkers.first?.modelId, "model_opus")
        XCTAssertFalse(resolved.warnings.contains { $0.contains("unavailable") })
        XCTAssertFalse(resolved.warnings.contains { $0.contains("LOCAL PIN SUBSTITUTED") })
        XCTAssertFalse(resolved.warnings.contains { $0.contains("Opus 5") && $0.contains("preferred") })
    }

    func testNilSnapshotKeepsLocalOutOfReadySet() {
        let local = seatedLocal()
        let opus = opusModel()
        let ready = BenchReadiness.readyModels(
            models: [local, opus],
            probeRecords: [claudeInstalledRecord()],
            ollamaLocal: nil
        )
        XCTAssertFalse(ready.contains(where: { $0.id == localId }))
        XCTAssertTrue(ready.contains(where: { $0.id == "model_opus" }))
    }

    // MARK: - Substitution honesty (local pin only)

    func testLocalPinSubstitutionNamesPinSensorAndPaidSubstitute() {
        let local = seatedLocal()
        let opus = opusModel()
        let snapshot = OllamaLocalRuntimeObserver.Snapshot(
            observedAt: now,
            ollamaVersion: nil,
            localTags: []
        )
        let ready = BenchReadiness.readyModels(
            models: [local, opus],
            probeRecords: [claudeInstalledRecord()],
            ollamaLocal: snapshot
        )
        XCTAssertFalse(ready.contains(where: { $0.id == localId }))

        let resolved = TeamResolver.resolve(
            team: pinnedDocReview(preferred: localId),
            requestLane: .code,
            requestEffort: .med,
            readyModels: ready,
            capabilities: capabilities,
            catalogModels: [local, opus],
            ollamaLocal: snapshot
        )
        XCTAssertEqual(resolved.answerWorkers.first?.modelId, "model_opus")
        let warning = resolved.warnings.first { $0.contains("LOCAL PIN SUBSTITUTED") }
        XCTAssertNotNil(warning)
        XCTAssertTrue(warning?.contains(localId) == true, "must name the pin")
        XCTAssertTrue(warning?.contains(localLabel) == true)
        XCTAssertTrue(warning?.contains("Ollama not reachable") == true, "must name the sensor")
        XCTAssertTrue(warning?.contains("Opus 5") == true, "must name the substitute")
        XCTAssertFalse(resolved.warnings.contains {
            $0.contains("preferred \(localId) unavailable; resolved to")
        })
    }

    func testUnobservedLocalPinNamesUnobservedSensor() {
        let local = seatedLocal()
        let opus = opusModel()
        let resolved = TeamResolver.resolve(
            team: pinnedDocReview(preferred: localId),
            requestLane: .code,
            requestEffort: .med,
            readyModels: [opus],
            capabilities: capabilities,
            catalogModels: [local, opus],
            ollamaLocal: nil
        )
        XCTAssertEqual(resolved.answerWorkers.first?.modelId, "model_opus")
        let warning = resolved.warnings.first { $0.contains("LOCAL PIN SUBSTITUTED") }
        XCTAssertTrue(warning?.contains("Ollama unobserved") == true)
        XCTAssertTrue(warning?.contains(localId) == true)
        XCTAssertTrue(warning?.contains("Opus 5") == true)
    }

    func testTagMissingLocalPinNamesTagSensor() {
        let local = seatedLocal()
        let opus = opusModel()
        let snapshot = reachableSnapshot(tags: ["gpt-oss:20b"])
        let resolved = TeamResolver.resolve(
            team: pinnedDocReview(preferred: localId),
            requestLane: .code,
            requestEffort: .med,
            readyModels: [opus],
            capabilities: capabilities,
            catalogModels: [local, opus],
            ollamaLocal: snapshot
        )
        let warning = resolved.warnings.first { $0.contains("LOCAL PIN SUBSTITUTED") }
        XCTAssertTrue(warning?.contains("tag not present locally: qwen3.8:27b-mlx") == true)
    }

    func testPaidPreferredUnavailableKeepsBuriedWarning() {
        let chatgpt54 = Model(
            id: "model_gpt_54", displayName: "GPT-5.4",
            modelLabel: "gpt-5.4", driverId: "codex", role: .answerer
        )
        let opus = opusModel()
        let team = TeamPreset(
            id: "code_test", displayName: "Test", lane: .code, outputKind: .plan,
            defaultEffort: .med,
            agentSpecs: [
                TeamAgentSpec(
                    id: "r1", skillId: "regression_guard",
                    preferredModelId: "model_gpt_sol", fallbackPolicy: .anyReady)
            ],
            lead: TeamLeadSpec(
                skillId: "plan_writer_build",
                requiredCapabilityTags: [.planner],
                fallbackPolicy: .strongestReady)
        )
        let resolved = TeamResolver.resolve(
            team: team, requestLane: .code, requestEffort: .low,
            readyModels: [opus, chatgpt54]
        )
        XCTAssertEqual(resolved.answerWorkers.first?.modelId, "model_gpt_54")
        XCTAssertTrue(resolved.warnings.contains { $0.contains("preferred model_gpt_sol unavailable") })
        XCTAssertFalse(resolved.warnings.contains { $0.contains("LOCAL PIN SUBSTITUTED") })
    }

    // MARK: - Helpers

    private func seatedLocal() -> Model {
        Model(
            id: localId,
            displayName: "Qwen3.8 27B local",
            modelLabel: localLabel,
            driverId: "claude_code",
            role: .answerer,
            enabled: true
        )
    }

    private func opusModel() -> Model {
        Model(
            id: "model_opus",
            displayName: "Opus 5",
            modelLabel: "opus",
            driverId: "claude_code",
            role: .both,
            enabled: true
        )
    }

    private func pinnedDocReview(preferred: String) -> TeamPreset {
        var team = BuiltInTeams.team("code_doc_review")
            ?? TeamPreset(
                id: "code_doc_review", displayName: "Doc Review",
                lane: .code, outputKind: .plan, defaultEffort: .med,
                agentSpecs: [
                    TeamAgentSpec(
                        id: "doc", skillId: "doc_reviewer",
                        preferredModelId: preferred,
                        requiredCapabilityTags: [.code],
                        fallbackPolicy: .laneCapable)
                ],
                lead: TeamLeadSpec(
                    skillId: "doc_reviewer",
                    preferredModelId: preferred,
                    requiredCapabilityTags: [.code],
                    fallbackPolicy: .strongestReady)
            )
        if !team.agentSpecs.isEmpty {
            team.agentSpecs[0].preferredModelId = preferred
        }
        team.lead.preferredModelId = preferred
        return team
    }

    private func capabilities(_ id: String) -> ModelCapabilities {
        if id == localId {
            return ModelCapabilities(
                laneTags: [.code],
                capabilityTags: [.code, .planner, .review],
                strengthRank: 40
            )
        }
        return ModelCatalog.capabilities(id)
    }

    private func claudeInstalledRecord() -> ToolProbeRecord {
        ToolProbeRecord(
            driverId: "claude_code",
            status: .ready(version: "1.0.0"),
            invocation: .direct(path: "/usr/local/bin/claude"),
            version: "1.0.0",
            lastProbeAt: now
        )
    }

    private func reachableSnapshot(tags: [String]) -> OllamaLocalRuntimeObserver.Snapshot {
        OllamaLocalRuntimeObserver.Snapshot(
            observedAt: now,
            ollamaVersion: "0.32.12",
            localTags: tags.map { .init(name: $0) }
        )
    }
}
