import XCTest
import AllnighterCore
import AllnighterEngine
@testable import AllnighterMac

/// R-S08 — the Mac GUI PM Relay launch surface. `RelayGUIRuntime`/`RelayLaunchViewModel`
/// can't be compared against `RelayDispatch.makeCoordinator` by a cross-module test:
/// `AllnighterCLI` is an `executableTarget` (`Packages/AllnighterCore/Package.swift`), not
/// a library product, so neither the Mac app nor its test target can import it — that's
/// exactly why `RelayGUIRuntime.makeCoordinator` MIRRORS the construction instead of
/// calling it (see that type's doc comment). These tests instead prove: (1) validation
/// enforces the doc/seat/max-rounds requirements, and (2) `start()` actually drives a real
/// `RelayCoordinator`/`RelayThreadProjector` end to end (temp stores, a stub `CommandRunner`
/// standing in for the CLI subprocess) so construction wiring is exercised, not just
/// asserted.
@MainActor
final class RelayLaunchViewModelTests: XCTestCase {
    /// Always returns a fixed PM-turn output carrying a valid `RelayVerdict` tail — makes
    /// every dispatched turn settle immediately, deterministically, with zero subprocess
    /// cost, regardless of which worker/driver the config resolves to.
    private struct DoneVerdictRunner: CommandRunner {
        func run(command: String, args: [String], stdin: String?, env: [String: String],
                  workingDirectory: String?, timeout: Duration) async -> CommandResult {
            CommandResult(stdout: """
            Reviewed. Nothing left to do.
            ```json
            {"verdict":"done","note":"Shipped."}
            ```
            """, exitCode: 0)
        }
    }

