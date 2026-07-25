import XCTest
import AllnighterCore
import AllnighterEngine
@testable import AllnighterMac

/// R-S08 — resume-from-GUI. `RelayResumeController.resume` must route through
/// `RelayCoordinator.resume` (same construction path as launch), never a normal chat
/// turn, and must refuse an empty answer or a relay that isn't actually resumable.
@MainActor
final class RelayResumeControllerTests: XCTestCase {
    private struct DoneVerdictRunner: CommandRunner {
        func run(command: String, args: [String], stdin: String?, env: [String: String],
                  workingDirectory: String?, timeout: Duration) async -> CommandResult {
            CommandResult(stdout: """
            Answered.
            ```json
            {"verdict":"done","note":"Resolved."}
            ```
            """, exitCode: 0)
        }
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

    private func tempRoot(_ label: String) -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("alln-relay-resume-\(label)-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func stubbedFactory(root: URL, models: [Model], registry: DriverRegistry)
        -> (@escaping @Sendable () -> String) -> RelayCoordinator {
        let store = ThreadStore(rootDirectory: root.appendingPathComponent("threads", isDirectory: true))
        let runStore = RunStore(rootDirectory: root.appendingPathComponent("runs", isDirectory: true))
        let stateStore = RelayStateStore(rootDirectory: root.appendingPathComponent("relay", isDirectory: true))
        let stubDriverIdValue = Self.stubDriverId
        return { idFactory in
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
    }

    /// A directly-persisted `.escalated` `RelayState` — the shape a real escalated round
    /// leaves behind (`RelayCoordinator.escalate`), written straight to the store so the
    /// test doesn't need a full round to reach it.
    private func seedEscalated(
        id: String, root: URL, projectRoot: String, pmWorkerId: String, devWorkerId: String
    ) -> RelayStateStore {
        let stateStore = RelayStateStore(rootDirectory: root.appendingPathComponent("relay", isDirectory: true))
        let state = RelayState(
            id: id, projectRoot: projectRoot, docPath: "docs/spec.md",
            pmWorkerId: pmWorkerId, devWorkerId: devWorkerId, status: .escalated,
            createdAt: Date(), note: "76/77 or 88 — say which?"
        )
        try? stateStore.save(state)
        return stateStore
    }

    private func repoRoot() -> String {
        let url = tempRoot("repo")
        return url.path
    }

    // MARK: - Eligibility

    func testCanResumeTrueForEscalatedFalseForUnknown() {
        let root = tempRoot("eligibility")
        let stateStore = seedEscalated(
            id: "relay_a", root: root, projectRoot: repoRoot(),
            pmWorkerId: "pm", devWorkerId: "dev")
        let controller = RelayResumeController(
            makeCoordinator: stubbedFactory(root: root, models: [], registry: DriverRegistry()),
            stateStore: stateStore
        )
        XCTAssertTrue(controller.canResume(relayId: "relay_a"))
        XCTAssertFalse(controller.canResume(relayId: "relay_does_not_exist"))
    }

    func testCanResumeFalseForDoneRelay() {
        let root = tempRoot("done")
        let stateStore = RelayStateStore(rootDirectory: root.appendingPathComponent("relay", isDirectory: true))
        let state = RelayState(
            id: "relay_done", projectRoot: repoRoot(), docPath: "docs/spec.md",
            pmWorkerId: "pm", devWorkerId: "dev", status: .done, createdAt: Date())
        try? stateStore.save(state)
        let controller = RelayResumeController(
            makeCoordinator: stubbedFactory(root: root, models: [], registry: DriverRegistry()),
            stateStore: stateStore
        )
        XCTAssertFalse(controller.canResume(relayId: "relay_done"), "a done relay is never resumable")
    }

    // MARK: - Resume routing

    func testResumeRefusesEmptyAnswer() {
        let root = tempRoot("empty")
        let stateStore = seedEscalated(
            id: "relay_b", root: root, projectRoot: repoRoot(),
            pmWorkerId: "pm", devWorkerId: "dev")
        let controller = RelayResumeController(
            makeCoordinator: stubbedFactory(root: root, models: [], registry: DriverRegistry()),
            stateStore: stateStore
        )
        XCTAssertFalse(controller.resume(relayId: "relay_b", answer: "   "))
        XCTAssertFalse(controller.isResuming("relay_b"))
    }

    func testResumeRefusesIneligibleRelay() {
        let root = tempRoot("ineligible")
        let controller = RelayResumeController(
            makeCoordinator: stubbedFactory(root: root, models: [], registry: DriverRegistry()),
            stateStore: RelayStateStore(rootDirectory: root.appendingPathComponent("relay", isDirectory: true))
        )
        XCTAssertFalse(controller.resume(relayId: "relay_never_existed", answer: "76/77"))
    }

    /// End-to-end: an escalated relay resumed with a real answer routes through
    /// `RelayCoordinator.resume` and reaches `done` via the stubbed PM turn — proving the
    /// wiring dispatches through the coordinator, not a normal chat send (there is no
    /// chat path in this test's stores at all).
    func testResumeRoutesThroughCoordinatorAndReachesDone() async throws {
        let seatable = stubWorkers()
        let root = tempRoot("full")
        let relayId = "relay_full_\(UUID().uuidString)"
        let stateStore = seedEscalated(
            id: relayId, root: root, projectRoot: repoRoot(),
            pmWorkerId: seatable[0].id, devWorkerId: seatable[1].id)
        let controller = RelayResumeController(
            makeCoordinator: stubbedFactory(root: root, models: seatable, registry: stubRegistry()),
            stateStore: stateStore
        )

        XCTAssertTrue(controller.resume(relayId: relayId, answer: "Go with 88."))
        XCTAssertTrue(controller.isResuming(relayId))

        // The seed state is ALREADY `.escalated` — wait for the stubbed PM turn's `done`
        // verdict specifically (not merely "no longer .running"), since the pre-resume
        // status would otherwise satisfy a weaker check on the very first poll.
        var settled: RelayState?
        for _ in 0..<200 {
            if let state = stateStore.load(id: relayId), state.status == .done {
                settled = state; break
            }
            try await Task.sleep(nanoseconds: 15_000_000)
        }
        XCTAssertEqual(settled?.status, .done, "note: \(settled?.note ?? "nil")")

        // Disk settles a beat before `RelayResumeController` clears its in-flight flag
        // (the flag clears only once `coordinator.resume`'s `await` actually returns
        // control) — poll briefly rather than asserting on the exact same tick.
        for _ in 0..<50 {
            if !controller.isResuming(relayId) { break }
            try await Task.sleep(nanoseconds: 15_000_000)
        }
        XCTAssertFalse(controller.isResuming(relayId))
    }
}
