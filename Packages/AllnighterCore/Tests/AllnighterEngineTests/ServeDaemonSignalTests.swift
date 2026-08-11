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
}
