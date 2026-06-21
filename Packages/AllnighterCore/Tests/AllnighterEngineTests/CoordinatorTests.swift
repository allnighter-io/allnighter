import XCTest
import AllnighterCore
@testable import AllnighterEngine

/// Serve0: resident coordinator health seam — foregroundOnly when off, available
/// when a live pid is observed, unavailable for stale state.
final class CoordinatorHealthTests: XCTestCase {

    private func tempDirs() -> (URL, ResidentCoordinatorStore, ResidentCoordinatorProbe) {
        let root = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("coord-\(UUID().uuidString)")
        let coordDir = root.appendingPathComponent("Coordinator", isDirectory: true)
        let runsDir = root.appendingPathComponent("Runs", isDirectory: true)
        let store = ResidentCoordinatorStore(directory: coordDir)
        let probe = ResidentCoordinatorProbe(store: store, runsDirectory: runsDir)
        return (root, store, probe)
    }

    func testHealthForegroundOnlyWhenNoState() {
        let (root, _, probe) = tempDirs()
        defer { try? FileManager.default.removeItem(at: root) }

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
        defer { try? FileManager.default.removeItem(at: root) }

        let pid = ProcessInfo.processInfo.processIdentifier
        try store.save(.init(
            coordinatorId: "coord-test",
            pid: pid,
            startedAt: Date(timeIntervalSince1970: 1_700_000_000),
            loopbackHost: "127.0.0.1",
            loopbackPort: 18743,
            binaryVersion: "0.1.0",
            contractVersion: "1.0.0"
        ))

        let health = probe.health(binaryVersion: "0.1.0")
        XCTAssertEqual(health.state, .available)
        XCTAssertEqual(health.coordinatorId, "coord-test")
        XCTAssertEqual(health.pid, pid)
        XCTAssertTrue(health.loopback.listening)
        XCTAssertEqual(health.loopback.port, 18743)
        XCTAssertEqual(health.activeObligationCount, 0)
    }

    func testHealthUnavailableWhenPidIsDead() throws {
        let (root, store, probe) = tempDirs()
        defer { try? FileManager.default.removeItem(at: root) }

        try store.save(.init(
            coordinatorId: "stale",
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
        defer { try? FileManager.default.removeItem(at: root) }

        XCTAssertEqual(probe.doctorCoordinator().state, .foregroundOnly)

        try store.save(.init(
            coordinatorId: "live",
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

    func testResidentCoordinatorClearsStateOnShutdown() async throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("coord-run-\(UUID().uuidString)")
        let store = ResidentCoordinatorStore(directory: root.appendingPathComponent("Coordinator", isDirectory: true))
        defer { try? FileManager.default.removeItem(at: root) }

        let box = BoolBox()
        try await ResidentCoordinator(binaryVersion: "0.1.0", store: store).run(untilShutdown: {
            box.value = store.load() != nil
        })
        XCTAssertTrue(box.value)
        XCTAssertNil(store.load(), "clean shutdown clears durable coordinator state")
    }

    func testResidentCoordinatorRunsRemoteDependencyUntilShutdown() async throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("coord-remote-\(UUID().uuidString)")
        let store = ResidentCoordinatorStore(directory: root.appendingPathComponent("Coordinator", isDirectory: true))
        let remote = RecordingRemoteCoordinator()
        defer { try? FileManager.default.removeItem(at: root) }

        try await ResidentCoordinator(
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
        XCTAssertNil(store.load(), "clean shutdown clears durable coordinator state")
    }
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
