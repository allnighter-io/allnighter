import XCTest
@testable import AllnighterCore

final class ModelCatalogTests: XCTestCase {
    private var modelsRoot: URL!
    private var rosterURL: URL!

    private func testRegistry() -> DriverRegistry {
        let ids = Set(ModelCatalog.builtIns.map(\.driverId))
        return DriverRegistry(ids.sorted().map { DriverManifest(id: $0, displayName: $0, kind: .headlessCLI) })
    }

    override func setUp() {
        super.setUp()
        let base = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        modelsRoot = base.appendingPathComponent("models", isDirectory: true)
        rosterURL = base.appendingPathComponent("model_roster.json")
        CatalogRoots.overrideForTesting(
            teams: base.appendingPathComponent("teams", isDirectory: true),
            skills: base.appendingPathComponent("skills", isDirectory: true),
            models: modelsRoot)
        ModelCatalog.overrideRosterForTesting(fileURL: rosterURL)
    }

    override func tearDown() {
        OpenCodeModelGate.overrideGoConnectedForTesting(nil)
        CatalogRoots.resetTestingOverrides()
        ModelCatalog.resetTestingOverrides()
        try? FileManager.default.removeItem(at: modelsRoot.deletingLastPathComponent())
        super.tearDown()
    }

    func testBuiltInsDefaultEnabledOnFreshInstall() {
        OpenCodeModelGate.overrideGoConnectedForTesting(false)
        let registry = testRegistry()
        let models = ModelCatalog.resolvedModels(registry: registry)
        // Fable, Opus, Sonnet 5, GPT-5.6 Sol, GPT-5.6 Terra,
        // Grok 4.5, Kimi K3, Kimi K2.7 Code, Cursor Auto, Composer 2.5, Cursor Grok 4.5, Gemini Flash.
        // Cursor Sol + Antigravity Opus stay default-off.
        // Terra medium seat was added default-on in eff7d44e (models: add Codex Terra
        // medium seat), taking the fresh-install count 10 → 11.
        // Kimi K2.7 Code added default-on 2026-07-27 (11 → 12).
        // Cursor Fable/Opus/Sonnet seats added default-on 2026-07-28 (12 → 15).
        // Antigravity Opus/Sonnet 4.6 re-added default-on for Claude quota harvest (15 → 17).
        // GPT-5.6 Luna added default-on on Economy bench (17 → 18).
        // Muse Spark 1.2 seats removed; Muse Spark 1.3 Contributor via OpenCode (24 while Go locked).
        XCTAssertEqual(models.filter(\.enabled).count, 24)
        XCTAssertTrue(models.first { $0.id == "model_opencode_big_pickle" }?.enabled ?? false)
        XCTAssertTrue(models.first { $0.id == "model_opencode_muse_spark_13_contributor" }?.enabled ?? false,
                       "OpenRouter Muse is not Go inventory — it stays on-bench without a Go key")
        XCTAssertFalse(models.first { $0.id == "model_opencode_glm_5_2" }?.enabled ?? true,
                       "OpenCode Go inventory stays off until Go auth connects")
        XCTAssertEqual(models.first { $0.id == "model_agy_opus" }?.displayName, "Opus 4.6 (Antigravity)")
        XCTAssertEqual(models.first { $0.id == "model_agy_sonnet" }?.displayName, "Sonnet 4.6 (Antigravity)")
        XCTAssertEqual(models.first { $0.id == "model_agy_opus" }?.modelLabel, "Claude Opus 4.6 (Thinking)")
        XCTAssertEqual(models.first { $0.id == "model_agy_sonnet" }?.modelLabel, "Claude Sonnet 4.6 (Thinking)")
        XCTAssertTrue(models.first { $0.id == "model_fable" }?.enabled ?? false)
        XCTAssertFalse(models.first { $0.id == "model_cursor_gpt_sol" }?.enabled ?? true,
                       "Cursor Sol is never on-Bench by default")
        XCTAssertTrue(models.first { $0.id == "model_gpt_sol" }?.enabled ?? false)
        XCTAssertEqual(models.first { $0.id == "model_sonnet" }?.modelLabel, "sonnet")
        XCTAssertEqual(models.first { $0.id == "model_opus" }?.displayName, "Opus 5")
        XCTAssertEqual(models.first { $0.id == "model_fable" }?.displayName, "Fable 5")
        XCTAssertEqual(models.first { $0.id == "model_cursor_fable" }?.displayName, "Fable 5 (Cursor)")
        XCTAssertEqual(models.first { $0.id == "model_cursor_opus" }?.displayName, "Opus 5 (Cursor)")
        XCTAssertEqual(models.first { $0.id == "model_opus" }?.modelLabel, "opus")
        XCTAssertEqual(models.first { $0.id == "model_gpt_sol" }?.displayName, "GPT-5.6 Sol")
        XCTAssertEqual(models.first { $0.id == "model_gpt_luna" }?.displayName, "GPT-5.6 Luna")
        XCTAssertEqual(models.first { $0.id == "model_cursor_gpt_sol" }?.displayName, "GPT-5.6 Sol (Cursor)")
    }

