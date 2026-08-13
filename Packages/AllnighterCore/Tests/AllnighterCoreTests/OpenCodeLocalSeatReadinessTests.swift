import XCTest
@testable import AllnighterCore

/// Local OpenCode seats must not inherit Zen/Go driver smoke (packet §6.1 / §7.2).
/// Fixtures only — never a live Ollama, OpenCode, or Zen socket.
final class OpenCodeLocalSeatReadinessTests: XCTestCase {
    private let observedAt = Date(timeIntervalSince1970: 1_754_000_000)
    private let now = Date(timeIntervalSince1970: 1_754_000_100)

    private var modelsRoot: URL!
    private var rosterURL: URL!

    override func setUp() {
        super.setUp()
        let base = FileManager.default.temporaryDirectory.appendingPathComponent(
            UUID().uuidString, isDirectory: true)
        modelsRoot = base.appendingPathComponent("models", isDirectory: true)
        rosterURL = base.appendingPathComponent("model_roster.json")
        CatalogRoots.overrideForTesting(
            teams: base.appendingPathComponent("teams", isDirectory: true),
            skills: base.appendingPathComponent("skills", isDirectory: true),
            models: modelsRoot)
        ModelCatalog.overrideRosterForTesting(fileURL: rosterURL)
        XCTAssertTrue(AllnighterSupportRoot.isRunningUnderTestHost)
    }

    override func tearDown() {
        CatalogRoots.resetTestingOverrides()
        ModelCatalog.resetTestingOverrides()
        try? FileManager.default.removeItem(at: modelsRoot.deletingLastPathComponent())
        super.tearDown()
    }

    func testLocalSeatIgnoresRejectedZenSmokeWhenTagIsPresent() {
        let outcome = OpenCodeLocalSeatReadiness.verify(
            modelLabel: "ollama/qwen3:8b",
            driverId: "opencode",
            probeRecord: zenRejectedRecord(),
            snapshot: idleSnapshot(tags: ["qwen3:8b"]),
            now: now
        )
        guard case .recognized(let smoke) = outcome else {
            return XCTFail("expected recognized, got \(outcome)")
        }
        XCTAssertEqual(smoke.status, .recognized)
        XCTAssertEqual(smoke.label, "ollama/qwen3:8b")
        XCTAssertNil(smoke.detail)
        XCTAssertTrue(
            OpenCodeLocalSeatReadiness.isLocallyReady(
                modelLabel: "ollama/qwen3:8b",
                binaryPath: "/usr/local/bin/opencode",
                snapshot: idleSnapshot(tags: ["qwen3:8b"])
            )
        )
    }

    func testGoSeatIsNotLocalAndMissingCLIWhenZenRejected() {
        XCTAssertFalse(
            OpenCodeLocalSeatReadiness.isLocalOpenCodeSeat(
                driverId: "opencode", modelLabel: "opencode-go/kimi-k2.5")
        )
        let outcome = OpenCodeLocalSeatReadiness.verify(
            modelLabel: "opencode-go/kimi-k2.5",
            driverId: "opencode",
            probeRecord: zenRejectedRecord(),
            snapshot: idleSnapshot(tags: ["qwen3:8b"]),
            now: now
        )
        XCTAssertEqual(outcome, .notLocalSeat)
        XCTAssertNil(
            OpenCodeLocalSeatReadiness.installedBinaryPath(
                from: ToolProbeRecord(
                    driverId: "opencode",
                    status: .probeFailed(reason: "opencode smoke: provider rejected"),
                    lastProbeAt: now
                )
            ),
            "probeFailed without an invocation path is missing CLI"
        )
    }

    func testLocalSeatMissingTagIsRejectedWithoutBorrowingZen() {
        let outcome = OpenCodeLocalSeatReadiness.verify(
            modelLabel: "ollama/qwen3:8b",
            driverId: "opencode",
            probeRecord: zenRejectedRecord(),
            snapshot: idleSnapshot(tags: ["qwen2.5:0.5b"]),
            now: now
        )
        guard case .rejected(let smoke) = outcome else {
            return XCTFail("expected rejected, got \(outcome)")
        }
        XCTAssertEqual(smoke.status, .unrecognized)
        XCTAssertEqual(smoke.detail, "Ollama tag not present locally: qwen3:8b")
    }

    func testUnreachableOllamaDoesNotUseZenReady() {
        let zenReady = ToolProbeRecord(
            driverId: "opencode",
            status: .ready(version: "1.18.16"),
            invocation: .direct(path: "/usr/local/bin/opencode"),
            version: "1.18.16",
            lastProbeAt: now
        )
        let down = OllamaLocalRuntimeObserver.Snapshot(
            readiness: .unavailable,
            observedAt: observedAt,
            ollamaVersion: nil,
            localTags: [],
            observeFailure: .version(.network("connection refused"))
        )
        let outcome = OpenCodeLocalSeatReadiness.verify(
            modelLabel: "ollama/qwen3:8b",
            driverId: "opencode",
            probeRecord: zenReady,
            snapshot: down,
            now: now
        )
        guard case .rejected(let smoke) = outcome else {
            return XCTFail("expected rejected, got \(outcome)")
        }
        XCTAssertEqual(smoke.detail, "Ollama not reachable")
    }

    func testVerifyLocalSucceedsWhileZenProbeFailed() async throws {
        let created = try addCustom(label: "ollama/qwen3:8b", name: "Qwen3 local")
        let failing = MockWorkerInvoking.failing("Zen smoke must not run for a local seat")
        let smoke = try await ModelCatalog.verifyModelSmoke(
            id: created.id,
            registry: opencodeRegistry(),
            invoker: failing,
            probeRecords: [zenRejectedRecord()],
            ollamaSnapshot: idleSnapshot(tags: ["qwen3:8b"]),
            now: now
        )
        XCTAssertEqual(smoke.status, .recognized)
        XCTAssertEqual(ModelCatalog.get(created.id)?.modelSmokeStatus, "recognized")
        XCTAssertNil(ModelCatalog.get(created.id)?.modelSmokeDetail)
        try ModelCatalog.setEnabled(created.id, true)
        XCTAssertTrue(ModelCatalog.isEnabled(created.id))
    }

