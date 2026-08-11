import XCTest
@testable import AllnighterEngine

/// §4.2 restart contract: SIGTERM must die by signal after settling receipts;
/// deliberate stand-down paths must not re-raise.
final class ServeDaemonSignalTests: XCTestCase {

    private var priorHooks: ServeDaemonSignalHooks!

    override func setUp() {
        super.setUp()
        priorHooks = ServeDaemon.signalHooks
    }

    override func tearDown() {
        ServeDaemon.signalHooks = priorHooks
        super.tearDown()
    }

    func testSIGTERMRequiresReraise() {
        XCTAssertTrue(ServeDaemon.shouldReraiseSIGTERM(after: SIGTERM))
    }

    func testSIGINTDoesNotReraise() {
        XCTAssertFalse(ServeDaemon.shouldReraiseSIGTERM(after: SIGINT))
    }

    func testNilSignalDoesNotReraise() {
        XCTAssertFalse(ServeDaemon.shouldReraiseSIGTERM(after: nil))
    }

    /// Before the fix, SIGTERM resumed the shutdown continuation and `run()` returned
    /// normally, so the CLI exited 0 and launchd treated it as deliberate stand-down.
    func testReraiseRestoresDefaultHandlerThenRaisesSIGTERM() {
        var setCalls: [(Int32, sig_t)] = []
        var raised: [Int32] = []
        ServeDaemon.signalHooks = ServeDaemonSignalHooks(
            setSignal: { sig, handler in
                setCalls.append((sig, handler))
                return nil
            },
            raiseSignal: { sig in
                raised.append(sig)
                return 0
            }
        )

        ServeDaemon.performSIGTERMReraise()

        XCTAssertEqual(setCalls.count, 1)
        XCTAssertEqual(setCalls[0].0, SIGTERM)
        XCTAssertEqual(setCalls[0].1, SIG_DFL)
        XCTAssertEqual(raised, [SIGTERM])
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