    func testDisableSonnetPersistsAcrossReload() throws {
        let registry = testRegistry()
        try ModelCatalog.setEnabled("model_sonnet", false)
        let models = ModelCatalog.resolvedModels(registry: registry)
        XCTAssertFalse(models.first { $0.id == "model_sonnet" }!.enabled)
        let reloaded = ModelCatalog.resolvedModels(registry: registry)
        XCTAssertFalse(reloaded.first { $0.id == "model_sonnet" }!.enabled)
    }

    func testReenableRestoresBench() throws {
        let registry = testRegistry()
        try ModelCatalog.setEnabled("model_sonnet", false)
        try ModelCatalog.setEnabled("model_sonnet", true)
        XCTAssertTrue(ModelCatalog.resolvedModels(registry: registry).first { $0.id == "model_sonnet" }!.enabled)
    }

    func testStaleRosterIDIsDiagnosed() throws {
        let registry = testRegistry()
        try ModelRosterPersistence(fileURL: rosterURL).save(
            ModelRosterState(enabledModelIds: ["model_opus", "ghost_model"]))
        let diags = ModelCatalog.diagnostics(registry: registry)
        XCTAssertTrue(diags.contains { $0.code == "MODEL_ROSTER_STALE_ID" && $0.modelId == "ghost_model" })
    }

    func testLegacyRosterBackfillsKimiK27WithoutReenablingUserDisabledSeats() throws {
        let registry = testRegistry()
        try ModelRosterPersistence(fileURL: rosterURL).save(
            ModelRosterState(enabledModelIds: ["model_opus"]))
        _ = ModelCatalog.resolvedModels(registry: registry)
        let roster = try XCTUnwrap(ModelRosterPersistence(fileURL: rosterURL).load())
        XCTAssertTrue(roster.enabledModelIds.contains("model_kimi_k27"))
        XCTAssertFalse(roster.enabledModelIds.contains("model_cursor_auto"),
                       "default-on seats the user left off must not be backfilled")
        XCTAssertNotNil(roster.catalogSeenModelIds)
    }

    func testProbeLabelWhenAllClaudeModelsDisabled() throws {
        try ModelCatalog.setEnabled("model_fable", false)
        try ModelCatalog.setEnabled("model_opus", false)
        try ModelCatalog.setEnabled("model_sonnet", false)
        // Falls back to the Claude-side flagship built-in label for smoke probes.
        XCTAssertEqual(ModelCatalog.probeModelLabel(driverId: "claude_code"), "fable")
    }

    func testOpenCodeProbeUsesZenBigPickleNotGoCapacityLabel() {
        OpenCodeModelGate.overrideGoConnectedForTesting(false)
        defer { OpenCodeModelGate.overrideGoConnectedForTesting(nil) }
        XCTAssertEqual(ModelCatalog.probeModelLabel(driverId: "opencode"), "opencode/big-pickle")
        XCTAssertFalse(
            ModelCatalog.probeModelLabel(driverId: "opencode")?.hasPrefix("opencode-go/") == true
        )
    }

    func testOpenCodeProbeUsesGoFlashWhenGoConnected() {
        OpenCodeModelGate.overrideGoConnectedForTesting(true)
        defer { OpenCodeModelGate.overrideGoConnectedForTesting(nil) }
        XCTAssertEqual(
            ModelCatalog.probeModelLabel(driverId: "opencode"),
            "opencode-go/deepseek-v4-flash"
        )
        XCTAssertNotEqual(
            ModelCatalog.probeModelLabel(driverId: "opencode"),
            "opencode/big-pickle",
            "Go-only hosts must not smoke Zen big-pickle"
        )
    }