    private func tempRoot(_ label: String) -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("alln-relay-launch-\(label)-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    /// A `makeCoordinator`-shaped factory wired to temp stores + a deterministic runner —
    /// the SAME `RelayCoordinator`/`RelayThreadProjector`/`RunService` production types
    /// `RelayGUIRuntime.makeCoordinator` builds, just pointed at an isolated root so the
    /// test never touches real user data.
    /// Coordinator factory + a matching thread-projector factory over the SAME temp
    /// `ThreadStore`/`RunStore` — mirrors `RelayLaunchViewModel`'s production pairing
    /// (`RelayGUIRuntime.makeCoordinator` + the default `RelayThreadProjector()`), just
    /// pointed at an isolated root instead of the real default paths.
    private func stubbedFactory(root: URL, models: [Model], registry: DriverRegistry) -> (
        coordinator: (@escaping @Sendable () -> String) -> RelayCoordinator,
        threadProjector: () -> RelayThreadProjector
    ) {
        let store = ThreadStore(rootDirectory: root.appendingPathComponent("threads", isDirectory: true))
        let runStore = RunStore(rootDirectory: root.appendingPathComponent("runs", isDirectory: true))
        let stateStore = RelayStateStore(rootDirectory: root.appendingPathComponent("relay", isDirectory: true))
        let stubDriverIdValue = Self.stubDriverId
        let coordinatorFactory: (@escaping @Sendable () -> String) -> RelayCoordinator = { idFactory in
            RelayCoordinator(
                runService: RunService(
                    models: models, registry: registry, runStore: runStore,
                    commandRunner: DoneVerdictRunner(),
                    // Declare the stub driver ready. Readiness normally comes from
                    // the user's SetupStore probe cache; borrowing that made the
                    // test depend on whether the founder's bench happened to be
                    // probed, which is not what these tests are about.
                    probeRecords: {
                        [ToolProbeRecord(driverId: stubDriverIdValue,
                                         status: .ready(version: "relay-stub 1.0"),
                                         lastProbeAt: Date())]
                    }
                ),
                stateStore: stateStore,
                runStore: runStore,
                threadProjector: RelayThreadProjector(store: store, runStore: runStore),
                idFactory: idFactory
            )
        }
        return (coordinatorFactory, { RelayThreadProjector(store: store, runStore: runStore) })
    }


    /// A driver + two workers this test OWNS. Previously these tests seated
    /// `AppConfig.loadConfiguration().models[0..1]` — the user's live catalog —
    /// which made them fail for reasons that had nothing to do with the relay:
    /// the first model was simply disabled (WORKER_NOT_AVAILABLE), and once that
    /// was skipped the next two sat on WARM drivers (cursor/grok ACP, codex
    /// app-server, claude stream-json) that a canned-stdout stub cannot drive, so
    /// the PM turn was judged stalled. A plain headless driver is exactly what
    /// `DoneVerdictRunner` can stand in for, and it cannot drift when the user
    /// edits their bench.
    nonisolated static let stubDriverId = "relay_stub_cli"

    private func stubRegistry() -> DriverRegistry {
        DriverRegistry([
            DriverManifest(
                id: Self.stubDriverId,
                displayName: "Relay Stub CLI",
                kind: .headlessCLI,
                detectCommand: "relay-stub --version",
                smokeTestCommand: "relay-stub smoke {{model}}",
                smokeTestExpect: "READY",
                invoke: .init(
                    command: "relay-stub",
                    args: ["-p", "{{prompt}}", "--model", "{{model}}"],
                    promptVia: .arg,
                    env: [:],
                    workingDir: nil,
                    timeoutSeconds: 5
                ),
                output: .init()
            )
        ])
    }

    private func stubWorkers() -> [Model] {
        [
            Model(id: "relay_stub_pm", displayName: "Stub PM", modelLabel: "pm",
                  driverId: Self.stubDriverId, role: .answerer, enabled: true),
            Model(id: "relay_stub_dev", displayName: "Stub Dev", modelLabel: "dev",
                  driverId: Self.stubDriverId, role: .answerer, enabled: true)
        ]
    }

    private func repoRoot() -> String {
        let url = tempRoot("repo")
        return url.path
    }

    // MARK: - Validation

    func testValidationRequiresDocAndSeats() {
        let issues = RelayLaunchViewModel.validate(
            docPath: "", pmWorkerId: nil, devWorkerId: nil, maxRounds: 20)
        XCTAssertTrue(issues.contains { $0.id == "doc" })
        XCTAssertTrue(issues.contains { $0.id == "pm" })
        XCTAssertTrue(issues.contains { $0.id == "dev" })
    }

    func testValidationRejectsSameSeatForBothRoles() {
        let issues = RelayLaunchViewModel.validate(
            docPath: "docs/spec.md", pmWorkerId: "model_x", devWorkerId: "model_x", maxRounds: 20)
        XCTAssertTrue(issues.contains { $0.id == "same-seat" })
    }

    func testValidationRejectsNonPositiveMaxRounds() {
        let issues = RelayLaunchViewModel.validate(
            docPath: "docs/spec.md", pmWorkerId: "a", devWorkerId: "b", maxRounds: 0)
        XCTAssertTrue(issues.contains { $0.id == "max-rounds" })
    }

    func testCanStartTrueOnlyWhenValid() {
        let config = AppConfig.loadConfiguration()
        let vm = RelayLaunchViewModel(
            projectId: "prj_test", projectRoot: repoRoot(),
            models: config.models, registry: config.registry, readyModels: [])
        XCTAssertFalse(vm.canStart)
        vm.docPath = "docs/spec.md"
        vm.pmWorkerId = "pm_worker"
        vm.devWorkerId = "dev_worker"
        XCTAssertTrue(vm.canStart)
    }

    // MARK: - Start (real coordinator, isolated stores)

    func testStartSeedsThreadImmediatelyAndReachesDone() async throws {
        let seatable = stubWorkers()
        let registry = stubRegistry()
        let root = tempRoot("start")
        let factory = stubbedFactory(root: root, models: seatable, registry: registry)
        let vm = RelayLaunchViewModel(
            projectId: "prj_test", projectRoot: repoRoot(),
            models: seatable, registry: registry, readyModels: [],
            makeCoordinator: factory.coordinator,
            makeThreadProjector: factory.threadProjector
        )
        vm.docPath = "docs/spec.md"
        vm.pmWorkerId = seatable[0].id
        vm.devWorkerId = seatable[1].id

        guard let relayId = vm.start() else {
            return XCTFail("valid config must start")
        }
        XCTAssertTrue(relayId.hasPrefix("relay_"))

        // The thread must exist SYNCHRONOUSLY (before the background Task's first
        // suspension) — the GUI selects it right after `start()` returns.
        let store = ThreadStore(rootDirectory: root.appendingPathComponent("threads", isDirectory: true))
        XCTAssertNotNil(store.get(relayId), "start() must seed the relay's thread before returning")

        let stateStore = RelayStateStore(rootDirectory: root.appendingPathComponent("relay", isDirectory: true))
        var settled: RelayState?
        for _ in 0..<200 {
            if let state = stateStore.load(id: relayId), state.status != .running {
                settled = state; break
            }
            try await Task.sleep(nanoseconds: 15_000_000)
        }
        // Report the relay's own note on failure — an escalation carries the
        // reason, and asserting on status alone throws that away.
        XCTAssertEqual(settled?.status, .done,
                       "the stubbed PM turn always returns verdict: done — note: \(settled?.note ?? "nil")")

        // The thread must project the PM turn's settled text.
        let thread = store.get(relayId)
        let texts = (thread?.turns ?? []).map { $0.text ?? "<nil>" }
        XCTAssertTrue(texts.contains { $0.contains("Reviewed") },
                      "thread must project the PM turn's settled prose; got turns: \(texts)")
    }

    func testStartReturnsNilWhenInvalid() {
        let config = AppConfig.loadConfiguration()
        let vm = RelayLaunchViewModel(
            projectId: "prj_test", projectRoot: repoRoot(),
            models: config.models, registry: config.registry, readyModels: [])
        // No doc, no seats picked.
        XCTAssertNil(vm.start())
    }
}
