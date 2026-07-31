import XCTest
import AllnighterCore
@testable import AllnighterEngine

/// `alln serve` daemon health seam — foregroundOnly when off, available when a
/// live pid is observed, unavailable for stale state. There is no transport to
/// report on: Code Red deleted it, so health is the record plus pid liveness.
final class CoordinatorHealthTests: XCTestCase {

    private func tempDirs() -> (URL, ServeDaemonStore, ServeDaemonProbe) {
        let root = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("coord-\(UUID().uuidString)")
        let coordDir = root.appendingPathComponent("Coordinator", isDirectory: true)
        let runsDir = root.appendingPathComponent("Runs", isDirectory: true)
        let store = ServeDaemonStore(directory: coordDir)
        let probe = ServeDaemonProbe(store: store, runsDirectory: runsDir)
        return (root, store, probe)
    }

    func testHealthForegroundOnlyWhenNoState() {
        let (root, _, probe) = tempDirs()
        defer { removeIfPresent(root) }

        let health = probe.health(binaryVersion: "0.1.0")
        XCTAssertEqual(health.state, .foregroundOnly)
        XCTAssertNil(health.pid)
        XCTAssertEqual(health.activeObligationCount, 0)
        XCTAssertFalse(health.loopback.listening)
        XCTAssertTrue(health.journal.incrementalDurable)
        XCTAssertTrue(health.journal.orphanRecovery)
    }


    func testHealthAvailableWhenLivePidMatches() throws {
        let (root, store, probe) = tempDirs()
        defer { removeIfPresent(root) }

        let pid = ProcessInfo.processInfo.processIdentifier
        try store.save(.init(
            daemonId: "coord-test",
            pid: pid,
            startedAt: Date(timeIntervalSince1970: 1_700_000_000),
            loopbackHost: "127.0.0.1",
            loopbackPort: 18743,
            binaryVersion: "0.1.0",
            contractVersion: "1.0.0"
        ))

        let health = probe.health(binaryVersion: "0.1.0")
        XCTAssertEqual(health.state, .available)
        XCTAssertEqual(health.daemonId, "coord-test")
        XCTAssertEqual(health.pid, pid)
        XCTAssertTrue(health.loopback.listening)
        XCTAssertEqual(health.loopback.port, 18743)
        XCTAssertEqual(health.activeObligationCount, 0)
    }

    func testHealthCountsNonTerminalRunsAsObligations() throws {
        let (root, store, probe) = tempDirs()
        defer { removeIfPresent(root) }
        let runs = RunStore(rootDirectory: root.appendingPathComponent("Runs", isDirectory: true))
        try runs.save(TeamRun(id: "active", prompt: "work", status: .running, createdAt: Date()), models: [])
        try runs.save(TeamRun(id: "finished", prompt: "done", status: .complete, createdAt: Date()), models: [])
        try store.save(.init(
            daemonId: "coord-test",
            pid: ProcessInfo.processInfo.processIdentifier,
            startedAt: Date(),
            loopbackHost: "127.0.0.1",
            loopbackPort: 18743,
            binaryVersion: "0.1.0",
            contractVersion: "1.0.0"
        ))

        XCTAssertEqual(probe.health(binaryVersion: "0.1.0").activeObligationCount, 1)
    }

    func testHealthUnavailableWhenPidIsDead() throws {
        let (root, store, probe) = tempDirs()
        defer { removeIfPresent(root) }

        try store.save(.init(
            daemonId: "stale",
            pid: 2_000_000,
            startedAt: Date(timeIntervalSince1970: 1_700_000_000),
            loopbackHost: "127.0.0.1",
            loopbackPort: 18743,
            binaryVersion: "0.1.0",
            contractVersion: "1.0.0"
        ))

        let health = probe.health(binaryVersion: "0.1.0")
        XCTAssertEqual(health.state, .unavailable)
        XCTAssertEqual(health.pid, 2_000_000)
        XCTAssertFalse(health.loopback.listening)
    }

