import XCTest
import AgentOSCLI
@testable import AllnighterEngine

/// Kill tests for the notInstalled-over-ready guard.
/// A path-miss this pass must not assert uninstall over a still-executable
/// prior ready path; genuine absence / real uninstall still report notInstalled.
final class ProbeRecordMergeTests: XCTestCase {

    private let now = Date(timeIntervalSince1970: 1_700_000_000)
    private let earlier = Date(timeIntervalSince1970: 1_600_000_000)

    private func readyRecord(path: String, version: String = "1.18.16") -> ToolProbeRecord {
        ToolProbeRecord(
            driverId: "opencode",
            status: .ready(version: version),
            invocation: .direct(path: path),
            version: version,
            lastProbeAt: earlier,
            lastDetectedAt: earlier
        )
    }

    private func notInstalledPass(driverId: String = "opencode") -> ToolProbeRecord {
        ToolProbeRecord(
            driverId: driverId,
            status: .notInstalled,
            lastProbeAt: now,
            lastDetectedAt: now
        )
    }

    // 1. prior ready + recorded path still executable + pass resolves nothing
    //    -> NOT downgraded; reason captured in failureCode.
    func testRetainsReadyWhenPriorPathStillExecutable() {
        let path = "/Users/openclaw/.opencode/bin/opencode"
        let prior = readyRecord(path: path)
        let incoming = notInstalledPass()

        let applied = ProbeRecordMerge.apply(
            incoming: incoming,
            prior: prior,
            isExecutable: { $0 == path }
        )

        XCTAssertEqual(applied.status, .ready(version: "1.18.16"))
        XCTAssertEqual(applied.invocation, .direct(path: path))
        XCTAssertEqual(applied.version, "1.18.16")
        XCTAssertEqual(applied.lastProbeAt, earlier, "must not manufacture smoke freshness")
        XCTAssertEqual(applied.lastDetectedAt, now, "presence re-check may advance")
        XCTAssertEqual(applied.failureCode, ProbeRecordMerge.retainedReadyFailureCode)
    }

    // 2. prior ready + recorded path deleted + pass resolves nothing
    //    -> notInstalled (real uninstall).
    func testAllowsNotInstalledWhenPriorPathGone() {
        let path = "/tmp/gone-opencode"
        let prior = readyRecord(path: path)
        let incoming = notInstalledPass()

        let applied = ProbeRecordMerge.apply(
            incoming: incoming,
            prior: prior,
            isExecutable: { _ in false }
        )

        XCTAssertEqual(applied.status, .notInstalled)
        XCTAssertNil(applied.invocation)
        XCTAssertNil(applied.failureCode)
    }

    // 3. no prior record + pass resolves nothing -> notInstalled.
    func testNotInstalledWhenNoPrior() {
        let incoming = notInstalledPass(driverId: "qwen")

        let applied = ProbeRecordMerge.apply(
            incoming: incoming,
            prior: nil,
            isExecutable: { _ in true }
        )

        XCTAssertEqual(applied.status, .notInstalled)
        XCTAssertEqual(applied.driverId, "qwen")
    }

    // 4. pass resolves a path normally -> unchanged ready behavior.
    func testReadyPassUnchanged() {
        let path = "/Users/openclaw/.opencode/bin/opencode"
        let prior = readyRecord(path: path, version: "1.0.0")
        let incoming = ToolProbeRecord(
            driverId: "opencode",
            status: .ready(version: "1.18.16"),
            invocation: .direct(path: path),
            version: "1.18.16",
            lastProbeAt: now,
            lastDetectedAt: now
        )

        let applied = ProbeRecordMerge.apply(
            incoming: incoming,
            prior: prior,
            isExecutable: { _ in false } // irrelevant when incoming is ready
        )

        XCTAssertEqual(applied.status, .ready(version: "1.18.16"))
        XCTAssertEqual(applied.version, "1.18.16")
        XCTAssertEqual(applied.lastProbeAt, now)
        XCTAssertNil(applied.failureCode)
    }

    func testUpsertDoesNotDowngradeSiblingDrivers() {
        var records = [
            readyRecord(path: "/bin/opencode"),
            ToolProbeRecord(driverId: "qwen", status: .notInstalled, lastProbeAt: earlier),
        ]
        ProbeRecordMerge.upsert(
            notInstalledPass(driverId: "qwen"),
            into: &records,
            isExecutable: { $0 == "/bin/opencode" }
        )
        ProbeRecordMerge.upsert(
            notInstalledPass(driverId: "opencode"),
            into: &records,
            isExecutable: { $0 == "/bin/opencode" }
        )

        let opencode = records.first { $0.driverId == "opencode" }
        let qwen = records.first { $0.driverId == "qwen" }
        XCTAssertEqual(opencode?.status, .ready(version: "1.18.16"))
        XCTAssertEqual(opencode?.failureCode, ProbeRecordMerge.retainedReadyFailureCode)
        XCTAssertEqual(qwen?.status, .notInstalled)
    }
}
