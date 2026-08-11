import XCTest
@testable import AllnighterEngine

/// §4.2 restart contract: SIGTERM must die by signal after settling receipts;
/// deliberate stand-down paths must not re-raise.
///
/// Coverage limit, stated rather than implied: the two-line delivery itself
/// (`signal(SIGTERM, SIG_DFL)` then `raise(SIGTERM)`) is **not** unit-tested. An
/// injectable seam for it was tried and removed — it required a mutable global
/// holding process-wide signal disposition, which Swift 6 rejects as unsafe
/// shared state, and the faithful version of the assertion kills the test
/// runner. The decision logic below is tested; the delivery is proven on the
/// real primitive by ASR-S06 gate 3
/// (`works-test-serve-continuity.sh --mutate-product-agent crash-restart`).
final class ServeDaemonSignalTests: XCTestCase {

    func testSIGTERMRequiresReraise() {
        XCTAssertTrue(ServeDaemon.shouldReraiseSIGTERM(after: SIGTERM))
    }

    func testSIGINTDoesNotReraise() {
        XCTAssertFalse(ServeDaemon.shouldReraiseSIGTERM(after: SIGINT))
    }

    func testNilSignalDoesNotReraise() {
        XCTAssertFalse(ServeDaemon.shouldReraiseSIGTERM(after: nil))
    }

    /// Admission refusal exits 0 before `runUntilSignal` — no daemon, no re-raise.
    func testAdmissionRefuseIsDeliberateStandDownNotSignalDeath() {
        let decision = ServeDaemonAdmission.decide(
            existing: ServeDaemonRecord(
                daemonId: "d-1",
                pid: 42,
                startedAt: Date(),
                loopbackHost: "127.0.0.1",
                loopbackPort: 41_234,
                binaryVersion: "0.12.2",
                binaryGitSha: "same-sha",
                contractVersion: "9.19.0"
            ),
            isAlive: { _ in true },
            myGitSha: "same-sha"
        )
        guard case .refuse(let pid, _) = decision else {
            return XCTFail("expected refuse for identical build: \(decision)")
        }
        XCTAssertEqual(pid, 42)
    }

    /// §4.2 both directions: only SIGTERM becomes signal death; other exits stay clean.
    func testReraiseContractIsSIGTERMOnly() {
        XCTAssertTrue(ServeDaemon.shouldReraiseSIGTERM(after: SIGTERM))
        XCTAssertFalse(ServeDaemon.shouldReraiseSIGTERM(after: SIGINT))
        XCTAssertFalse(ServeDaemon.shouldReraiseSIGTERM(after: nil))
    }

    func testExactStandDownMarkerIsConsumedBeforeCleanExit() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let marker = directory.appendingPathComponent("stand-down")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        try Data("stand-down".utf8).write(to: marker)
        let daemon = ServeDaemon(binaryVersion: "test", standDownMarkerURL: marker)

        try await daemon.runUntilSignal()

        XCTAssertFalse(FileManager.default.fileExists(atPath: marker.path))
    }

    func testOnlyExactStandDownMarkerContentInduces() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let marker = directory.appendingPathComponent("stand-down")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        try Data().write(to: marker)
        XCTAssertFalse(ServeDaemon.consumeStandDownMarkerIfRequested(at: marker))
        XCTAssertTrue(FileManager.default.fileExists(atPath: marker.path))

        try Data("stand-down\n".utf8).write(to: marker)
        XCTAssertFalse(ServeDaemon.consumeStandDownMarkerIfRequested(at: marker))
        XCTAssertTrue(FileManager.default.fileExists(atPath: marker.path))
    }
}