    func testAntigravityProbeUsesGeminiFlashNotOpus() {
        XCTAssertEqual(
            ModelCatalog.probeModelLabel(driverId: "antigravity"),
            "Gemini 3.8 Flash (Medium)"
        )
        XCTAssertNotEqual(
            ModelCatalog.probeModelLabel(driverId: "antigravity"),
            "Claude Opus 4.6 (Thinking)",
            "Opus is role=both so selectProbeLabel would pick it; smoke must stay on Gemini"
        )
    }

    func testOpenCodeGlm53ShipsWithGoLabel() throws {
        let glm = try XCTUnwrap(ModelCatalog.get("model_opencode_glm_5_3"))
        XCTAssertEqual(glm.displayName, "GLM-5.3")
        XCTAssertEqual(glm.modelLabel, "opencode-go/glm-5.3")
        XCTAssertTrue(OpenCodeModelGate.isGoCatalogSeat(glm))
    }

    func testOpenCodeGlm53FlashShipsWithGoLabel() throws {
        let glm = try XCTUnwrap(ModelCatalog.get("model_opencode_glm_5_3_flash"))
        XCTAssertEqual(glm.displayName, "GLM-5.3-Flash")
        XCTAssertEqual(glm.modelLabel, "opencode-go/glm-5.3-flash")
        XCTAssertTrue(OpenCodeModelGate.isGoCatalogSeat(glm))
    }

    func testOpenCodeGoInventoryHiddenAndRefusesEnable() throws {
        OpenCodeModelGate.overrideGoConnectedForTesting(false)
        defer { OpenCodeModelGate.overrideGoConnectedForTesting(nil) }
        let glm = try XCTUnwrap(ModelCatalog.get("model_opencode_glm_5_2"))
        XCTAssertTrue(OpenCodeModelGate.isGoCatalogSeat(glm))
        XCTAssertFalse(OpenCodeModelGate.visibleInCLIRoster(glm))
        let zen = try XCTUnwrap(ModelCatalog.get("model_opencode_big_pickle"))
        XCTAssertTrue(OpenCodeModelGate.visibleInCLIRoster(zen))
        XCTAssertFalse(ModelCatalog.isEnabled("model_opencode_glm_5_2"))
        XCTAssertThrowsError(try ModelCatalog.setEnabled("model_opencode_glm_5_2", true))
    }

    func testOpenCodeGoInventoryUnlocksWhenAuthConnected() throws {
        OpenCodeModelGate.overrideGoConnectedForTesting(true)
        defer { OpenCodeModelGate.overrideGoConnectedForTesting(nil) }
        let glm = try XCTUnwrap(ModelCatalog.get("model_opencode_glm_5_2"))
        XCTAssertTrue(OpenCodeModelGate.visibleInCLIRoster(glm))
        try ModelCatalog.setEnabled("model_opencode_glm_5_2", true)
        XCTAssertTrue(ModelCatalog.isEnabled("model_opencode_glm_5_2"))
        try ModelCatalog.setEnabled("model_opencode_glm_5_2", false)
    }

