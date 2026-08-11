import XCTest
import AllnighterCore
@testable import AllnighterEngine

final class ServeHealthClientTests: XCTestCase {

    private func transportReturning(statusCode: Int, body: String) -> ServeHealthClient.Transport {
        return { _, _ in (Data(body.utf8), statusCode) }
    }

    private func transportThrowing(_ error: Error) -> ServeHealthClient.Transport {
        return { _, _ in throw error }
    }

    private func healthJSON(daemonId: String, pid: Int32) -> String {
        return """
        {"daemonId":"\(daemonId)","pid":\(pid),"state":"available"}
        """
    }

    // MARK: - ServeHealthClient (unit)

    func testClientSuccessWithMatchingFields() {
        let client = ServeHealthClient(transport: transportReturning(
            statusCode: 200, body: healthJSON(daemonId: "coord-1", pid: 42)))
        let result = client.probe(host: "127.0.0.1", port: 18743)
        guard case .success(let r) = result else {
            XCTFail("expected success, got \(result)")
            return
        }
        XCTAssertEqual(r.daemonId, "coord-1")
        XCTAssertEqual(r.pid, 42)
    }

    func testClientParsesPidAsInt() {
        let body = "{\"daemonId\":\"d\",\"pid\":99}"
        let client = ServeHealthClient(transport: transportReturning(statusCode: 200, body: body))
        guard case .success(let r) = client.probe(host: "127.0.0.1", port: 1) else {
            XCTFail("expected success")
            return
        }
        XCTAssertEqual(r.pid, 99)
    }

    func testClientRefusesNonLoopbackHost() {
        let client = ServeHealthClient(transport: transportReturning(statusCode: 200, body: "{}"))
        let result = client.probe(host: "192.168.1.1", port: 80)
        guard case .failure(let f) = result else {
            XCTFail("expected failure for non-loopback host")
            return
        }
        XCTAssertEqual(f, .nonLoopbackHost("192.168.1.1:80"))
    }

    func testClientRefusesNonLoopbackLocalhostVariantIsFine() {
        let client = ServeHealthClient(transport: transportReturning(
            statusCode: 200, body: healthJSON(daemonId: "d", pid: 1)))
        guard case .success = client.probe(host: "localhost", port: 18743) else {
            XCTFail("localhost should be accepted")
            return
        }
    }

    func testClientConnectionRefused() {
        let error = NSError(domain: NSURLErrorDomain, code: NSURLErrorCannotConnectToHost,
                            userInfo: [NSLocalizedDescriptionKey: "Connection refused"])
        let client = ServeHealthClient(transport: transportThrowing(error))
        let result = client.probe(host: "127.0.0.1", port: 18743)
        guard case .failure(let f) = result else {
            XCTFail("expected connection refused")
            return
        }
        XCTAssertEqual(f, .connectionRefused("127.0.0.1:18743"))
    }

    func testClientCannotFindHost() {
        let error = NSError(domain: NSURLErrorDomain, code: NSURLErrorCannotFindHost,
                            userInfo: nil)
        let client = ServeHealthClient(transport: transportThrowing(error))
        guard case .failure(.connectionRefused) = client.probe(host: "127.0.0.1", port: 1) else {
            XCTFail("expected connection refused for cannot find host")
            return
        }
    }

    func testClientTimeout() {
        let error = NSError(domain: NSURLErrorDomain, code: NSURLErrorTimedOut,
                            userInfo: nil)
        let client = ServeHealthClient(transport: transportThrowing(error))
        let result = client.probe(host: "127.0.0.1", port: 18743)
        guard case .failure(let f) = result else {
            XCTFail("expected timeout")
            return
        }
        XCTAssertEqual(f, .timeout("127.0.0.1:18743"))
    }

    func testClientNon200Status() {
        let client = ServeHealthClient(transport: transportReturning(statusCode: 503, body: "{}"))
        let result = client.probe(host: "127.0.0.1", port: 18743)
        guard case .failure(let f) = result else {
            XCTFail("expected non-200 failure")
            return
        }
        XCTAssertEqual(f, .non200Status(503, "127.0.0.1:18743"))
    }

