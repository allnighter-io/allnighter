import XCTest
@testable import AllnighterCore

/// LR-S05c — persisted default body + ruling 5 hosting-body pointer.
/// Fixture-only: never opens Ollama, never walks `/api/tags`.
final class LocalRuntimeSurfaceS05cTests: XCTestCase {
    private var scratch: URL!
    private let now = Date(timeIntervalSince1970: 1_754_000_000)
    private let registry = DriverRegistry([
        DriverManifest(id: "claude_code", displayName: "Claude Code", kind: .headlessCLI),
        DriverManifest(id: "opencode", displayName: "OpenCode", kind: .headlessCLI),
    ])

    private let paid = ModelDefinition(
        id: "model_lr_s05c_paid_fixture",
        displayName: "Paid fixture",
        modelLabel: "opus",
        driverId: "claude_code",
        role: .answerer,
        origin: .builtIn,
        defaultEnabled: true,
        capabilities: ModelCapabilities()
    )
    private let paidOpenCode = ModelDefinition(
        id: "model_lr_s05c_paid_opencode",
        displayName: "Big Pickle",
        modelLabel: "big-pickle",
        driverId: "opencode",
        role: .answerer,
        origin: .builtIn,
        defaultEnabled: true,
        capabilities: ModelCapabilities()
    )
    private let seatedOpenCode = ModelDefinition(
        id: OllamaLocalModelDiscoveryProvider.seatedID(
            tag: "qwen3.8:27b-mlx", bodyDriverId: "opencode"),
        displayName: "Qwen3.8 27B",
        modelLabel: "ollama/qwen3.8:27b-mlx",
        driverId: "opencode",
        role: .answerer,
        origin: .discovered,
        defaultEnabled: true,
        capabilities: ModelCapabilities()
    )

    override func setUp() {
        super.setUp()
        scratch = FileManager.default.temporaryDirectory
            .appendingPathComponent("lr-s05c-\(UUID().uuidString)", isDirectory: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: scratch)
        super.tearDown()
    }

    // MARK: - Persisted default body (§0.5)

    func testPersistedDefaultBodyAppliesToNextEnableOnly() throws {
        let url = scratch.appendingPathComponent("local_runtime.json")
        let store = LocalRuntimeDefaultBody(fileURL: url)
        XCTAssertEqual(store.resolved(), "opencode")

        try store.save("claude_code")
        XCTAssertEqual(store.resolved(), "claude_code")

        let candidate = OllamaLocalModelDiscoveryProvider.candidateID(tag: "qwen3.8:27b-mlx")
        let command = OllamaLocalModelDiscoveryProvider.enableCommand(
            candidateID: candidate, bodyDriverId: store.resolved())
        XCTAssertTrue(command.contains("--body claude_code"), command)

        let seatedBefore = OllamaLocalModelDiscoveryProvider.seatedID(
            tag: "qwen3.8:27b-mlx", bodyDriverId: "opencode")
        try store.save("opencode")
        let seatedAfter = OllamaLocalModelDiscoveryProvider.seatedID(
            tag: "qwen3.8:27b-mlx", bodyDriverId: "opencode")
        XCTAssertEqual(seatedBefore, seatedAfter)
        XCTAssertNotEqual(
            seatedBefore,
            OllamaLocalModelDiscoveryProvider.seatedID(
                tag: "qwen3.8:27b-mlx", bodyDriverId: "claude_code")
        )
    }

    func testSelectorWriteRefusesUnknownBodyAndDoesNotRemint() {
        let url = scratch.appendingPathComponent("local_runtime.json")
        let store = LocalRuntimeDefaultBody(fileURL: url)
        XCTAssertThrowsError(try store.save("ollama_local"))
        XCTAssertEqual(store.resolved(), "opencode")
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
    }

    func testMenuDefaultBodyUsesPersistedOverrideForNextEnable() throws {
        let snapshot = snapshotFromPayload()
        let list = ModelListProjector.build(
            registry: registry,
            definitions: [paid],
            probeRecords: [],
            now: now,
            diagnostics: [],
            ollamaLocal: snapshot
        )
        let menu = MenuCatalog.project(
            teams: [],
            modelEntries: list.models,
            ollamaLocal: snapshot,
            defaultBody: "claude_code"
        )
        XCTAssertEqual(menu.localRuntime?.defaultBody, "claude_code")
        let overlay = try XCTUnwrap(menu.localRuntime?.tags.first { $0.seated == false })
        XCTAssertTrue(
            overlay.enableCommand?.contains("--body claude_code") == true,
            overlay.enableCommand ?? "")
    }