    func testOpenCodeGoConnectSeedsDefaultOnSeats() throws {
        OpenCodeModelGate.overrideGoConnectedForTesting(false)
        let rosterURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("opencode-go-seed-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: rosterURL) }
        ModelCatalog.overrideRosterForTesting(fileURL: rosterURL)
        defer { ModelCatalog.resetTestingOverrides() }
        try ModelRosterPersistence(fileURL: rosterURL).save(
            ModelRosterState(
                enabledModelIds: ["model_opus", "model_opencode_big_pickle"],
                catalogSeenModelIds: ModelCatalog.builtIns.map(\.id),
                openCodeGoDefaultsSeeded: false))
        _ = ModelCatalog.resolvedModels(registry: testRegistry())
        XCTAssertFalse(ModelCatalog.isEnabled("model_opencode_glm_5_2"))

        OpenCodeModelGate.overrideGoConnectedForTesting(true)
        let models = ModelCatalog.resolvedModels(registry: testRegistry())
        for id in [
            "model_opencode_glm_5_2",
            "model_opencode_glm_5_3",
            "model_opencode_glm_5_3_flash",
            "model_opencode_deepseek_v4_pro",
            "model_opencode_deepseek_v4_flash",
        ] {
            XCTAssertTrue(models.contains { $0.id == id && $0.enabled }, "\(id) should seed on")
        }
        let roster = try XCTUnwrap(ModelRosterPersistence(fileURL: rosterURL).load())
        XCTAssertEqual(roster.openCodeGoDefaultsSeeded, true)

        // User off sticks across reconcile.
        try ModelCatalog.setEnabled("model_opencode_glm_5_2", false)
        _ = ModelCatalog.resolvedModels(registry: testRegistry())
        XCTAssertFalse(ModelCatalog.isEnabled("model_opencode_glm_5_2"))
    }

    func testOpenCodeGoConnectedReadsAuthProviderKeyOnly() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("opencode-auth-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let auth = dir.appendingPathComponent("auth.json")
        try Data(#"{"opencode-go":{"type":"api","key":"secret-should-not-matter"}}"#.utf8)
            .write(to: auth)
        XCTAssertTrue(OpenCodeModelGate.isGoConnected(authFileURL: auth))
        try Data(#"{"opencode":{"type":"api","key":"zen-only"}}"#.utf8).write(to: auth)
        XCTAssertFalse(OpenCodeModelGate.isGoConnected(authFileURL: auth))
    }

    func testReconcileScrubsOpenCodeGoFromExistingRoster() throws {
        OpenCodeModelGate.overrideGoConnectedForTesting(false)
        defer { OpenCodeModelGate.overrideGoConnectedForTesting(nil) }
        let rosterURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("opencode-go-scrub-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: rosterURL) }
        ModelCatalog.overrideRosterForTesting(fileURL: rosterURL)
        defer { ModelCatalog.resetTestingOverrides() }
        try ModelRosterPersistence(fileURL: rosterURL).save(
            ModelRosterState(
                enabledModelIds: ["model_opus", "model_opencode_glm_5_2", "model_opencode_big_pickle"],
                catalogSeenModelIds: ModelCatalog.builtIns.map(\.id)))
        let registry = testRegistry()
        let models = ModelCatalog.resolvedModels(registry: registry)
        XCTAssertFalse(models.contains { $0.id == "model_opencode_glm_5_2" && $0.enabled })
        let roster = try XCTUnwrap(ModelRosterPersistence(fileURL: rosterURL).load())
        XCTAssertFalse(roster.enabledModelIds.contains("model_opencode_glm_5_2"))
        XCTAssertTrue(roster.enabledModelIds.contains("model_opencode_big_pickle"))
    }

    func testOpenCodeMuseSpark13ContributorShipsWithOpenRouterLabel() throws {
        OpenCodeModelGate.overrideGoConnectedForTesting(false)
        defer { OpenCodeModelGate.overrideGoConnectedForTesting(nil) }
        let muse = try XCTUnwrap(ModelCatalog.get("model_opencode_muse_spark_13_contributor"))
        XCTAssertEqual(muse.displayName, "Muse Spark 1.3 Contributor (OpenCode)")
        XCTAssertEqual(muse.modelLabel, "openrouter/meta/muse-spark-1.3-contributor")
        XCTAssertEqual(muse.driverId, "opencode")
        XCTAssertFalse(OpenCodeModelGate.isGoCatalogSeat(muse))
        XCTAssertTrue(OpenCodeModelGate.visibleInCLIRoster(muse))
        XCTAssertTrue(muse.defaultEnabled)
        XCTAssertEqual(ModelCatalog.modelFamily(muse.id), "muse")
        XCTAssertTrue(ModelCatalog.isEnabled("model_opencode_muse_spark_13_contributor"))
    }

    func testCustomModelCRUD() throws {
        let registry = testRegistry()
        let created = try ModelCatalog.createCustom(
            driverId: "claude_code", displayName: "Fabel", modelLabel: "fabel",
            role: .answerer, enabled: true, registry: registry)
        XCTAssertTrue(created.id.hasPrefix("custom_claude_code_"))
        XCTAssertEqual(created.modelSmokeStatus, "unverified")
        // enabled=true is ignored until smoke-verified — stays off the Bench.
        XCTAssertFalse(ModelCatalog.resolvedModels(registry: registry).contains { $0.id == created.id && $0.enabled })

        var updated = created
        updated.displayName = "Fabel 2"
        updated.modelLabel = "fabel-2"
        try ModelCatalog.updateCustom(updated)
        XCTAssertEqual(ModelCatalog.get(created.id)?.displayName, "Fabel 2")

        try ModelCatalog.deleteCustom(created.id)
        XCTAssertNil(ModelCatalog.get(created.id))
    }

    func testAddDisabledStaysOffBench() throws {
        let registry = testRegistry()
        let created = try ModelCatalog.createCustom(
            driverId: "claude_code", displayName: "Fabel", modelLabel: "fabel",
            role: .answerer, enabled: false, registry: registry)
        let model = ModelCatalog.resolvedModels(registry: registry).first { $0.id == created.id }
        XCTAssertFalse(model?.enabled ?? true)
    }

    func testCustomModelStaysOffBenchUntilSmokeRecognized() throws {
        let registry = testRegistry()
        let created = try ModelCatalog.createCustom(
            driverId: "claude_code", displayName: "Fabel", modelLabel: "fabel",
            role: .answerer, enabled: true, registry: registry)
        XCTAssertEqual(created.modelSmokeStatus, "unverified")
        XCTAssertFalse(ModelCatalog.isEnabled(created.id))

        XCTAssertThrowsError(try ModelCatalog.setEnabled(created.id, true)) { error in
            guard case .invalid(let detail) = error as? ModelCatalogError else {
                return XCTFail("expected invalid")
            }
            XCTAssertTrue(detail.contains("alln models verify \(created.id)"))
        }

        var recognized = created
        recognized.modelSmokeStatus = ModelSmokeStatus.recognized.rawValue
        try ModelCatalog.updateCustom(recognized)
        try ModelCatalog.setEnabled(created.id, true)
        XCTAssertTrue(ModelCatalog.isEnabled(created.id))
    }

    func testVerifyModelSmokePersistsRecognized() async throws {
        let registry = DriverRegistry([
            DriverManifest(
                id: "claude_code",
                displayName: "Claude",
                kind: .headlessCLI,
                invoke: .init(
                    command: "claude",
                    args: ["-p", "{{prompt}}", "--model", "{{model}}"]
                )
            )
        ])
        let created = try ModelCatalog.createCustom(
            driverId: "claude_code", displayName: "Fabel", modelLabel: "fabel",
            role: .answerer, enabled: true, registry: registry)
        let records = [
            ToolProbeRecord(
                driverId: "claude_code",
                status: .ready(version: "1"),
                invocation: .direct(path: "/usr/bin/true"),
                lastProbeAt: Date()
            )
        ]
        let invoker = MockWorkerInvoking.answering([ModelSmokeVerifier.verificationToken])
        let smoke = try await ModelCatalog.verifyModelSmoke(
            id: created.id,
            registry: registry,
            invoker: invoker,
            probeRecords: records
        )
        XCTAssertEqual(smoke.status, .recognized)
        XCTAssertEqual(ModelCatalog.get(created.id)?.modelSmokeStatus, "recognized")
        XCTAssertNil(ModelCatalog.get(created.id)?.modelSmokeDetail)
        // Verify does not auto-enable.
        XCTAssertFalse(ModelCatalog.isEnabled(created.id))
    }

    func testBuiltInDeleteFails() {
        XCTAssertThrowsError(try ModelCatalog.deleteCustom("model_opus")) { error in
            XCTAssertEqual(error as? ModelCatalogError, .builtInImmutable)
        }
    }

    func testUnknownDriverFails() {
        let registry = testRegistry()
        XCTAssertThrowsError(try ModelCatalog.createCustom(
            driverId: "missing_driver", displayName: "X", modelLabel: "x",
            role: .answerer, registry: registry)) { error in
            if case .driverMissing(let id) = error as? ModelCatalogError {
                XCTAssertEqual(id, "missing_driver")
            } else {
                XCTFail("expected driverMissing")
            }
        }
    }

    func testDiscoveryDoesNotRunFromResolvedModels() {
        let registry = testRegistry()
        _ = ModelCatalog.resolvedModels(registry: registry)
        XCTAssertNil(ModelDiscoveryRegistry.provider(for: "claude_code"))
    }

    func testRecognizedModelInheritsDriverCapabilities() {
        // A default-off recognized model (no explicit tags) inherits its CLI's lane
        // capability, so enabling it makes it usable in team resolution.
        let caps = ModelCatalog.capabilities("model_gpt_54")
        XCTAssertFalse(caps.laneTags.isEmpty, "gpt-5.4 inherits Codex lanes")
        XCTAssertTrue(caps.capabilityTags.contains(.code))
    }

    func testEveryBuiltInHasCapabilityEntry() {
        let missing = ModelCatalog.builtIns.map(\.id).filter { ModelCatalog.builtInCapabilities[$0] == nil }
        XCTAssertTrue(missing.isEmpty, "builtIns missing builtInCapabilities: \(missing)")
    }

    func testCreateCustomPersistsEmptyCapabilitiesAndReadsUnratedRank() throws {
        let registry = testRegistry()
        let created = try ModelCatalog.createCustom(
            driverId: "claude_code", displayName: "Haiku Seat Test", modelLabel: "claude-haiku-test",
            role: .answerer, enabled: false, registry: registry)
        XCTAssertTrue(created.capabilities.capabilityTags.isEmpty)
        XCTAssertEqual(created.capabilities.strengthRank, 0)
        let caps = ModelCatalog.capabilities(created.id)
        XCTAssertEqual(caps.strengthRank, ModelCatalog.unratedModelRank)
        XCTAssertFalse(caps.capabilityTags.isEmpty, "unrated still inherits driver tags")
        XCTAssertEqual(ModelCatalog.caliberBand(caps.strengthRank), 0)
    }

    func testPoisonedCustomRankIsIgnored() throws {
        // Poisoned disk record: donor flagship caps persisted on a custom id.
        let registry = testRegistry()
        let created = try ModelCatalog.createCustom(
            driverId: "claude_code", displayName: "Poisoned", modelLabel: "poison",
            role: .answerer, enabled: false, registry: registry)
        var poisoned = created
        poisoned.capabilities = ModelCatalog.builtInCapabilities["model_fable"]!
        try ModelCatalog.updateCustom(poisoned)
        // The donor's rank, whatever it is — this test is about the poisoned
        // record being ignored at read time, not about a specific number.
        XCTAssertEqual(
            ModelCatalog.get(created.id)?.capabilities.strengthRank,
            ModelCatalog.builtInCapabilities["model_fable"]?.strengthRank)
        XCTAssertEqual(ModelCatalog.capabilities(created.id).strengthRank, ModelCatalog.unratedModelRank)
    }

    func testFloorBuiltInsSitAtUnratedBand() {
        XCTAssertEqual(ModelCatalog.capabilities("model_gpt_54_mini").strengthRank, 40)
        XCTAssertEqual(ModelCatalog.capabilities("model_gpt_spark").strengthRank, 40)
        XCTAssertLessThan(ModelCatalog.capabilities("model_gpt_54").strengthRank,
                          ModelCatalog.capabilities("model_gpt_sol").strengthRank)
    }

    func testHighValueWorkerModelsOutrankSonnet() {
        let sonnet = ModelCatalog.capabilities("model_sonnet").strengthRank
        XCTAssertGreaterThan(ModelCatalog.capabilities("model_cursor_grok_45").strengthRank, sonnet)
        XCTAssertGreaterThan(ModelCatalog.capabilities("model_cursor_grok_46").strengthRank, sonnet)
        XCTAssertGreaterThan(ModelCatalog.capabilities("model_cursor_grok_46").strengthRank,
                             ModelCatalog.capabilities("model_cursor_grok_45").strengthRank)
        XCTAssertGreaterThan(ModelCatalog.capabilities("model_kimi_k3").strengthRank, sonnet)
        XCTAssertGreaterThan(ModelCatalog.capabilities("model_grok").strengthRank, sonnet)
        XCTAssertGreaterThan(ModelCatalog.capabilities("model_grok_46").strengthRank, sonnet)
        XCTAssertGreaterThan(ModelCatalog.capabilities("model_grok_46").strengthRank,
                             ModelCatalog.capabilities("model_grok").strengthRank)
    }

    func testCustomClaudeFamilyMapsViaHostDriver() throws {
        let registry = testRegistry()
        let created = try ModelCatalog.createCustom(
            driverId: "claude_code", displayName: "Family Map", modelLabel: "fm",
            role: .answerer, enabled: false, registry: registry)
        XCTAssertEqual(ModelCatalog.modelFamily(created.id), "claude")
        XCTAssertEqual(ModelCatalog.hostFamily(driverId: "codex"), "gpt")
        XCTAssertEqual(ModelCatalog.hostFamily(driverId: "cursor_agent"), "driver:cursor_agent")
        XCTAssertEqual(ModelCatalog.modelFamily("unknown_no_disk", driverId: "kimi"), "kimi")
    }
}