    func testClientUnparseableBodyNotJSON() {
        let client = ServeHealthClient(transport: transportReturning(statusCode: 200, body: "not json"))
        let result = client.probe(host: "127.0.0.1", port: 18743)
        guard case .failure(let f) = result else {
            XCTFail("expected unparseable body")
            return
        }
        guard case .unparseableBody = f else {
            XCTFail("expected unparseableBody, got \(f)")
            return
        }
    }

    func testClientUnparseableBodyMissingDaemonId() {
        let client = ServeHealthClient(transport: transportReturning(statusCode: 200, body: "{\"pid\":1}"))
        let result = client.probe(host: "127.0.0.1", port: 18743)
        guard case .failure(let f) = result else {
            XCTFail("expected unparseable body")
            return
        }
        guard case .unparseableBody(let detail) = f else {
            XCTFail("expected unparseableBody, got \(f)")
            return
        }
        XCTAssertTrue(detail.contains("daemonId"))
    }

    func testClientUnparseableBodyMissingPid() {
        let client = ServeHealthClient(transport: transportReturning(statusCode: 200, body: "{\"daemonId\":\"d\"}"))
        let result = client.probe(host: "127.0.0.1", port: 18743)
        guard case .failure(let f) = result else {
            XCTFail("expected unparseable body")
            return
        }
        guard case .unparseableBody(let detail) = f else {
            XCTFail("expected unparseableBody, got \(f)")
            return
        }
        XCTAssertTrue(detail.contains("pid"))
    }

    func testClientGenericErrorBecomesConnectionRefused() {
        struct DummyError: Error {}
        let client = ServeHealthClient(transport: transportThrowing(DummyError()))
        let result = client.probe(host: "127.0.0.1", port: 18743)
        guard case .failure(.connectionRefused) = result else {
            XCTFail("expected connection refused for generic error, got \(result)")
            return
        }
    }

    // MARK: - ServeDaemonProbe active probe integration

    private func tempDirs() -> (URL, ServeDaemonStore) {
        let root = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("hc-\(UUID().uuidString)")
        let coordDir = root.appendingPathComponent("Coordinator", isDirectory: true)
        let store = ServeDaemonStore(directory: coordDir)
        return (root, store)
    }

    private func saveRecord(to store: ServeDaemonStore,
                            daemonId: String = "coord-test",
                            pid: Int32 = 42,
                            port: UInt16 = 18743) throws {
        try store.save(.init(
            daemonId: daemonId,
            pid: pid,
            startedAt: Date(timeIntervalSince1970: 1_700_000_000),
            loopbackHost: "127.0.0.1",
            loopbackPort: port,
            binaryVersion: "0.1.0",
            contractVersion: "1.0.0"
        ))
    }

    func testProbeReportsListeningOnMatchingResponse() throws {
        let (root, store) = tempDirs()
        defer { removeIfPresent(root) }
        try saveRecord(to: store, daemonId: "coord-test", pid: 42)

        let client = ServeHealthClient(transport: transportReturning(
            statusCode: 200, body: healthJSON(daemonId: "coord-test", pid: 42)))
        let probe = ServeDaemonProbe(store: store, runsDirectory: root.appendingPathComponent("Runs", isDirectory: true),
                                     processAlive: { $0 == 42 ? true : false })
        let health = probe.health(binaryVersion: "0.1.0", healthClient: client)
        XCTAssertEqual(health.state, .available)
        XCTAssertTrue(health.loopback.listening)
        XCTAssertNil(health.loopback.detail)
    }

    func testProbeReportsNotListeningOnConnectionRefused() throws {
        let (root, store) = tempDirs()
        defer { removeIfPresent(root) }
        try saveRecord(to: store)

        let error = NSError(domain: NSURLErrorDomain, code: NSURLErrorCannotConnectToHost, userInfo: nil)
        let client = ServeHealthClient(transport: transportThrowing(error))
        let probe = ServeDaemonProbe(store: store, runsDirectory: root.appendingPathComponent("Runs", isDirectory: true),
                                     processAlive: { $0 == 42 ? true : false })
        let health = probe.health(binaryVersion: "0.1.0", healthClient: client)
        XCTAssertEqual(health.state, .available)
        XCTAssertFalse(health.loopback.listening)
        XCTAssertEqual(health.loopback.detail, "connection refused at 127.0.0.1:18743")
    }

