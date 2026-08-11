import XCTest
import AllnighterCore
@testable import AllnighterEngine

/// ASR-S03f2a — gatherer composes existing readers into `ServeStatusJSON.Input`.
final class ServeStatusGathererTests: XCTestCase {

    private let t0 = Date(timeIntervalSince1970: 1_720_000_000)
    private let t1 = Date(timeIntervalSince1970: 1_720_000_100)
    private let label = ServeLaunchAgentStatus.label
    private let canonicalPath = "/tmp/alln-test/.local/share/allnighter/bin/alln"
    private let shaA = "abc123"
    private let cdhashA = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"

    // MARK: - ASR-S03f2a2 rot / fail-closed (supervisor loaded)

    /// Negative proof: structured "could not consult" must yield unknown even when
    /// `detail` is reworded. Against the prose-matching gatherer this returned `true`.
    func testStructuredCouldNotConsultWithRewordedDetailYieldsUnknown() {
        let observation = ServeLaunchAgentStatus.Observation(
            state: .unknown,
            detail: "plist present but launchctl could not be reached (reworded)",
            launchctlConsultability: .couldNotConsult
        )
        XCTAssertNil(
            ServeStatusGatherer.supervisorLoaded(plistPresent: true, observation: observation),
            "structured could-not-consult must yield unknown regardless of detail wording"
        )
    }

    /// Unclassifiable observation (no consultability signal) yields unknown, never optimistic true.
    func testUnclassifiableObservationYieldsUnknownNotTrue() {
        let observation = ServeLaunchAgentStatus.Observation(
            state: .unknown,
            detail: "com.allnighter.resident-coordinator plist present but launchctl print failed (job not loaded)",
            launchctlConsultability: nil
        )
        XCTAssertNil(
            ServeStatusGatherer.supervisorLoaded(plistPresent: true, observation: observation),
            "missing consultability must fail closed to unknown, not optimistic true"
        )
    }

    // MARK: - Healthy path

    func testHealthyHostProducesHealthyStatus() {
        let root = makeTempRoot()
        defer { removeIfPresent(root) }

        let gatherer = makeGatherer(root: root, healthTransport: matchingHealthTransport())
        let gathered = gatherer.gather()

        XCTAssertEqual(gathered.status.state, .healthy)
        XCTAssertNil(gathered.status.recovery)
        XCTAssertTrue(gathered.status.binary.matches)
        XCTAssertNotNil(gathered.status.daemon.activeHealthRespondedAt)
    }

    // MARK: - Four distinct failure-to-read observations

    func testDesiredStateUnreadableMapsToUnknownNotAbsent() {
        let root = makeTempRoot()
        defer { removeIfPresent(root) }

        let gatherer = makeGatherer(
            root: root,
            healthTransport: matchingHealthTransport(),
            readDesiredState: { .unreadable(reason: "corrupt JSON") }
        )
        let gathered = gatherer.gather()

        XCTAssertEqual(gathered.input.desiredState, .unknown(reason: "corrupt JSON"))
        XCTAssertEqual(gathered.status.state, .degraded)
        XCTAssertEqual(gathered.status.recovery?.reasonCode, "SERVE_UNKNOWN_DESIRED_STATE")
    }

    func testReceiptAbsentIsDistinctFromUnreadable() {
        let root = makeTempRoot()
        defer { removeIfPresent(root) }

        let gathererAbsent = makeGatherer(
            root: root,
            healthTransport: matchingHealthTransport(),
            receiptReading: .absent
        )
        XCTAssertEqual(gathererAbsent.gather().input.receipt, .absent)
        XCTAssertNotEqual(gathererAbsent.gather().status.state, ServeStatusJSON.State.healthy)

        let gathererUnreadable = makeGatherer(
            root: root,
            healthTransport: matchingHealthTransport(),
            receiptReading: .unreadable(reason: "truncated")
        )
        XCTAssertEqual(gathererUnreadable.gather().input.receipt, .unreadable(reason: "truncated"))
        XCTAssertEqual(gathererUnreadable.gather().status.recovery?.reasonCode, "SERVE_UNKNOWN_RECEIPT")
    }

