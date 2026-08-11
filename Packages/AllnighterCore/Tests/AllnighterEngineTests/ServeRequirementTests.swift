import XCTest
import AllnighterCore
@testable import AllnighterEngine

/// ASR-S04a — `ServeRequirement` is the only product refusal for serve
/// unhealth, and it observes the active handshake (never pid/plist alone).
final class ServeRequirementTests: XCTestCase {

    private func tempDirs() -> (root: URL, store: ServeDaemonStore, runs: URL) {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("serve-requirement-\(UUID().uuidString)", isDirectory: true)
        let coordDir = root.appendingPathComponent("Coordinator", isDirectory: true)
        let runsDir = root.appendingPathComponent("Runs", isDirectory: true)
        try? FileManager.default.createDirectory(at: coordDir, withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(at: runsDir, withIntermediateDirectories: true)
        return (root, ServeDaemonStore(directory: coordDir), runsDir)
    }

    private func removeIfPresent(_ url: URL) {
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        try? FileManager.default.removeItem(at: url)
    }

    private func healthJSON(daemonId: String, pid: Int32) -> String {
        """
        {"daemonId":"\(daemonId)","pid":\(pid)}
        """
    }

    private func transportReturning(statusCode: Int, body: String) -> ServeHealthClient.Transport {
        { _, _ in (Data(body.utf8), statusCode) }
    }

    private func transportThrowing(_ error: Error) -> ServeHealthClient.Transport {
        { _, _ in throw error }
    }

    // MARK: - Healthy handshake

    func testRequireSucceedsWhenHandshakeMatches() throws {
        let (root, store, runs) = tempDirs()
        defer { removeIfPresent(root) }
        let pid: Int32 = 4242
        try store.save(.init(
            daemonId: "daemon-ok",
            pid: pid,
            startedAt: Date(),
            loopbackHost: "127.0.0.1",
            loopbackPort: 18743,
            binaryVersion: "0.1.0",
            contractVersion: "1.0.0"
        ))
        let probe = ServeDaemonProbe(
            store: store,
            runsDirectory: runs,
            processAlive: { $0 == pid }
        )
        let client = ServeHealthClient(transport: transportReturning(
            statusCode: 200,
            body: healthJSON(daemonId: "daemon-ok", pid: pid)
        ))
        let requirement = ServeRequirement(
            probe: probe, healthClient: client, binaryVersion: "0.1.0"
        )

        let result = requirement.require(reason: "pmTurnWake")
        guard case .success = result else {
            return XCTFail("expected success, got \(result)")
        }
    }

    // MARK: - Live pid, nothing listening still refuses

    func testRequireRefusesLivePidWithNothingListening() throws {
        let (root, store, runs) = tempDirs()
        defer { removeIfPresent(root) }
        let pid: Int32 = 99
        try store.save(.init(
            daemonId: "daemon-dead-port",
            pid: pid,
            startedAt: Date(),
            loopbackHost: "127.0.0.1",
            loopbackPort: 18743,
            binaryVersion: "0.1.0",
            contractVersion: "1.0.0"
        ))
        let probe = ServeDaemonProbe(
            store: store,
            runsDirectory: runs,
            processAlive: { $0 == pid } // live pid
        )
        let error = NSError(
            domain: NSURLErrorDomain,
            code: NSURLErrorCannotConnectToHost,
            userInfo: nil
        )
        let client = ServeHealthClient(transport: transportThrowing(error))
        let requirement = ServeRequirement(
            probe: probe, healthClient: client, binaryVersion: "0.1.0"
        )

        let result = requirement.require(reason: "pmTurnWake")
        guard case .failure(let refusal) = result else {
            return XCTFail("live pid without handshake must refuse")
        }
        XCTAssertEqual(refusal.code, ServeRequirement.errorCode)
        XCTAssertTrue(
            refusal.observedState.contains("available_not_listening")
                || refusal.observedState.contains("not listening"),
            "observed: \(refusal.observedState)"
        )
        XCTAssertTrue(refusal.message.contains(ServeRequirement.recoveryCommand))
        XCTAssertEqual(refusal.recoveryCommand, ServeRequirement.recoveryCommand)
        XCTAssertEqual(refusal.health.state, .available)
        XCTAssertFalse(refusal.health.loopback.listening)
        XCTAssertFalse(refusal.health.loopback.listening, "must not treat pid as health")
    }

    func testRequireRefusesForegroundOnly() {
        let (root, store, runs) = tempDirs()
        defer { removeIfPresent(root) }
        let probe = ServeDaemonProbe(store: store, runsDirectory: runs)
        // No socket opened — transport unused when no record exists.
        let client = ServeHealthClient(transport: transportReturning(statusCode: 200, body: "{}"))
        let requirement = ServeRequirement(
            probe: probe, healthClient: client, binaryVersion: "0.1.0"
        )

        let result = requirement.require(reason: "pendingWake")
        guard case .failure(let refusal) = result else {
            return XCTFail("foregroundOnly must refuse")
        }
        XCTAssertEqual(refusal.observedState, "foregroundOnly")
        XCTAssertTrue(refusal.message.contains("alln serve repair"))
    }

    func testRequireRefusesDeadPidUnavailable() throws {
        let (root, store, runs) = tempDirs()
        defer { removeIfPresent(root) }
        try store.save(.init(
            daemonId: "stale",
            pid: 2_000_000,
            startedAt: Date(),
            loopbackHost: "127.0.0.1",
            loopbackPort: 18743,
            binaryVersion: "0.1.0",
            contractVersion: "1.0.0"
        ))
        let probe = ServeDaemonProbe(
            store: store,
            runsDirectory: runs,
            processAlive: { _ in false }
        )
        let client = ServeHealthClient(transport: transportReturning(
            statusCode: 200, body: healthJSON(daemonId: "stale", pid: 2_000_000)
        ))
        let requirement = ServeRequirement(
            probe: probe, healthClient: client, binaryVersion: "0.1.0"
        )

        guard case .failure(let refusal) = requirement.require(reason: "vendorBackoff") else {
            return XCTFail("dead pid must refuse")
        }
        XCTAssertEqual(refusal.observedState, "unavailable")
    }

    // MARK: - Deferred write: store unchanged on refusal

    func testDeferredWriteRefusesAndWritesNothing() throws {
        let (root, store, runs) = tempDirs()
        defer { removeIfPresent(root) }
        // Unhealthy: no daemon record.
        let probe = ServeDaemonProbe(store: store, runsDirectory: runs)
        let client = ServeHealthClient(transport: transportReturning(statusCode: 200, body: "{}"))
        let requirement = ServeRequirement(
            probe: probe, healthClient: client, binaryVersion: "0.1.0"
        )

        // Stand-in for a deferred-obligation store (wake ticket / park / etc.).
        let ticketURL = root.appendingPathComponent("wake-ticket.json")
        let before = try? Data(contentsOf: ticketURL)
        XCTAssertNil(before, "store must start empty")

        var writeCalled = false
        let result = try requirement.writeIfHealthy(reason: "pmTurnWake") {
            writeCalled = true
            try Data("queued".utf8).write(to: ticketURL, options: .atomic)
            return true
        }

        guard case .failure = result else {
            return XCTFail("unhealthy serve must refuse deferred write")
        }
        XCTAssertFalse(writeCalled, "write must not run when handshake fails")
        XCTAssertFalse(
            FileManager.default.fileExists(atPath: ticketURL.path),
            "refused deferred write must leave the store unchanged"
        )
        let after = try? Data(contentsOf: ticketURL)
        XCTAssertNil(after)
    }

    func testDeferredWriteRunsWhenHealthy() throws {
        let (root, store, runs) = tempDirs()
        defer { removeIfPresent(root) }
        let pid: Int32 = 7
        try store.save(.init(
            daemonId: "d",
            pid: pid,
            startedAt: Date(),
            loopbackHost: "127.0.0.1",
            loopbackPort: 1,
            binaryVersion: "0.1.0",
            contractVersion: "1.0.0"
        ))
        let probe = ServeDaemonProbe(
            store: store, runsDirectory: runs, processAlive: { $0 == pid }
        )
        let client = ServeHealthClient(transport: transportReturning(
            statusCode: 200, body: healthJSON(daemonId: "d", pid: pid)
        ))
        let requirement = ServeRequirement(
            probe: probe, healthClient: client, binaryVersion: "0.1.0"
        )
        let ticketURL = root.appendingPathComponent("wake-ticket.json")

        let result = try requirement.writeIfHealthy(reason: "pmTurnWake") {
            try Data("queued".utf8).write(to: ticketURL, options: .atomic)
            return "ok"
        }
        guard case .success(let value) = result else {
            return XCTFail("healthy handshake must allow write")
        }
        XCTAssertEqual(value, "ok")
        XCTAssertEqual(try String(contentsOf: ticketURL, encoding: .utf8), "queued")
    }

    // MARK: - Attended paths stay ungated (source gate + law)

    /// INFORM-never-BLOCK: `alln run` must not call ServeRequirement / ensureRunning.
    func testAllnRunDoesNotGateOnServeRequirement() throws {
        let here = URL(fileURLWithPath: #filePath)
        let runCLI = here
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Sources/AllnighterCLI/RunCLI.swift")
        let source = try String(contentsOf: runCLI, encoding: .utf8)
        XCTAssertFalse(
            source.contains("ServeRequirement"),
            "alln run must stay runnable with serve dead — do not gate command entry"
        )
        XCTAssertFalse(
            source.contains("ServeAutoLaunch"),
            "detached auto-launch must be gone from alln run"
        )
        XCTAssertFalse(
            source.contains("ensureRunning"),
            "alln run must not demand-heal serve"
        )
    }

    /// Attended loop dispatch (blocking start/resume/adopt) must not gate on serve.
    func testAttendedLoopDispatchDoesNotGateOnServeRequirement() throws {
        let here = URL(fileURLWithPath: #filePath)
        let loopCLI = here
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Sources/AllnighterCLI/LoopEngineCLI.swift")
        let source = try String(contentsOf: loopCLI, encoding: .utf8)

        // Gate is allowed only via requireServeForDeferredObligation (wake path).
        // Attended coordinator dispatches must not call it.
        XCTAssertFalse(source.contains("ServeAutoLaunch"))
        XCTAssertTrue(
            source.contains("requireServeForDeferredObligation"),
            "wake-delivery deferred obligation must call the shared preflight"
        )
        // The only call site is inside awaitDetachedAcceptance when wakeDelivery.
        guard let fnRange = source.range(of: "requireServeForDeferredObligation(reason:") else {
            return XCTFail("missing call site")
        }
        let before = source[source.startIndex..<fnRange.lowerBound]
        // Must appear after wakeDelivery guard, not before coordinator.run/resume/adopt.
        XCTAssertTrue(
            before.contains("if wakeDelivery"),
            "ServeRequirement must be behind wakeDelivery, not command entry"
        )
        for needle in ["coordinator.run(", "coordinator.resume(", "coordinator.adopt("] {
            XCTAssertTrue(source.contains(needle), "missing \(needle)")
            // No requireServe* between the preceding "Attended" marker and the call.
            guard let call = source.range(of: needle) else { continue }
            let lookbackStart = source.index(call.lowerBound, offsetBy: -200, limitedBy: source.startIndex)
                ?? source.startIndex
            let window = source[lookbackStart..<call.lowerBound]
            XCTAssertFalse(
                window.contains("requireServeForDeferredObligation"),
                "attended \(needle) must not call the deferred preflight"
            )
        }
    }

    /// Deleted auto-launch types must not remain in product source (excl. tests archive).
    func testServeAutoLaunchTypesDeletedFromSources() throws {
        let here = URL(fileURLWithPath: #filePath)
        let sourcesRoot = here
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Sources")
        let engine = sourcesRoot.appendingPathComponent("AllnighterEngine/ServeAutoLaunch.swift")
        let cli = sourcesRoot.appendingPathComponent("AllnighterCLI/ServeAutoLaunchCLI.swift")
        XCTAssertFalse(FileManager.default.fileExists(atPath: engine.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: cli.path))
    }
}