    func testProbeReportsNotListeningOnTimeout() throws {
        let (root, store) = tempDirs()
        defer { removeIfPresent(root) }
        try saveRecord(to: store)

        let error = NSError(domain: NSURLErrorDomain, code: NSURLErrorTimedOut, userInfo: nil)
        let client = ServeHealthClient(transport: transportThrowing(error))
        let probe = ServeDaemonProbe(store: store, runsDirectory: root.appendingPathComponent("Runs", isDirectory: true),
                                     processAlive: { $0 == 42 ? true : false })
        let health = probe.health(binaryVersion: "0.1.0", healthClient: client)
        XCTAssertFalse(health.loopback.listening)
        XCTAssertEqual(health.loopback.detail, "timeout at 127.0.0.1:18743")
    }

    func testProbeReportsNotListeningOnNon200() throws {
        let (root, store) = tempDirs()
        defer { removeIfPresent(root) }
        try saveRecord(to: store)

        let client = ServeHealthClient(transport: transportReturning(statusCode: 500, body: "{}"))
        let probe = ServeDaemonProbe(store: store, runsDirectory: root.appendingPathComponent("Runs", isDirectory: true),
                                     processAlive: { $0 == 42 ? true : false })
        let health = probe.health(binaryVersion: "0.1.0", healthClient: client)
        XCTAssertFalse(health.loopback.listening)
        XCTAssertEqual(health.loopback.detail, "HTTP 500 at 127.0.0.1:18743")
    }

    func testProbeReportsNotListeningOnUnparseableBody() throws {
        let (root, store) = tempDirs()
        defer { removeIfPresent(root) }
        try saveRecord(to: store)

        let client = ServeHealthClient(transport: transportReturning(statusCode: 200, body: "garbage"))
        let probe = ServeDaemonProbe(store: store, runsDirectory: root.appendingPathComponent("Runs", isDirectory: true),
                                     processAlive: { $0 == 42 ? true : false })
        let health = probe.health(binaryVersion: "0.1.0", healthClient: client)
        XCTAssertFalse(health.loopback.listening)
        XCTAssertTrue(health.loopback.detail?.contains("unparseable body") ?? false)
    }

    func testProbeReportsNotListeningOnDaemonIdMismatch() throws {
        let (root, store) = tempDirs()
        defer { removeIfPresent(root) }
        try saveRecord(to: store, daemonId: "coord-test", pid: 42)

        let client = ServeHealthClient(transport: transportReturning(
            statusCode: 200, body: healthJSON(daemonId: "other-daemon", pid: 42)))
        let probe = ServeDaemonProbe(store: store, runsDirectory: root.appendingPathComponent("Runs", isDirectory: true),
                                     processAlive: { $0 == 42 ? true : false })
        let health = probe.health(binaryVersion: "0.1.0", healthClient: client)
        XCTAssertFalse(health.loopback.listening)
        XCTAssertTrue(health.loopback.detail?.contains("daemonId mismatch") ?? false)
        XCTAssertTrue(health.loopback.detail?.contains("other-daemon") ?? false)
    }

    func testProbeReportsNotListeningOnPidMismatchRecycledPid() throws {
        let (root, store) = tempDirs()
        defer { removeIfPresent(root) }
        try saveRecord(to: store, daemonId: "coord-test", pid: 42)

        let client = ServeHealthClient(transport: transportReturning(
            statusCode: 200, body: healthJSON(daemonId: "coord-test", pid: 999)))
        let probe = ServeDaemonProbe(store: store, runsDirectory: root.appendingPathComponent("Runs", isDirectory: true),
                                     processAlive: { $0 == 42 ? true : false })
        let health = probe.health(binaryVersion: "0.1.0", healthClient: client)
        XCTAssertFalse(health.loopback.listening)
        XCTAssertTrue(health.loopback.detail?.contains("pid mismatch") ?? false)
        XCTAssertTrue(health.loopback.detail?.contains("recycled pid") ?? false)
    }

    func testProbeReportsNotListeningOnBothMismatch() throws {
        let (root, store) = tempDirs()
        defer { removeIfPresent(root) }
        try saveRecord(to: store, daemonId: "coord-test", pid: 42)

        let client = ServeHealthClient(transport: transportReturning(
            statusCode: 200, body: healthJSON(daemonId: "alien", pid: 77)))
        let probe = ServeDaemonProbe(store: store, runsDirectory: root.appendingPathComponent("Runs", isDirectory: true),
                                     processAlive: { $0 == 42 ? true : false })
        let health = probe.health(binaryVersion: "0.1.0", healthClient: client)
        XCTAssertFalse(health.loopback.listening)
        XCTAssertTrue(health.loopback.detail?.contains("daemonId mismatch") ?? false)
        XCTAssertTrue(health.loopback.detail?.contains("pid mismatch") ?? false)
    }

