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
        let coordinatorFactory: (@escaping @Sendable () -> String) -> RelayCoordinator = { idFactory in
            RelayCoordinator(
                runService: RunService(
                    models: models, registry: registry, runStore: runStore,
                    commandRunner: DoneVerdictRunner()
                ),
                stateStore: stateStore,
                runStore: runStore,
                threadProjector: RelayThreadProjector(store: store, runStore: runStore),
                idFactory: idFactory
            )
        }
        return (coordinatorFactory, { RelayThreadProjector(store: store, runStore: runStore) })
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
        let config = AppConfig.loadConfiguration()
        // Seat only ENABLED workers. A disabled model can never dispatch
        // (WORKER_NOT_AVAILABLE), so seating one proves nothing about the relay —
        // it just re-tests the readiness gate through an escalation.
        let seatable = config.models.filter { ModelCatalog.isEnabled($0.id) }
        try XCTSkipIf(seatable.count < 2, "need two distinct ENABLED worker ids to seat PM + dev")
        let root = tempRoot("start")
        let factory = stubbedFactory(root: root, models: config.models, registry: config.registry)
        let vm = RelayLaunchViewModel(
            projectId: "prj_test", projectRoot: repoRoot(),
            models: config.models, registry: config.registry, readyModels: [],
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
