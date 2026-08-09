import XCTest
@testable import AllnighterEngine
@testable import AllnighterCore

/// Serve singleton + takeover. Origin: four daemons on the dogfood host, oldest
/// nine days, each running a different build.
final class ServeDaemonAdmissionTests: XCTestCase {

    private func record(pid: Int32, gitSha: String, version: String = "0.12.2") -> ServeDaemonRecord {
        ServeDaemonRecord(
            daemonId: "d-\(pid)",
            pid: pid,
            startedAt: Date(timeIntervalSince1970: 1_700_000_000),
            loopbackHost: "127.0.0.1",
            loopbackPort: 41_234,
            binaryVersion: version,
            binaryGitSha: gitSha,
            contractVersion: "9.10.0"
        )
    }

    func testNoRecordStarts() {
        XCTAssertEqual(
            ServeDaemonAdmission.decide(existing: nil, isAlive: { _ in true }, myGitSha: "aaa"),
            .start)
    }

    /// A record whose process is gone is a claim that outlived its evidence —
    /// the same rule the probe cache learned today. It must not block a start.
    func testDeadPidStarts() {
        XCTAssertEqual(
            ServeDaemonAdmission.decide(
                existing: record(pid: 4242, gitSha: "aaa"),
                isAlive: { _ in false },
                myGitSha: "aaa"),
            .start)
    }

    /// Same build already serving: a second copy buys nothing and doubles every
    /// schedule.
    func testIdenticalBuildIsRefused() {
        XCTAssertEqual(
            ServeDaemonAdmission.decide(
                existing: record(pid: 900, gitSha: "aaa"),
                isAlive: { _ in true },
                myGitSha: "aaa"),
            .refuse(pid: 900, version: "0.12.2"))
    }

    /// The case that matters daily: a rebuild happened, the running daemon still
    /// executes the old code, and nothing says so. The newcomer takes over —
    /// stale code must not win by seniority.
    func testDifferentBuildIsSuperseded() {
        XCTAssertEqual(
            ServeDaemonAdmission.decide(
                existing: record(pid: 902, gitSha: "old-sha", version: "0.11.0"),
                isAlive: { _ in true },
                myGitSha: "new-sha"),
            .supersede(pid: 902, version: "0.11.0", gitSha: "old-sha"))
    }

    /// Identity is the git sha, not the version string. Two builds can share a
    /// version and differ in code, and noticing that is the entire point.
    func testSameVersionDifferentShaIsStillSuperseded() {
        let decision = ServeDaemonAdmission.decide(
            existing: record(pid: 903, gitSha: "sha-1", version: "0.12.2"),
            isAlive: { _ in true },
            myGitSha: "sha-2")
        guard case .supersede = decision else {
            return XCTFail("same version, different code must still supersede: \(decision)")
        }
    }

    // MARK: - Process table

    /// The record alone missed three live daemons on the dogfood host, so the
    /// process table is a second source of truth. The matching has to be narrow
    /// enough that it never reaps something innocent.
    func testProcessScanMatchesOnlyRealServeDaemons() {
        let listing = """
        HEADER
          902 /Users/mike/Documents/GitHub/Allnighter/.build/debug/alln serve
        43273 /Users/mike/.local/bin/alln serve
        43309 alln serve
        50001 alln serve --health
        50002 alln run "make serve faster"
        50003 /usr/bin/vim alln serve notes.md
        50004 /Users/mike/.local/bin/alln menu --json
        99999 alln serve
        """
        let pids = ServeDaemonAdmission.runningServePIDs(excluding: 99999) { listing }
        XCTAssertEqual(pids, [902, 43273, 43309])
        XCTAssertFalse(pids.contains(50001), "--health is a read, not a daemon")
        XCTAssertFalse(pids.contains(50002), "`alln run` is not serve")
        XCTAssertFalse(pids.contains(50003), "an editor with those words in argv is not serve")
        XCTAssertFalse(pids.contains(50004), "another alln subcommand is not serve")
        XCTAssertFalse(pids.contains(99999), "must never target itself")
    }

    func testProcessScanSurvivesAnUnavailableListing() {
        XCTAssertEqual(ServeDaemonAdmission.runningServePIDs(excluding: 1) { nil }, [])
        XCTAssertEqual(ServeDaemonAdmission.runningServePIDs(excluding: 1) { "" }, [])
    }

    // MARK: - Stop

    func testStopTermsFirstAndDoesNotEscalateWhenTheDaemonComplies() {
        var signals: [Int32] = []
        var alive = true
        let stopped = ServeDaemonAdmission.stop(
            pid: 555,
            isAlive: { _ in alive },
            sleep: { _ in alive = false },
            signal: { _, sig in signals.append(sig) })
        XCTAssertTrue(stopped)
        XCTAssertEqual(signals, [SIGTERM], "a compliant daemon must never be SIGKILLed")
    }

    func testStopEscalatesToKillWhenTermIsIgnored() {
        var signals: [Int32] = []
        var alive = true
        let stopped = ServeDaemonAdmission.stop(
            pid: 556,
            graceSeconds: 0.4,
            isAlive: { _ in alive },
            sleep: { _ in if signals.contains(SIGKILL) { alive = false } },
            signal: { _, sig in signals.append(sig) })
        XCTAssertTrue(stopped)
        XCTAssertEqual(signals.first, SIGTERM)
        XCTAssertTrue(signals.contains(SIGKILL))
    }

    /// If it survives both signals we must NOT start — two daemons is the
    /// condition being fixed, so failing loudly beats adding another.
    func testStopReportsFailureWhenTheDaemonSurvivesEverything() {
        let stopped = ServeDaemonAdmission.stop(
            pid: 557,
            graceSeconds: 0.4,
            isAlive: { _ in true },
            sleep: { _ in },
            signal: { _, _ in })
        XCTAssertFalse(stopped)
    }
}