    func testHealthTimeoutMapsToUnknownNotNoResponse() {
        let root = makeTempRoot()
        defer { removeIfPresent(root) }

        let timeoutError = NSError(domain: NSURLErrorDomain, code: NSURLErrorTimedOut, userInfo: nil)
        let gatherer = makeGatherer(
            root: root,
            healthTransport: { _, _ in throw timeoutError }
        )
        let gathered = gatherer.gather()

        guard case .unknown(let reason) = gathered.input.activeHealth else {
            XCTFail("expected unknown active health, got \(gathered.input.activeHealth)")
            return
        }
        XCTAssertTrue(reason.contains("timeout"))
        XCTAssertEqual(gathered.status.recovery?.reasonCode, "SERVE_UNKNOWN_ACTIVE_HEALTH")
    }

    func testHealthConnectionRefusedMapsToNoResponseNotUnknown() {
        let root = makeTempRoot()
        defer { removeIfPresent(root) }

        let refused = NSError(domain: NSURLErrorDomain, code: NSURLErrorCannotConnectToHost, userInfo: nil)
        let gatherer = makeGatherer(
            root: root,
            healthTransport: { _, _ in throw refused }
        )
        let gathered = gatherer.gather()

        guard case .noResponse(let reason) = gathered.input.activeHealth else {
            XCTFail("expected noResponse, got \(gathered.input.activeHealth)")
            return
        }
        XCTAssertTrue(reason.contains("connection refused"))
        XCTAssertNotEqual(gathered.status.recovery?.reasonCode, "SERVE_UNKNOWN_ACTIVE_HEALTH")
        XCTAssertEqual(gathered.status.state, .degraded)
    }

    // MARK: - Handshake mismatch (resolver compares against receipt)

    func testMismatchedDaemonIdDoesNotCountAsMatchedHandshake() {
        let root = makeTempRoot()
        defer { removeIfPresent(root) }

        let gatherer = makeGatherer(
            root: root,
            healthTransport: healthTransport(daemonId: "wrong-id", pid: 1234)
        )
        let gathered = gatherer.gather()

        guard case .responded(let id, _, _) = gathered.input.activeHealth else {
            XCTFail("expected responded handshake body")
            return
        }
        XCTAssertEqual(id, "wrong-id")
        XCTAssertNotEqual(gathered.status.state, ServeStatusJSON.State.healthy)
        XCTAssertNil(gathered.status.daemon.activeHealthRespondedAt)
    }

    func testMismatchedPidDoesNotCountAsMatchedHandshake() {
        let root = makeTempRoot()
        defer { removeIfPresent(root) }

        let gatherer = makeGatherer(
            root: root,
            healthTransport: healthTransport(daemonId: "d1", pid: 9999)
        )
        let gathered = gatherer.gather()

        guard case .responded(_, let pid, _) = gathered.input.activeHealth else {
            XCTFail("expected responded handshake body")
            return
        }
        XCTAssertEqual(pid, 9999)
        XCTAssertNotEqual(gathered.status.state, ServeStatusJSON.State.healthy)
        XCTAssertNil(gathered.status.daemon.activeHealthRespondedAt)
    }

    func testLiveSupervisorPidWithoutHandshakeNeverMatches() {
        let root = makeTempRoot()
        defer { removeIfPresent(root) }

        let listing = """
        state = running
        pid = 4242
        """
        let gatherer = makeGatherer(
            root: root,
            healthTransport: { _, _ in throw NSError(domain: NSURLErrorDomain, code: NSURLErrorCannotConnectToHost, userInfo: nil) },
            launchAgentListing: listing
        )
        let gathered = gatherer.gather()

        XCTAssertEqual(gathered.input.supervisor.pid, 4242)
        guard case .noResponse = gathered.input.activeHealth else {
            XCTFail("expected no handshake")
            return
        }
        XCTAssertNil(gathered.status.daemon.activeHealthRespondedAt)
        XCTAssertNotEqual(gathered.status.state, ServeStatusJSON.State.healthy)
    }

