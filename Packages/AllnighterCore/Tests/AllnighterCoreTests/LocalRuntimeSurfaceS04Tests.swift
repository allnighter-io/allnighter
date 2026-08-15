import XCTest
@testable import AllnighterCore

/// LR-S04 — pin-ability: an enabled seated local id resolves `--model` and
/// `preferredModelId`. Implementation skipped — S02 minting + S04b ready-set
/// already cover it; this file proves the resolution choke points.
/// preferredModelId proof: `LocalRuntimeSurfaceS04bTests.testS00Q3PinnedLocalResolvesWhenOllamaObserved`.
final class LocalRuntimeSurfaceS04Tests: XCTestCase {
    private var modelsRoot: URL!
    private var rosterURL: URL!
    private let now = Date(timeIntervalSince1970: 1_754_000_000)
    private let registry = DriverRegistry([
        DriverManifest(id: "claude_code", displayName: "Claude Code", kind: .headlessCLI),
        DriverManifest(id: "opencode", displayName: "OpenCode", kind: .headlessCLI),
    ])

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

    func testDiscoveredSeatedIdListsAndResolvesExplicitModel() throws {
        let tag = "qwen3.8:27b-mlx"
        let seatedID = OllamaLocalModelDiscoveryProvider.seatedID(
            tag: tag, bodyDriverId: "claude_code")
        try ModelCatalog.saveDiscovered(seatedClaude(tag: tag))
        try ModelCatalog.setEnabled(seatedID, true)

        XCTAssertNotNil(ModelCatalog.get(seatedID))
        XCTAssertTrue(ModelCatalog.list().contains(where: { $0.id == seatedID && $0.origin == .discovered }))

        let materialized = ModelCatalog.resolvedModels(registry: registry)
        let model = try XCTUnwrap(materialized.first(where: { $0.id == seatedID }))
        XCTAssertTrue(model.enabled)

        let snapshot = OllamaLocalRuntimeObserver.Snapshot(
            observedAt: now,
            ollamaVersion: "0.32.12",
            localTags: [.init(name: tag)]
        )
        let ready = BenchReadiness.readyModels(
            models: materialized,
            probeRecords: [claudeInstalledRecord()],
            ollamaLocal: snapshot
        )
        XCTAssertTrue(ready.contains(where: { $0.id == seatedID }))

        let resolved = ExactIdResolver.resolveWorker(
            seatedID,
            models: materialized,
            readyModelIds: Set(ready.map(\.id))
        )
        switch resolved {
        case .success(let picked):
            XCTAssertEqual(picked.id, seatedID)
            XCTAssertEqual(picked.modelLabel, "ollama/\(tag)")
        case .failure(let failure):
            XCTFail("expected --model to resolve discovered seated id: \(failure.message)")
        }
    }

    private func seatedClaude(tag: String) -> ModelDefinition {
        var seat = OllamaLocalModelDiscoveryProvider.candidate(for: tag, discoveredAt: now)
        seat.driverId = "claude_code"
        seat.id = OllamaLocalModelDiscoveryProvider.seatedID(tag: tag, bodyDriverId: "claude_code")
        seat.origin = .discovered
        return seat
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
}