    func testSurfaceOverrideDoesNotRewriteSeatedIds() throws {
        let snapshot = snapshotFromPayload()
        let surface = LocalRuntimeSurfacePresenter.build(
            registry: registry,
            probeRecords: [
                ToolProbeRecord(driverId: "opencode", status: .ready(version: "1"), version: "1", lastProbeAt: now),
                ToolProbeRecord(driverId: "claude_code", status: .ready(version: "1"), version: "1", lastProbeAt: now),
            ],
            parkedDriverIds: [],
            definitions: [seatedOpenCode],
            now: now,
            ollamaLocal: snapshot,
            defaultBody: "claude_code"
        )
        XCTAssertEqual(surface.defaultBody, "claude_code")
        let seated = try XCTUnwrap(surface.tags.first { $0.seated })
        XCTAssertEqual(seated.id, seatedOpenCode.id)
        XCTAssertTrue(seated.id.contains("opencode"))
        XCTAssertFalse(seated.id.contains("claude_code"))
    }

    // MARK: - Ruling 5

    func testRuling5PointerIsNotARosterSeat() throws {
        let models = materialize(
            [paid, paidOpenCode, seatedOpenCode],
            enabledIds: [paid.id, paidOpenCode.id, seatedOpenCode.id]
        )
        let drivers = DriverListProjector.build(
            registry: registry,
            probeRecords: [],
            now: now,
            models: models,
            parkedDriverIds: []
        )
        let opencode = try XCTUnwrap(drivers.drivers.first { $0.driverId == "opencode" })
        let claude = try XCTUnwrap(drivers.drivers.first { $0.driverId == "claude_code" })

        XCTAssertEqual(opencode.localRuntimeSeats, 1)
        XCTAssertNil(claude.localRuntimeSeats)

        let host = try XCTUnwrap(
            LocalRuntimePointerPresenter.row(
                driverId: opencode.driverId,
                localRuntimeSeats: opencode.localRuntimeSeats
            )
        )
        XCTAssertEqual(host.label, ChromeCopy.localRuntimePointerLabel(count: 1))
        XCTAssertFalse(host.selectable)
        XCTAssertFalse(host.countsTowardRoster)
        XCTAssertFalse(host.isModelsEntry)

        XCTAssertNil(
            LocalRuntimePointerPresenter.row(
                driverId: claude.driverId,
                localRuntimeSeats: claude.localRuntimeSeats
            )
        )

        let openRoster = LocalRuntimePointerPresenter.rosterDisplayNames(
            models: models, driverId: "opencode")
        let claudeRoster = LocalRuntimePointerPresenter.rosterDisplayNames(
            models: models, driverId: "claude_code")
        XCTAssertEqual(openRoster, ["Big Pickle"])
        XCTAssertEqual(claudeRoster, ["Paid fixture"])
        XCTAssertFalse(openRoster.contains(seatedOpenCode.displayName))
        XCTAssertFalse(claudeRoster.contains(seatedOpenCode.displayName))
        XCTAssertFalse(openRoster.contains(host.label))

        let snapshot = snapshotFromPayload()
        let list = ModelListProjector.build(
            registry: registry,
            definitions: [paid, paidOpenCode, seatedOpenCode],
            probeRecords: [],
            now: now,
            diagnostics: [],
            ollamaLocal: snapshot
        )
        let menu = MenuCatalog.project(
            teams: [],
            modelEntries: list.models,
            ollamaLocal: snapshot
        )
        XCTAssertFalse(menu.models.contains { $0.displayName == host.label })
        XCTAssertFalse(menu.models.contains { $0.id == host.label })
    }

    func testPointerOmitsDisabledSeatedLocal() {
        let models = materialize(
            [paidOpenCode, seatedOpenCode],
            enabledIds: [paidOpenCode.id]
        )
        let drivers = DriverListProjector.build(
            registry: registry,
            probeRecords: [],
            now: now,
            models: models,
            parkedDriverIds: []
        )
        let opencode = drivers.drivers.first { $0.driverId == "opencode" }
        XCTAssertNil(opencode?.localRuntimeSeats)
        XCTAssertNil(
            LocalRuntimePointerPresenter.row(
                driverId: "opencode",
                localRuntimeSeats: opencode?.localRuntimeSeats
            )
        )
    }

    // MARK: - Helpers

    private func snapshotFromPayload() -> OllamaLocalRuntimeObserver.Snapshot {
        let tagsJSON = """
        {"models":[
          {"name":"qwen3.8:27b-mlx","capabilities":["completion","tools"]},
          {"name":"gpt-oss:20b","capabilities":["completion"]}
        ]}
        """
        let tags = OllamaLocalRuntimeObserver.parseTags(Data(tagsJSON.utf8))!
        return OllamaLocalRuntimeObserver.snapshot(
            observedAt: now,
            ollamaVersion: "0.32.12",
            localTags: tags,
            residentModels: []
        )
    }

    private func materialize(
        _ definitions: [ModelDefinition],
        enabledIds: [String]
    ) -> [Model] {
        let enabled = Set(enabledIds)
        return definitions.map { def in
            Model(
                id: def.id,
                displayName: def.displayName,
                modelLabel: def.modelLabel,
                driverId: def.driverId,
                role: def.role,
                enabled: enabled.contains(def.id),
                effortVariants: def.effortVariants,
                family: def.family,
                generation: def.generation,
                resolvedPinId: def.resolvedPinId
            )
        }
    }
}