    func testVerifyGoSeatStillFailsWhenProviderProbeFailed() async throws {
        let created = try addCustom(label: "opencode-go/kimi-k2.5", name: "Go Kimi")
        let failing = MockWorkerInvoking.failing("Go verify must not invent a pass")
        do {
            _ = try await ModelCatalog.verifyModelSmoke(
                id: created.id,
                registry: opencodeRegistry(),
                invoker: failing,
                probeRecords: [zenRejectedRecord()],
                ollamaSnapshot: idleSnapshot(tags: ["qwen3:8b"]),
                now: now
            )
            XCTFail("Go seat must keep failing when the OpenCode probe is not ready")
        } catch let error as ModelCatalogError {
            guard case .invalid(let detail) = error else {
                return XCTFail("expected invalid, got \(error)")
            }
            XCTAssertEqual(detail, "CLI not detected/ready")
        }
        XCTAssertEqual(ModelCatalog.get(created.id)?.modelSmokeStatus, "unverified")
    }

    func testModelsListLocalReadyWhileGoNotReadyOnRejectedZen() throws {
        let local = ModelDefinition(
            id: "custom_opencode_ollama_qwen3_8b_local",
            displayName: "Qwen3 local",
            modelLabel: "ollama/qwen3:8b",
            driverId: "opencode",
            role: .answerer,
            origin: .custom,
            defaultEnabled: true,
            capabilities: ModelCapabilities()
        )
        let go = ModelDefinition(
            id: "custom_opencode_go_kimi",
            displayName: "Go Kimi",
            modelLabel: "opencode-go/kimi-k2.5",
            driverId: "opencode",
            role: .answerer,
            origin: .custom,
            defaultEnabled: true,
            capabilities: ModelCapabilities()
        )
        let list = ModelListProjector.build(
            registry: opencodeRegistry(),
            definitions: [local, go],
            probeRecords: [zenRejectedRecord()],
            now: now,
            diagnostics: [],
            ollamaLocal: idleSnapshot(tags: ["qwen3:8b"])
        )
        let localRow = try XCTUnwrap(list.models.first { $0.id == local.id })
        let goRow = try XCTUnwrap(list.models.first { $0.id == go.id })
        XCTAssertEqual(localRow.status, "ready")
        XCTAssertTrue(localRow.ready)
        XCTAssertEqual(localRow.readiness, "Idle")
        XCTAssertEqual(goRow.status, "notReady")
        XCTAssertFalse(goRow.ready)
        XCTAssertNil(goRow.readiness)
    }

    func testBenchAdmitsLocalSeatWhenZenIsRejectedAndGoStaysOut() {
        let local = Model(
            id: "custom_opencode_ollama_qwen3",
            displayName: "Qwen3 local",
            modelLabel: "ollama/qwen3:8b",
            driverId: "opencode",
            role: .answerer,
            enabled: true
        )
        let go = Model(
            id: "custom_opencode_go_kimi",
            displayName: "Go Kimi",
            modelLabel: "opencode-go/kimi-k2.5",
            driverId: "opencode",
            role: .answerer,
            enabled: true
        )
        let ready = BenchReadiness.readyModels(
            models: [local, go],
            probeRecords: [zenRejectedRecord()],
            coolingDriverIds: ["opencode"],
            ollamaLocal: idleSnapshot(tags: ["qwen3:8b"])
        )
        XCTAssertEqual(ready.map(\.id), [local.id])
    }

    func testGoSeatStaysOffBenchWhenItsProviderProbeFailed() {
        let go = Model(
            id: "custom_opencode_go_kimi",
            displayName: "Go Kimi",
            modelLabel: "opencode-go/kimi-k2.5",
            driverId: "opencode",
            role: .answerer,
            enabled: true
        )
        let ready = BenchReadiness.readyModels(
            models: [go],
            probeRecords: [zenRejectedRecord()],
            ollamaLocal: idleSnapshot(tags: ["qwen3:8b"])
        )
        XCTAssertTrue(ready.isEmpty)
    }

    // MARK: - Helpers

    private func opencodeRegistry() -> DriverRegistry {
        DriverRegistry([
            DriverManifest(
                id: "opencode",
                displayName: "OpenCode",
                kind: .headlessCLI,
                invoke: .init(
                    command: "opencode",
                    args: ["run", "-m", "{{model}}", "{{prompt}}"]
                )
            )
        ])
    }

    private func addCustom(label: String, name: String) throws -> ModelDefinition {
        try ModelCatalog.createCustom(
            driverId: "opencode",
            displayName: name,
            modelLabel: label,
            role: .answerer,
            enabled: true,
            registry: opencodeRegistry()
        )
    }

    private func zenRejectedRecord() -> ToolProbeRecord {
        ToolProbeRecord(
            driverId: "opencode",
            status: .probeFailed(reason: "opencode smoke: provider rejected"),
            invocation: .direct(path: "/usr/local/bin/opencode"),
            version: "1.18.16",
            lastProbeAt: now
        )
    }

    private func idleSnapshot(tags: [String]) -> OllamaLocalRuntimeObserver.Snapshot {
        OllamaLocalRuntimeObserver.Snapshot(
            readiness: .idle,
            observedAt: observedAt,
            ollamaVersion: "0.32.6",
            localTags: tags.map { .init(name: $0) }
        )
    }
}
