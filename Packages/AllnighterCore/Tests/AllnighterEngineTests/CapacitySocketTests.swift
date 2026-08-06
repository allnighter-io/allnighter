import Foundation
#if canImport(Darwin)
import Darwin
#endif
import XCTest
@testable import AllnighterCore
@testable import AllnighterEngine

/// CWB-S02 — capacity.sock fast path proofs.
///
/// Ship gate: "Spy 100× p95 <250 ms, zero PTYs". The spy is the resident's
/// injected `fetch` — the only path to a PTY — and the proof is that 100
/// socket reads never call it. Fallback proofs: miss / hang / bad version
/// all return nil so the CLI goes cold exactly once.
final class CapacitySocketTests: XCTestCase {

    private var servers: [CapacitySocketServer] = []
    private var socketPaths: [String] = []

    override func tearDown() {
        for server in servers { server.stop() }
        for path in socketPaths { unlink(path) }
        servers = []
        socketPaths = []
        super.tearDown()
    }

    // MARK: - Helpers

    private func tempSocketURL() -> URL {
        // `sun_path` is 104 bytes — keep test paths short (NSTemporaryDirectory
        // + UUID overflows it; the production support path does not).
        let url = URL(fileURLWithPath: "/tmp/alln-cap-\(UUID().uuidString.prefix(8)).sock")
        socketPaths.append(url.path)
        return url
    }

    private func startServer(at url: URL) throws -> CapacitySocketServer {
        let server = CapacitySocketServer(path: url)
        try server.start()
        servers.append(server)
        return server
    }

    private func knownWindow(source: String, used: Double, at now: Date) -> CapacityWindow {
        CapacityWindow(
            used: used,
            source: source,
            scope: .weekly,
            resetAt: now.addingTimeInterval(3_600),
            resetPrecision: .exact,
            observedAt: now,
            sourceTier: .tuiProbe
        )
    }

    private final class FetchSpy: @unchecked Sendable {
        private let lock = NSLock()
        private var _starts = 0

        var starts: Int {
            lock.lock(); defer { lock.unlock() }
            return _starts
        }

        /// Sync record — NSLock must not be touched from the async fetch closure.
        func recordStart() {
            lock.lock(); _starts += 1; lock.unlock()
        }

        func makeFetch() -> CapacityResidentService.Fetch {
            { _, _ in
                self.recordStart()
                let now = Date()
                let windows = CapacityAcquisition.benchSourceOrder.map {
                    CapacityWindow(
                        used: 42, source: $0, scope: .weekly,
                        resetAt: now.addingTimeInterval(3_600),
                        resetPrecision: .exact, observedAt: now,
                        sourceTier: .tuiProbe
                    )
                }
                return CapacityFetch.Snapshot(
                    now: now,
                    windows: windows,
                    rows: CapacityBenchProjection.rows(from: windows, now: now)
                )
            }
        }
    }

    /// Resident wired to the server, scheduler never started — the only
    /// acquire is the explicit one the test performs.
    private func makeResident(
        spy: FetchSpy,
        publisher: @escaping @Sendable (CapacitySocketSnapshot) -> Void
    ) async -> CapacityResidentService {
        let resident = CapacityResidentService(
            activities: .disabled,
            persistEnabled: { _ in },
            fetch: spy.makeFetch()
        )
        await resident.setSocketPublisher(publisher)
        return resident
    }

    // MARK: - Serving

    func testReadServesUpdatedSnapshot() throws {
        let url = tempSocketURL()
        let server = try startServer(at: url)
        let now = Date()
        server.update(CapacitySocketSnapshot(
            disabled: false,
            settledAt: now,
            windows: [knownWindow(source: "codex", used: 42, at: now)]
        ))

        let answer = CapacitySocketClient.read(path: url, timeout: 1.0)
        XCTAssertEqual(answer?.schemaVersion, CapacitySocketSnapshot.currentSchemaVersion)
        XCTAssertEqual(answer?.disabled, false)
        XCTAssertEqual(
            answer?.settledAt?.timeIntervalSince1970 ?? 0,
            now.timeIntervalSince1970,
            accuracy: 1.0 // CoreJSON .iso8601 floors to whole seconds
        )
        XCTAssertEqual(answer?.windows.count, 1)
        XCTAssertEqual(answer?.windows.first?.usedPercent, 42)
    }