    func testLivePidWithNothingListeningReportsNotListening() throws {
        let (root, store) = tempDirs()
        defer { removeIfPresent(root) }
        try saveRecord(to: store)

        let error = NSError(domain: NSURLErrorDomain, code: NSURLErrorCannotConnectToHost, userInfo: nil)
        let client = ServeHealthClient(transport: transportThrowing(error))
        let probe = ServeDaemonProbe(store: store, runsDirectory: root.appendingPathComponent("Runs", isDirectory: true),
                                     processAlive: { _ in true }) // live pid
        let health = probe.health(binaryVersion: "0.1.0", healthClient: client)
        XCTAssertFalse(health.loopback.listening, "live pid alone must not set listening: true")
        XCTAssertEqual(health.loopback.detail, "connection refused at 127.0.0.1:18743")
    }

    func testProbeWithoutHealthClientKeepsOldBehavior() throws {
        let (root, store) = tempDirs()
        defer { removeIfPresent(root) }
        try saveRecord(to: store)

        let probe = ServeDaemonProbe(store: store, runsDirectory: root.appendingPathComponent("Runs", isDirectory: true),
                                     processAlive: { _ in true })
        let health = probe.health(binaryVersion: "0.1.0")
        XCTAssertEqual(health.state, .available)
        XCTAssertTrue(health.loopback.listening, "nil healthClient preserves legacy listening: true for daemon self-report")
        XCTAssertNil(health.loopback.detail)
    }

    func testCLIPathTransportIsInvokedProofActiveProbeNotNilDefault() throws {
        let (root, store) = tempDirs()
        defer { removeIfPresent(root) }
        try saveRecord(to: store, daemonId: "coord-test", pid: 42)

        let counter = TransportInvocationCounter()
        let body = Data(#"{"daemonId":"coord-test","pid":42}"#.utf8)
        let client = ServeHealthClient(transport: { _, _ in
            counter.invoke()
            return (body, 200)
        })
        let probe = ServeDaemonProbe(store: store, runsDirectory: root.appendingPathComponent("Runs", isDirectory: true),
                                     processAlive: { _ in true })
        let health = probe.health(binaryVersion: "0.1.0", healthClient: client)

        XCTAssertTrue(counter.wasInvoked,
                      "CLI serve health path must invoke transport (active probe), not default to nil healthClient")
        XCTAssertTrue(health.loopback.listening, "active probe succeeded — daemon should report listening: true")
    }

    func testProbeWithClientDoesNotFallThroughToOldBehavior() throws {
        let (root, store) = tempDirs()
        defer { removeIfPresent(root) }
        try saveRecord(to: store)

        let error = NSError(domain: NSURLErrorDomain, code: NSURLErrorCannotConnectToHost, userInfo: nil)
        let client = ServeHealthClient(transport: transportThrowing(error))
        let probe = ServeDaemonProbe(store: store, runsDirectory: root.appendingPathComponent("Runs", isDirectory: true),
                                     processAlive: { _ in true })
        let health = probe.health(binaryVersion: "0.1.0", healthClient: client)
        XCTAssertFalse(health.loopback.listening, "with healthClient, listening must come from active probe, not pid")
    }

    func testProbeNonLoopbackHostRefusedInClient() {
        let client = ServeHealthClient(transport: transportReturning(statusCode: 200, body: "{}"))
        let result = client.probe(host: "10.0.0.1", port: 1234)
        guard case .failure(let f) = result else {
            XCTFail("expected nonLoopbackHost failure")
            return
        }
        XCTAssertEqual(f, .nonLoopbackHost("10.0.0.1:1234"))
    }
}

private final class TransportInvocationCounter: @unchecked Sendable {
    private(set) var wasInvoked = false
    func invoke() { wasInvoked = true }
}

private func removeIfPresent(_ url: URL) {
    guard FileManager.default.fileExists(atPath: url.path) else { return }
    try? FileManager.default.removeItem(at: url)
}
