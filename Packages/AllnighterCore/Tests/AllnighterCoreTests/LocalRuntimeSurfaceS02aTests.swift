import XCTest
@testable import AllnighterCore

/// LR-S02a — minting enable (Claude Code body), `.discovered` persist, rule 7.
/// Fixture-only: never opens a socket, never writes the real catalog.
final class LocalRuntimeSurfaceS02aTests: XCTestCase {
    private var modelsRoot: URL!
    private var rosterURL: URL!
    private let now = Date(timeIntervalSince1970: 1_754_000_000)
    private let registry = DriverRegistry([
        DriverManifest(id: "claude_code", displayName: "Claude Code", kind: .headlessCLI),
        DriverManifest(id: "opencode", displayName: "OpenCode", kind: .headlessCLI),
    ])

    private let tagsPayload = """
    {"models":[
      {"name":"qwen3.8:27b-mlx","capabilities":["completion","vision","tools","thinking"]},
      {"name":"nomic-embed-text","capabilities":["embedding"]},
      {"name":"nomic-shaped-orphan"}
    ]}
    """

    override func setUp() {
        super.setUp()
        let base = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        modelsRoot = base.appendingPathComponent("models", isDirectory: true)
        rosterURL = base.appendingPathComponent("model_roster.json")
        CatalogRoots.overrideForTesting(
            teams: base.appendingPathComponent("teams", isDirectory: true),
            skills: base.appendingPathComponent("skills", isDirectory: true),
            models: modelsRoot)
        ModelCatalog.overrideRosterForTesting(fileURL: rosterURL)
    }

    override func tearDown() {
        CatalogRoots.resetTestingOverrides()
        ModelCatalog.resetTestingOverrides()
        try? FileManager.default.removeItem(at: modelsRoot.deletingLastPathComponent())
        super.tearDown()
    }

    // MARK: - Persist path

    func testSaveDiscoveredPersistsOriginAndDoesNotRebaseOntoCustom() throws {
        let seat = seatedClaude(tag: "qwen3.8:27b-mlx")
        try ModelCatalog.saveDiscovered(seat)
        let loaded = try XCTUnwrap(ModelCatalog.get(seat.id))
        XCTAssertEqual(loaded.origin, .discovered)
        XCTAssertEqual(loaded.driverId, "claude_code")
        XCTAssertEqual(loaded.modelLabel, "ollama/qwen3.8:27b-mlx")
        XCTAssertNotEqual(loaded.origin, .custom)

        XCTAssertThrowsError(try ModelCatalog.updateCustom(loaded)) { error in
            XCTAssertEqual(error as? ModelCatalogError, .builtInImmutable)
        }
        XCTAssertThrowsError(try ModelCatalog.saveDiscovered(customClaude(tag: "qwen3.8:27b-mlx"))) { error in
            XCTAssertEqual(error as? ModelCatalogError, .builtInImmutable)
        }
    }

    func testSaveCustomStillRejectsDiscovered() throws {
        let seat = seatedClaude(tag: "qwen3.8:27b-mlx")
        XCTAssertEqual(seat.origin, .discovered)
        // createCustom is the custom persist door; saveCustom is private.
        // updateCustom / createCustom must not accept a discovered rebase.
        XCTAssertThrowsError(try ModelCatalog.updateCustom(seat)) { error in
            XCTAssertEqual(error as? ModelCatalogError, .builtInImmutable)
        }
    }

    // MARK: - Enable grammar

    func testEnableCandidateMintsDiscoveredClaudeSeatAndPrintsNilG1() throws {
        let candidateID = OllamaLocalModelDiscoveryProvider.candidateID(tag: "qwen3.8:27b-mlx")
        let assessment = try LocalRuntimeSeatMint.enable(
            candidateID: candidateID,
            bodyDriverId: "claude_code",
            snapshot: snapshotFromPayload(),
            now: now
        )
        XCTAssertTrue(assessment.permitsEnable)
        XCTAssertNil(assessment.refusal)
        XCTAssertTrue(assessment.disclosures.contains { $0.contains("Allnighter has not tested this model") })
        XCTAssertTrue(assessment.disclosures.contains { $0.contains("adding it to Claude Code") })
        XCTAssertFalse(assessment.disclosures.contains { $0.lowercased().contains("g1 failed") })

        let seatedID = OllamaLocalModelDiscoveryProvider.seatedID(
            tag: "qwen3.8:27b-mlx", bodyDriverId: "claude_code")
        XCTAssertEqual(assessment.boundSeat?.id, seatedID)
        XCTAssertEqual(assessment.boundSeat?.driverId, "claude_code")
        XCTAssertEqual(assessment.boundSeat?.origin, .discovered)
        XCTAssertNotEqual(assessment.boundSeat?.driverId, "ollama_local")

        let persisted = try XCTUnwrap(ModelCatalog.get(seatedID))
        XCTAssertEqual(persisted.origin, .discovered)
        XCTAssertEqual(persisted.driverId, "claude_code")
        XCTAssertTrue(ModelCatalog.isEnabled(seatedID))
        XCTAssertNil(ModelCatalog.get(candidateID))
    }