    // MARK: - Read-only / no mutations

    func testGathererPerformsNoWritesOnReadOnlyFilesystem() {
        let root = makeTempRoot()
        defer { removeIfPresent(root) }

        let coordDir = root.appendingPathComponent("Coordinator", isDirectory: true)
        let gatherer = makeGatherer(root: root, healthTransport: matchingHealthTransport())
        let before = listFilePaths(under: coordDir)
        _ = gatherer.gather()
        let after = listFilePaths(under: coordDir)
        XCTAssertEqual(before.sorted(), after.sorted())
    }

    // MARK: - Injectable dependencies (zero real host access)

    func testEveryDependencyIsInjectedWithoutHostAccess() {
        let respondedAt = t1
        let root = makeTempRoot()
        defer { removeIfPresent(root) }

        let injected = makeGatherer(
            root: root,
            clock: { respondedAt },
            healthTransport: matchingHealthTransport()
        )
        let gathered = injected.gather()
        XCTAssertEqual(
            gathered.input.activeHealth,
            ServeStatusJSON.ActiveHealthObservation.responded(daemonId: "d1", pid: 1234, respondedAt: respondedAt)
        )
        XCTAssertEqual(gathered.status.state, ServeStatusJSON.State.healthy)

        let rows = requiredRows()
        let path = canonicalPath
        let gitSha = shaA
        let cdhash = cdhashA
        let startedAt = t0
        let agentLabel = label
        let pureInjection = ServeStatusGatherer(
            homeDirectory: URL(fileURLWithPath: "/fake/home"),
            readDesiredState: { .present(state: .enabled, updatedAt: startedAt) },
            launchAgent: ServeLaunchAgentStatus(
                plistURL: URL(fileURLWithPath: "/fake/\(agentLabel).plist"),
                plistExists: { _ in true },
                printListing: { "state = running\npid = 1234\n" }
            ),
            readAuthorization: { _ in .enabled },
            healthClient: ServeHealthClient(transport: matchingHealthTransport()),
            readReceipt: {
                .present(daemonId: "d1", pid: 1234, startedAt: startedAt, rows: rows)
            },
            daemonStore: ServeDaemonStore(directory: root.appendingPathComponent("Coordinator")),
            readCanonicalInstall: {
                ServeStatusGatherer.CanonicalInstallReading(
                    path: path,
                    expectedGitSha: gitSha,
                    expectedCodeIdentity: .init(cdhash: cdhash, version: "1.0.0")
                )
            },
            readRunningCodeIdentity: { _ in .init(cdhash: cdhash, version: "1.0.0") },
            activeObligationCount: { 0 }
        )
        _ = pureInjection.gatherInput()
    }

    // MARK: - Fixtures

    private func makeTempRoot() -> URL {
        URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("gatherer-\(UUID().uuidString)", isDirectory: true)
    }

    private func removeIfPresent(_ url: URL) {
        try? FileManager.default.removeItem(at: url)
    }

    private func matchingHealthTransport() -> ServeHealthClient.Transport {
        healthTransport(daemonId: "d1", pid: 1234)
    }

    private func healthTransport(daemonId: String, pid: Int32) -> ServeHealthClient.Transport {
        let body = "{\"daemonId\":\"\(daemonId)\",\"pid\":\(pid)}"
        return { _, _ in (Data(body.utf8), 200) }
    }

    private func requiredRows(
        state: ServeRuntimeReceipts.SchedulerState = .waiting
    ) -> [ServeRuntimeReceipts.SchedulerRow] {
        ServeRuntimeReceipts.requiredSchedulerIds.sorted().map {
            ServeRuntimeReceipts.SchedulerRow(
                id: $0,
                state: state,
                lastAttemptAt: t0,
                lastSuccessAt: t0,
                lastError: nil,
                nextWakeAt: t1
            )
        }
    }

