import XCTest
@testable import AllnighterCore

/// LR-S01b — `menu --json` `localRuntime` + `drivers --json` `localRuntimeSeats`.
/// Fixture-only: never opens a socket, never writes the real catalog.
final class LocalRuntimeSurfaceS01bTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_754_000_000)
    private let registry = DriverRegistry([
        DriverManifest(id: "claude_code", displayName: "Claude Code", kind: .headlessCLI),
        DriverManifest(id: "opencode", displayName: "OpenCode", kind: .headlessCLI),
    ])
    private let paid = ModelDefinition(
        id: "model_lr_s01b_paid_fixture",
        displayName: "Paid fixture",
        modelLabel: "opus",
        driverId: "claude_code",
        role: .answerer,
        origin: .builtIn,
        defaultEnabled: true,
        capabilities: ModelCapabilities()
    )
    private let seatedLocal = ModelDefinition(
        id: "custom_claude_code_qwen38_27b_local",
        displayName: "Qwen seated",
        modelLabel: "ollama/qwen3.8:27b-mlx",
        driverId: "claude_code",
        role: .answerer,
        origin: .custom,
        defaultEnabled: true,
        capabilities: ModelCapabilities()
    )
    private let seatedOpenCode = ModelDefinition(
        id: "custom_opencode_gpt_oss_local",
        displayName: "GPT-OSS seated",
        modelLabel: "ollama/gpt-oss:20b",
        driverId: "opencode",
        role: .answerer,
        origin: .custom,
        defaultEnabled: true,
        capabilities: ModelCapabilities()
    )

    private let tagsPayload = """
    {"models":[
      {"name":"qwen3.8:27b-mlx","capabilities":["completion","vision","tools","thinking"]},
      {"name":"gpt-oss:20b","capabilities":["completion"]},
      {"name":"nomic-shaped-orphan"}
    ]}
    """

    func testMenuLocalRuntimeListsEveryDiscoveredTagWithDefaultBody() throws {
        let snapshot = snapshotFromPayload()
        let list = modelList(from: [paid], snapshot: snapshot)
        let menu = MenuCatalog.project(
            teams: [],
            modelEntries: list.models,
            ollamaLocal: snapshot
        )
        let runtime = try XCTUnwrap(menu.localRuntime)
        XCTAssertEqual(runtime.defaultBody, "opencode")
        XCTAssertEqual(runtime.tags.map(\.label), [
            "ollama/gpt-oss:20b",
            "ollama/qwen3.8:27b-mlx",
            "ollama/nomic-shaped-orphan",
        ])

        let orphanID = OllamaLocalModelDiscoveryProvider.candidateID(tag: "nomic-shaped-orphan")
        let orphan = try XCTUnwrap(runtime.tags.first { $0.id == orphanID })
        XCTAssertEqual(orphan.seated, false)
        XCTAssertEqual(orphan.enabled, false)
        XCTAssertTrue(orphan.enableCommand?.contains("--body opencode") ?? false)

        let completeness = try XCTUnwrap(menu.completeness.localRuntime)
        XCTAssertEqual(completeness.count, 3)
        XCTAssertTrue(completeness.complete)
    }

    func testMenuTierOneOmitsOverlayButLocalRuntimeStillNamesIt() throws {
        let snapshot = snapshotFromPayload()
        let list = modelList(from: [paid], snapshot: snapshot)
        let menu = MenuCatalog.project(
            teams: [],
            modelEntries: list.models,
            ollamaLocal: snapshot
        )
        let overlayID = OllamaLocalModelDiscoveryProvider.candidateID(tag: "nomic-shaped-orphan")
        XCTAssertNil(menu.models.first { $0.id == overlayID })
        XCTAssertNotNil(menu.localRuntime?.tags.first { $0.id == overlayID })
    }

    func testSeatedLocalAppearsInLocalRuntimeNotDuplicatedAsOverlay() throws {
        let snapshot = snapshotFromPayload()
        let list = modelList(from: [paid, seatedLocal], snapshot: snapshot)
        let menu = MenuCatalog.project(
            teams: [],
            modelEntries: list.models,
            ollamaLocal: snapshot
        )
        let overlayID = OllamaLocalModelDiscoveryProvider.candidateID(tag: "qwen3.8:27b-mlx")
        XCTAssertNil(list.models.first { $0.id == overlayID })

        let runtime = try XCTUnwrap(menu.localRuntime)
        let seated = try XCTUnwrap(runtime.tags.first { $0.label == "ollama/qwen3.8:27b-mlx" })
        XCTAssertEqual(seated.id, seatedLocal.id)
        XCTAssertEqual(seated.seated, true)
        XCTAssertNil(seated.enableCommand)
    }

    func testDriversJSONLocalRuntimeSeatsOnlyOnHostingBody() throws {
        let models = ModelCatalog.materializeForTests(
            [paid, seatedLocal, seatedOpenCode],
            registry: registry,
            enabledIds: [seatedLocal.id, seatedOpenCode.id]
        )
        let drivers = DriverListProjector.build(
            registry: registry,
            probeRecords: [],
            now: now,
            models: models,
            parkedDriverIds: []
        )
        let claude = try XCTUnwrap(drivers.drivers.first { $0.driverId == "claude_code" })
        let opencode = try XCTUnwrap(drivers.drivers.first { $0.driverId == "opencode" })
        XCTAssertEqual(claude.localRuntimeSeats, 1)
        XCTAssertEqual(opencode.localRuntimeSeats, 1)
    }

    func testDriversJSONOmitsLocalRuntimeSeatsWhenZero() {
        let drivers = DriverListProjector.build(
            registry: registry,
            probeRecords: [],
            now: now,
            models: [],
            parkedDriverIds: []
        )
        for row in drivers.drivers {
            XCTAssertNil(row.localRuntimeSeats)
        }
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

    private func modelList(
        from definitions: [ModelDefinition],
        snapshot: OllamaLocalRuntimeObserver.Snapshot
    ) -> ModelListJSON {
        ModelListProjector.build(
            registry: registry,
            definitions: definitions,
            probeRecords: [],
            now: now,
            diagnostics: [],
            ollamaLocal: snapshot
        )
    }
}

// MARK: - Test-only materialize

private extension ModelCatalog {
    static func materializeForTests(
        _ definitions: [ModelDefinition],
        registry: DriverRegistry,
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