    func testServerNeverReadsTheConnection() throws {
        // A client that sends bytes cannot steer anything: the server writes
        // the snapshot and closes regardless.
        let url = tempSocketURL()
        let server = try startServer(at: url)
        let now = Date()
        server.update(CapacitySocketSnapshot(
            disabled: false, settledAt: now,
            windows: [knownWindow(source: "kimi", used: 7, at: now)]
        ))

        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        XCTAssertGreaterThanOrEqual(fd, 0)
        defer { close(fd) }
        var addr = try XCTUnwrap(CapacitySocketServer.unixAddress(path: url.path))
        let connected = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        XCTAssertEqual(connected, 0)
        _ = "please probe everything".withCString { write(fd, $0, strlen($0)) }

        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 8192)
        while true {
            let count = buffer.withUnsafeMutableBytes { read(fd, $0.baseAddress, $0.count) }
            guard count > 0 else { break }
            data.append(contentsOf: buffer.prefix(count))
        }
        let answer = CapacitySocketSnapshot.decode(data)
        XCTAssertEqual(answer?.windows.first?.source, "kimi")
    }

    // MARK: - Fallback primitives (miss / hang / bad version → nil → cold once)

    func testMissReturnsNil() {
        let url = tempSocketURL()
        XCTAssertNil(CapacitySocketClient.read(path: url, timeout: 0.5))
    }

    func testStaleFileReturnsNil() throws {
        // A regular file at the socket path (crash debris is unlinked at the
        // next app launch, but the CLI must not trust what it finds either).
        let url = tempSocketURL()
        try Data("debris".utf8).write(to: url)
        XCTAssertNil(CapacitySocketClient.read(path: url, timeout: 0.5))
    }

    func testHangingServerTimesOutToNil() throws {
        // Listener that accepts (via backlog) but never writes: connect
        // succeeds, the read must hit the budget and fall back.
        let url = tempSocketURL()
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        XCTAssertGreaterThanOrEqual(fd, 0)
        defer { close(fd) }
        var addr = try XCTUnwrap(CapacitySocketServer.unixAddress(path: url.path))
        let bound = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.bind(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        XCTAssertEqual(bound, 0)
        XCTAssertEqual(listen(fd, 1), 0)

        let started = Date()
        let answer = CapacitySocketClient.read(path: url, timeout: 0.3)
        let elapsed = Date().timeIntervalSince(started)
        XCTAssertNil(answer, "a hung socket must fall back, not hang the CLI")
        XCTAssertLessThan(elapsed, 3.0, "fallback must stay inside a sane budget")
    }

    func testBadSchemaVersionReturnsNil() throws {
        let url = tempSocketURL()
        let server = try startServer(at: url)
        server.update(CapacitySocketSnapshot(
            schemaVersion: 999,
            disabled: false,
            settledAt: Date(),
            windows: []
        ))
        XCTAssertNil(
            CapacitySocketClient.read(path: url, timeout: 1.0),
            "foreign schema version → cold fallback, never a decoded lie"
        )
    }

    // MARK: - Lifecycle

    func testStopUnlinksSocketFile() throws {
        let url = tempSocketURL()
        let server = try startServer(at: url)
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
        server.stop()
        XCTAssertFalse(
            FileManager.default.fileExists(atPath: url.path),
            "graceful quit must unlink so the CLI sees a clean miss"
        )
        XCTAssertNil(CapacitySocketClient.read(path: url, timeout: 0.3))
    }

    func testStartReclaimsStaleSocketFile() throws {
        // Hard-kill reconcile: debris at the path must not block the next bind.
        let url = tempSocketURL()
        try Data("stale".utf8).write(to: url)
        let server = CapacitySocketServer(path: url)
        XCTAssertNoThrow(try server.start())
        servers.append(server)
        XCTAssertTrue(server.isRunning)
    }

    // MARK: - Ship gate: spy 100× p95 <250 ms, zero PTYs

    func testHundredReadsZeroAcquiresP95Budget() async throws {
        let url = tempSocketURL()
        let server = try startServer(at: url)
        let spy = FetchSpy()
        let resident = await makeResident(spy: spy) { answer in server.update(answer) }

        // One explicit settle through the funnel — the snapshot the socket serves.
        _ = await resident.requestRefresh(reason: .userRefresh)
        XCTAssertEqual(spy.starts, 1)

        var durations: [TimeInterval] = []
        durations.reserveCapacity(100)
        for _ in 0..<100 {
            let started = Date()
            let answer = CapacitySocketClient.read(path: url, timeout: 1.0)
            durations.append(Date().timeIntervalSince(started))
            XCTAssertNotNil(answer)
            XCTAssertEqual(answer?.windows.count, CapacityAcquisition.benchSourceOrder.count)
        }
        XCTAssertEqual(
            spy.starts, 1,
            "100 socket reads must start zero acquires — the socket is read-only"
        )
        let sorted = durations.sorted()
        let p95 = sorted[Int(ceil(0.95 * Double(sorted.count))) - 1]
        XCTAssertLessThan(p95, 0.250, "socket p95 must beat the 250 ms instant budget")
    }

    // MARK: - Feature OFF answers disabled, never a stale snapshot

    func testFeatureOffAnswersDisabledNotStaleSnapshot() async throws {
        let url = tempSocketURL()
        let server = try startServer(at: url)
        let spy = FetchSpy()
        let resident = await makeResident(spy: spy) { answer in server.update(answer) }

        _ = await resident.requestRefresh(reason: .userRefresh)
        XCTAssertEqual(CapacitySocketClient.read(path: url, timeout: 1.0)?.disabled, false)

        await resident.setEnabled(false)
        let answer = CapacitySocketClient.read(path: url, timeout: 1.0)
        XCTAssertEqual(answer?.disabled, true, "OFF must answer disabled")
        XCTAssertEqual(answer?.windows ?? [], [], "OFF must not serve the stale snapshot")
        XCTAssertNil(answer?.settledAt)
    }

    func testResidentPublishesWarmingBeforeFirstSettle() async throws {
        let recorder = AnswerRecorder()
        let spy = FetchSpy()
        _ = await makeResident(spy: spy) { answer in recorder.record(answer) }
        let first = recorder.answers.first
        XCTAssertEqual(first?.disabled, false)
        XCTAssertNil(first?.settledAt, "no settle yet → warming, not a fabricated snapshot")
        XCTAssertEqual(first?.windows ?? [], [])
    }

    // MARK: - Fast-path mapping (pure)

    func testFastPathDisabledAnswerYieldsDisabledRows() {
        let now = Date()
        let bench = CapacitySocketFastPath.snapshot(from: .disabledAnswer, now: now)
        XCTAssertEqual(bench.rows.count, CapacityAcquisition.benchSourceOrder.count)
        for row in bench.rows {
            XCTAssertEqual(row.unknownReason, .disabled)
        }
    }

    func testFastPathWarmingAnswerYieldsNeverSampled() {
        let now = Date()
        let bench = CapacitySocketFastPath.snapshot(from: .warmingAnswer, now: now)
        XCTAssertEqual(bench.rows.count, CapacityAcquisition.benchSourceOrder.count)
        for row in bench.rows {
            XCTAssertEqual(row.unknownReason, .neverSampled)
        }
    }

    func testFastPathSettledAnswerPaintGatesByAge() {
        let settledAt = Date()
        let window = knownWindow(source: "codex", used: 42, at: settledAt)
        let answer = CapacitySocketSnapshot(disabled: false, settledAt: settledAt, windows: [window])

        // Fresh: passes through ungated.
        let fresh = CapacitySocketFastPath.snapshot(
            from: answer, now: settledAt.addingTimeInterval(60)
        )
        XCTAssertNil(fresh.windows.first?.unknownReason)
        XCTAssertEqual(fresh.windows.first?.usedPercent, 42)

        // Past the 30-minute gate: known seats paint expired, observedAt honest.
        let stale = CapacitySocketFastPath.snapshot(
            from: answer, now: settledAt.addingTimeInterval(CapacityPaintGate.gateInterval + 1)
        )
        guard case .expired(let observedAt)? = stale.windows.first?.unknownReason else {
            return XCTFail("past-gate snapshot must paint expired, not fresh")
        }
        XCTAssertEqual(observedAt, window.observedAt)
    }

    /// A resident answer settled before a seat was promoted onto the bench
    /// (e.g. an old-build Dock app process still running after OCG-S08) must
    /// still yield the full current roster over the socket-served path — the
    /// missing seat painted as an honest `neverSampled` unknown, never
    /// silently dropped. A live-path proof does not cover this: the gap is
    /// specific to the resident's answer being stale/partial, and the fast
    /// path (`CapacitySocketFastPath.snapshot`) is what has to complete it.
    func testFastPathCompletesSeatMissingFromStaleResidentAnswer() {
        let settledAt = Date()
        let now = settledAt.addingTimeInterval(60)
        // Simulate a pre-promotion resident: only the PTY seats settled,
        // exactly as `CapacityAcquisition.ptySourceOrder` (not benchSourceOrder).
        let staleWindows = CapacityAcquisition.ptySourceOrder.map { source in
            knownWindow(source: source, used: 10, at: settledAt)
        }
        XCTAssertFalse(
            CapacityAcquisition.ptySourceOrder.contains(CapacityAcquisition.dogfoodSourceId),
            "fixture must omit the dashboard seat to model the stale-resident gap"
        )
        let answer = CapacitySocketSnapshot(disabled: false, settledAt: settledAt, windows: staleWindows)

        let bench = CapacitySocketFastPath.snapshot(from: answer, now: now)

        XCTAssertEqual(
            bench.rows.count, CapacityAcquisition.benchSourceOrder.count,
            "bare capacity over the socket path must show every current bench seat"
        )
        let sources = Set(bench.windows.map(\.source))
        XCTAssertEqual(sources, Set(CapacityAcquisition.benchSourceOrder))

        let goWindow = bench.windows.first { $0.source == CapacityAcquisition.dogfoodSourceId }
        XCTAssertEqual(
            goWindow?.unknownReason, .neverSampled,
            "a seat absent from the resident's answer must paint an honest unknown, never be invented or dropped"
        )
        // Seats the stale answer did carry stay untouched by the completion step.
        let codexWindow = bench.windows.first { $0.source == "codex" }
        XCTAssertNil(codexWindow?.unknownReason)
        XCTAssertEqual(codexWindow?.usedPercent, 10)
    }

    private final class AnswerRecorder: @unchecked Sendable {
        private let lock = NSLock()
        private var _answers: [CapacitySocketSnapshot] = []

        var answers: [CapacitySocketSnapshot] {
            lock.lock(); defer { lock.unlock() }
            return _answers
        }

        func record(_ answer: CapacitySocketSnapshot) {
            lock.lock(); _answers.append(answer); lock.unlock()
        }
    }
}