    private func listFilePaths(under directory: URL) -> [String] {
        guard let enumerator = FileManager.default.enumerator(at: directory, includingPropertiesForKeys: nil) else {
            return []
        }
        var paths: [String] = []
        for case let url as URL in enumerator {
            paths.append(url.path)
        }
        return paths
    }

    private func makeGatherer(
        root: URL,
        clock: @escaping @Sendable () -> Date = { Date(timeIntervalSince1970: 1_720_000_100) },
        healthTransport: @escaping ServeHealthClient.Transport,
        launchAgentListing: String = "state = running\npid = 1234\n",
        readDesiredState: (@Sendable () -> ServeDesiredState.Reading)? = nil,
        receiptReading: ServeRuntimeReceipts.Reading? = nil
    ) -> ServeStatusGatherer {
        let fixtureT0 = t0
        let fixtureShaA = shaA
        let fixtureCdhashA = cdhashA
        let fixtureCanonicalPath = canonicalPath
        let fixtureLabel = label
        let coordDir = root.appendingPathComponent("Coordinator", isDirectory: true)
        let homeDir = root.appendingPathComponent("Home", isDirectory: true)
        let plistURL = homeDir
            .appendingPathComponent("Library/LaunchAgents", isDirectory: true)
            .appendingPathComponent("\(fixtureLabel).plist")

        try? FileManager.default.createDirectory(at: plistURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(at: coordDir, withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: plistURL.path, contents: Data("plist".utf8))
        FileManager.default.createFile(atPath: URL(fileURLWithPath: fixtureCanonicalPath).path, contents: Data([0xCF]))

        let store = ServeDaemonStore(directory: coordDir)
        try? store.save(.init(
            daemonId: "d1",
            pid: 1234,
            startedAt: fixtureT0,
            loopbackHost: "127.0.0.1",
            loopbackPort: 18743,
            binaryVersion: "1.0.0",
            binaryGitSha: fixtureShaA,
            contractVersion: "1.0.0"
        ))

        let receipts = ServeRuntimeReceipts(directory: coordDir, clock: { fixtureT0 })
        let readReceipt: @Sendable () -> ServeRuntimeReceipts.Reading
        if let receiptReading {
            readReceipt = { receiptReading }
            switch receiptReading {
            case .absent:
                break
            case .unreadable:
                FileManager.default.createFile(
                    atPath: receipts.runtimeFile.path,
                    contents: Data("{not json".utf8)
                )
            case .present(let daemonId, let pid, let startedAt, let rows):
                _ = receipts.write(daemonId: daemonId, pid: pid, startedAt: startedAt, rows: rows)
            }
        } else {
            _ = receipts.write(daemonId: "d1", pid: 1234, startedAt: fixtureT0, rows: requiredRows())
            readReceipt = { receipts.read() }
        }

        return ServeStatusGatherer(
            homeDirectory: homeDir,
            clock: clock,
            readDesiredState: readDesiredState ?? { .present(state: .enabled, updatedAt: fixtureT0) },
            launchAgent: ServeLaunchAgentStatus(
                plistURL: plistURL,
                plistExists: { _ in true },
                printListing: { launchAgentListing }
            ),
            readAuthorization: { _ in .enabled },
            healthClient: ServeHealthClient(transport: healthTransport),
            readReceipt: readReceipt,
            daemonStore: store,
            readCanonicalInstall: {
                ServeStatusGatherer.CanonicalInstallReading(
                    path: fixtureCanonicalPath,
                    expectedGitSha: fixtureShaA,
                    expectedCodeIdentity: .init(cdhash: fixtureCdhashA, version: "1.0.0")
                )
            },
            readRunningCodeIdentity: { _ in .init(cdhash: fixtureCdhashA, version: "1.0.0") },
            activeObligationCount: { 0 },
            converging: { false }
        )
    }
}