    func testDoctorCoordinatorMapsStates() throws {
        let (root, store, probe) = tempDirs()
        defer { removeIfPresent(root) }

        XCTAssertEqual(probe.doctorCoordinator().state, .foregroundOnly)

        try store.save(.init(
            daemonId: "live",
            pid: ProcessInfo.processInfo.processIdentifier,
            startedAt: Date(),
            loopbackHost: "127.0.0.1",
            loopbackPort: 1,
            binaryVersion: "0.1.0",
            contractVersion: "1.0.0"
        ))
        XCTAssertEqual(probe.doctorCoordinator().state, .available)
        XCTAssertTrue(probe.doctorCoordinator().available)
    }

    func testCoordinatorHealthSchemaMatchesType() throws {
        let (_, _, probe) = tempDirs()
        let health = probe.health(binaryVersion: "0.1.0")
        let schema = ContractSchema.coordinatorHealthSchema()
        let props = try XCTUnwrap(schema["properties"] as? [String: Any])
        XCTAssertEqual(Set(props.keys), Set(Mirror(reflecting: health).children.compactMap(\.label)))
    }
}

final class CoordinatorRunTests: XCTestCase {

    override func setUp() {
        super.setUp()
        ServerAcceptLoopTestGate.enter()
    }

    override func tearDown() {
        ServerAcceptLoopTestGate.exit()
        super.tearDown()
    }

    func testLoopbackHealthServerResponds() throws {
        let server = LoopbackHealthServer()
        defer { server.stop() }
        let port = try server.start { "{\"ok\":true}" }
        XCTAssertGreaterThan(port, 0)

        let box = StringBox()
        let exp = expectation(description: "health")
        URLSession.shared.dataTask(with: URL(string: "http://127.0.0.1:\(port)/health")!) { data, _, _ in
            box.value = String(decoding: data ?? Data(), as: UTF8.self)
            exp.fulfill()
        }.resume()
        wait(for: [exp], timeout: 2)
        XCTAssertEqual(box.value, "{\"ok\":true}")
    }

    func testLoopbackHealthServerStopStartCycle() throws {
        let server = LoopbackHealthServer()
        let port1 = try server.start { "{\"v\":1}" }
        server.stop()
        let port2 = try server.start { "{\"v\":2}" }
        XCTAssertGreaterThan(port2, 0)

        let box = StringBox()
        let exp = expectation(description: "health-after-restart")
        URLSession.shared.dataTask(with: URL(string: "http://127.0.0.1:\(port2)/health")!) { data, _, _ in
            box.value = String(decoding: data ?? Data(), as: UTF8.self)
            exp.fulfill()
        }.resume()
        wait(for: [exp], timeout: 2)
        XCTAssertEqual(box.value, "{\"v\":2}")
        XCTAssertNotEqual(port1, port2)
        server.stop()
    }

    func testServeDaemonClearsStateOnShutdown() async throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("coord-run-\(UUID().uuidString)")
        let store = ServeDaemonStore(directory: root.appendingPathComponent("Coordinator", isDirectory: true))
        defer { removeIfPresent(root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)

        let box = BoolBox()
        try await ServeDaemon(binaryVersion: "0.1.0", store: store).run(untilShutdown: {
            box.value = store.load() != nil
        })
        XCTAssertTrue(box.value)
        XCTAssertNil(store.load(), "clean shutdown clears durable daemon state")
    }



    func testServeDaemonRunsRemoteDependencyUntilShutdown() async throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("coord-remote-\(UUID().uuidString)")
        let store = ServeDaemonStore(directory: root.appendingPathComponent("Coordinator", isDirectory: true))
        let remote = RecordingRemoteCoordinator()
        defer { removeIfPresent(root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)

        try await ServeDaemon(
            binaryVersion: "0.1.0",
            store: store,
            remoteDependencies: .init(coordinator: remote)
        ).run(untilShutdown: {
            while !remote.started {
                try? await Task.sleep(nanoseconds: 1_000_000)
            }
        })

        XCTAssertTrue(remote.started)
        XCTAssertTrue(remote.sawCancellation)
        XCTAssertNil(store.load(), "clean shutdown clears durable daemon state")
    }