    func testEnableWithoutBodyStaysSetEnabledOnExistingSeat() throws {
        let custom = try ModelCatalog.createCustom(
            driverId: "claude_code",
            displayName: "Qwen seated",
            modelLabel: "ollama/qwen3.8:27b-mlx",
            role: .answerer,
            registry: registry
        )
        var recognized = custom
        recognized.modelSmokeStatus = ModelSmokeStatus.recognized.rawValue
        try ModelCatalog.updateCustom(recognized)
        XCTAssertFalse(ModelCatalog.isEnabled(custom.id))
        try ModelCatalog.setEnabled(custom.id, true)
        XCTAssertTrue(ModelCatalog.isEnabled(custom.id))
        XCTAssertEqual(ModelCatalog.get(custom.id)?.origin, .custom)
    }

    func testBodyOnAlreadySeatedIdRefuses() throws {
        let custom = try ModelCatalog.createCustom(
            driverId: "claude_code",
            displayName: "Qwen seated",
            modelLabel: "ollama/qwen3.8:27b-mlx",
            role: .answerer,
            registry: registry
        )
        XCTAssertThrowsError(
            try LocalRuntimeSeatMint.enable(
                candidateID: custom.id,
                bodyDriverId: "claude_code",
                snapshot: snapshotFromPayload(),
                now: now
            )
        ) { error in
            guard case .invalid(let detail) = error as? ModelCatalogError else {
                return XCTFail("expected invalid, got \(error)")
            }
            XCTAssertTrue(detail.contains("already seated"), detail)
            XCTAssertTrue(detail.contains("omit --body"), detail)
        }
        XCTAssertNil(ModelCatalog.get(
            OllamaLocalModelDiscoveryProvider.seatedID(
                tag: "qwen3.8:27b-mlx", bodyDriverId: "claude_code")))
    }

    func testEnableUnknownCandidateRefuses() {
        XCTAssertThrowsError(
            try LocalRuntimeSeatMint.enable(
                candidateID: "discovered_ollama_missing_tag",
                bodyDriverId: "claude_code",
                snapshot: snapshotFromPayload(),
                now: now
            )
        ) { error in
            XCTAssertEqual(error as? ModelCatalogError, .notFound("discovered_ollama_missing_tag"))
        }
    }

    func testDeclaredNonCompletionIsNotACandidate() {
        let embedID = OllamaLocalModelDiscoveryProvider.candidateID(tag: "nomic-embed-text")
        XCTAssertThrowsError(
            try LocalRuntimeSeatMint.enable(
                candidateID: embedID,
                bodyDriverId: "claude_code",
                snapshot: snapshotFromPayload(),
                now: now
            )
        ) { error in
            XCTAssertEqual(error as? ModelCatalogError, .notFound(embedID))
        }
    }

    func testUnknownBodyRefusesAndDoesNotPersist() {
        let candidateID = OllamaLocalModelDiscoveryProvider.candidateID(tag: "nomic-shaped-orphan")
        XCTAssertThrowsError(
            try LocalRuntimeSeatMint.enable(
                candidateID: candidateID,
                bodyDriverId: "codex",
                snapshot: snapshotFromPayload(),
                now: now
            )
        ) { error in
            guard case .invalid(let detail) = error as? ModelCatalogError else {
                return XCTFail("expected invalid")
            }
            XCTAssertTrue(detail.contains("unknown agent body"), detail)
        }
        XCTAssertNil(ModelCatalog.get(
            OllamaLocalModelDiscoveryProvider.seatedID(
                tag: "nomic-shaped-orphan", bodyDriverId: "codex")))
    }

    func testCapabilityUnknownTagIsStillEnableable() throws {
        let candidateID = OllamaLocalModelDiscoveryProvider.candidateID(tag: "nomic-shaped-orphan")
        let assessment = try LocalRuntimeSeatMint.enable(
            candidateID: candidateID,
            bodyDriverId: "claude_code",
            snapshot: snapshotFromPayload(),
            now: now
        )
        XCTAssertTrue(assessment.permitsEnable)
        XCTAssertTrue(assessment.disclosures.contains { $0.contains("Allnighter has not tested this model") })
        let seatedID = OllamaLocalModelDiscoveryProvider.seatedID(
            tag: "nomic-shaped-orphan", bodyDriverId: "claude_code")
        XCTAssertEqual(ModelCatalog.get(seatedID)?.origin, .discovered)
        XCTAssertTrue(ModelCatalog.isEnabled(seatedID))
    }

    // MARK: - Rule 7 auto-sub