    func testServeDaemonRunsPMTurnWakeScheduler() async throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("coord-pm-turn-wake-\(UUID().uuidString)")
        defer { removeIfPresent(root) }
        let runs = root.appendingPathComponent("Runs", isDirectory: true)
        let turn = PMTurnJSON(
            kind: .run, subjectId: "run_wake", sequence: 1, createdAt: Date(),
            reason: "done", lifecycleStatus: "done", report: "done", nextCommands: [])
        let expectedPayload = try CoreJSON.encode(turn)
        try PMTurnStore(runsRootDirectory: runs).save(turn)
        let config = PMTurnWakeConfigurationStore(fileURL: root.appendingPathComponent("config.json"))
        try config.save(.init(pmTurnWake: .init(command: ["/receiver"])))
        let invoked = BoolBox()
        let scheduler = PMTurnWakeScheduler(
            runsRootDirectory: runs,
            loopsRootDirectory: root.appendingPathComponent("Loops", isDirectory: true),
            configurationStore: config,
            ledgerStore: .init(fileURL: root.appendingPathComponent("ledger.json")),
            invoke: { _, stdin in
                invoked.value = stdin == expectedPayload
                return .init(succeeded: true)
            },
            pollInterval: 0.01
        )

        try await ServeDaemon(
            binaryVersion: "0.1.0",
            store: ServeDaemonStore(directory: root.appendingPathComponent("Coordinator", isDirectory: true)),
            pmTurnWakeScheduler: scheduler
        ).run(untilShutdown: {
            while !invoked.value {
                try? await Task.sleep(nanoseconds: 1_000_000)
            }
        })

        XCTAssertTrue(invoked.value)
    }
}

/// Deletes a temp root only when it is actually there.
///
/// A `try? FileManager.removeItem(...)` in a `defer` is not inert when it FAILS:
/// if the test method is already unwinding with an error, the failed remove
/// replaces the error XCTest reports with `NSCocoaErrorDomain 4 "couldn't be
/// removed"`. Verified both ways in a standalone XCTest target: a remove that
/// succeeds masks nothing, and an in-function `do/catch` still sees the original
/// error — it is XCTest's *reported* error that gets replaced. That mask cost a
/// full misdiagnosis here (a "teardown race" that never existed) while the real
/// failure was the coordinator's `unsafePath`, thrown because the scoped
/// rendezvous parent did not exist. Never reintroduce the unguarded form.
///
/// Cleanup itself is deliberately best-effort: a temp root that survives under
/// `NSTemporaryDirectory()` is not a test failure, so the guarded remove still
/// discards a genuine removal error. If that ever needs to be visible, report it
/// from `addTeardownBlock`, which runs outside the error-propagation window.
private func removeIfPresent(_ url: URL) {
    guard FileManager.default.fileExists(atPath: url.path) else { return }
    try? FileManager.default.removeItem(at: url)
}

private final class StringBox: @unchecked Sendable {
    private let lock = NSLock()
    private var stored = ""
    var value: String {
        get { lock.withLock { stored } }
        set { lock.withLock { stored = newValue } }
    }
}

private final class BoolBox: @unchecked Sendable {
    private let lock = NSLock()
    private var stored = false
    var value: Bool {
        get { lock.withLock { stored } }
        set { lock.withLock { stored = newValue } }
    }
}

private final class RecordingRemoteCoordinator: RemoteMacAgentCoordinating, @unchecked Sendable {
    private let lock = NSLock()
    private var storedStarted = false
    private var storedSawCancellation = false

    var started: Bool {
        lock.withLock { storedStarted }
    }

    var sawCancellation: Bool {
        lock.withLock { storedSawCancellation }
    }

    func run(isCancelled: @escaping @Sendable () -> Bool) async {
        lock.withLock { storedStarted = true }
        while !isCancelled() && !Task.isCancelled {
            try? await Task.sleep(nanoseconds: 1_000_000)
        }
        lock.withLock { storedSawCancellation = true }
    }
}

private extension NSLock {
    func withLock<T>(_ body: () -> T) -> T {
        lock()
        defer { unlock() }
        return body()
    }
}