    func testLocalSeatIsNeverAutomaticSubstituteIncludingCustomOrigin() {
        let s00 = Model(
            id: "custom_claude_code_qwen38_27b_local",
            displayName: "Qwen3.8 27B local",
            modelLabel: "ollama/qwen3.8:27b-mlx",
            driverId: "claude_code",
            role: .answerer,
            enabled: true
        )
        let discovered = Model(
            id: "discovered_claude_code_qwen3_8_27b_mlx",
            displayName: "qwen3.8:27b-mlx",
            modelLabel: "ollama/qwen3.8:27b-mlx",
            driverId: "claude_code",
            role: .answerer,
            enabled: true
        )
        let opencodeLocal = Model(
            id: "custom_opencode_gpt_oss_local",
            displayName: "GPT-OSS local",
            modelLabel: "ollama/gpt-oss:20b",
            driverId: "opencode",
            role: .answerer,
            enabled: true
        )
        XCTAssertTrue(OllamaLocalDoctorReport.isOllamaBackedSeat(modelLabel: s00.modelLabel))
        XCTAssertTrue(ClaudeLocalIsolation.isLocalSeat(s00))
        XCTAssertTrue(OpenCodeLocalSeatReadiness.isLocalOpenCodeSeat(opencodeLocal))
        XCTAssertFalse(ModelCatalog.allowsAutomaticSubstitution(s00))
        XCTAssertFalse(ModelCatalog.allowsAutomaticSubstitution(discovered))
        XCTAssertFalse(ModelCatalog.allowsAutomaticSubstitution(opencodeLocal))
        XCTAssertFalse(ModelCatalog.neverAutomaticSubstituteIds.contains(s00.id))
        XCTAssertTrue(ModelCatalog.allowsAutomaticSubstitution("model_opus"))
        XCTAssertFalse(ModelCatalog.allowsAutomaticSubstitution("model_cursor_gpt_sol"))
    }

    func testPersistedDiscoveredSeatIsBlockedByIdLookup() throws {
        let seat = seatedClaude(tag: "qwen3.8:27b-mlx")
        try ModelCatalog.saveDiscovered(seat)
        XCTAssertFalse(ModelCatalog.allowsAutomaticSubstitution(seat.id))
    }

    func testUnpinnedTeamDoesNotAutoStaffLocalSeat() {
        let local = Model(
            id: "custom_claude_code_qwen38_27b_local",
            displayName: "Qwen3.8 27B local",
            modelLabel: "ollama/qwen3.8:27b-mlx",
            driverId: "claude_code",
            role: .answerer,
            enabled: true
        )
        let opus = Model(
            id: "model_opus",
            displayName: "Opus 5",
            modelLabel: "opus",
            driverId: "claude_code",
            role: .answerer,
            enabled: true
        )
        let pick = TeamResolver.selectModel(
            preferredModelId: nil,
            fallbackModelIds: [],
            allowedModelIds: [],
            requiredTags: [],
            fallback: .strongestReady,
            lane: .code,
            ready: [local, opus],
            capabilities: { id in
                id == local.id
                    ? ModelCapabilities(laneTags: [.code], capabilityTags: [.code], strengthRank: 40)
                    : ModelCatalog.capabilities(id)
            }
        )
        XCTAssertEqual(pick?.model.id, "model_opus")
        XCTAssertNotEqual(pick?.model.id, local.id)
    }

    func testExplicitPreferredModelIdStillSelectsLocalSeat() {
        let local = Model(
            id: "custom_claude_code_qwen38_27b_local",
            displayName: "Qwen3.8 27B local",
            modelLabel: "ollama/qwen3.8:27b-mlx",
            driverId: "claude_code",
            role: .answerer,
            enabled: true
        )
        let opus = Model(
            id: "model_opus",
            displayName: "Opus 5",
            modelLabel: "opus",
            driverId: "claude_code",
            role: .answerer,
            enabled: true
        )
        let pick = TeamResolver.selectModel(
            preferredModelId: local.id,
            fallbackModelIds: [],
            allowedModelIds: [],
            requiredTags: [.code],
            fallback: .laneCapable,
            lane: .code,
            ready: [local, opus],
            capabilities: { id in
                id == local.id
                    ? ModelCapabilities(laneTags: [.code], capabilityTags: [.code], strengthRank: 40)
                    : ModelCatalog.capabilities(id)
            }
        )
        XCTAssertEqual(pick?.model.id, local.id)
    }

    // MARK: - Helpers

    private func snapshotFromPayload() -> OllamaLocalRuntimeObserver.Snapshot {
        let tags = OllamaLocalRuntimeObserver.parseTags(Data(tagsPayload.utf8))!
        return OllamaLocalRuntimeObserver.snapshot(
            observedAt: now,
            ollamaVersion: "0.32.12",
            localTags: tags,
            residentModels: []
        )
    }

    private func seatedClaude(tag: String) -> ModelDefinition {
        var seat = OllamaLocalModelDiscoveryProvider.candidate(for: tag, discoveredAt: now)
        seat.driverId = "claude_code"
        seat.id = OllamaLocalModelDiscoveryProvider.seatedID(tag: tag, bodyDriverId: "claude_code")
        seat.origin = .discovered
        return seat
    }

    private func customClaude(tag: String) -> ModelDefinition {
        ModelDefinition(
            id: "custom_claude_code_qwen38_27b_local",
            displayName: "Qwen seated",
            modelLabel: "ollama/\(tag)",
            driverId: "claude_code",
            role: .answerer,
            origin: .custom,
            defaultEnabled: false,
            capabilities: ModelCapabilities()
        )
    }
}
