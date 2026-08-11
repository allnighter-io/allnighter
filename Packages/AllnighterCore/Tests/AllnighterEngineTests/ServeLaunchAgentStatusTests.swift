import XCTest
import AllnighterCore
@testable import AllnighterEngine

/// SC-S00 — LaunchAgent honesty. All fixtures injected; no live launchctl.
/// The wedge rule (spawn scheduled / inactive + EX_CONFIG 78 or LWCR marks +
/// no live pid, or exit 78 with zero active count) is the only fail-closed
/// gate: absent plist stays OK, a running agent with a live pid never wedges.
final class ServeLaunchAgentStatusTests: XCTestCase {

    /// Dogfood-host shape: KeepAlive respawn loop after a rebuild left the
    /// agent spawn scheduled with EX_CONFIG and LWCR marks, no live pid.
    private let wedgedListing = """
        gui/501/com.allnighter.resident-coordinator = {
        	active count = 0
        	copy count = 0
        	one shot = 0
        	last exit code = 78
        	state = spawn scheduled
        	program = /Users/mike/.local/bin/alln
        	properties = {
        		managed LWCR = 1
        		needs LWCR = 1
        	}
        }
        """

    private let runningListing = """
        gui/501/com.allnighter.resident-coordinator = {
        	active count = 1
        	last exit code = 0
        	pid = 4242
        	state = running
        	program = /Users/mike/.local/bin/alln
        }
        """

    /// Loaded, idle, healthy: KeepAlive job waiting for work, clean last exit.
    private let idleListing = """
        gui/501/com.allnighter.resident-coordinator = {
        	active count = 0
        	last exit code = 0
        	state = waiting
        	program = /Users/mike/.local/bin/alln
        }
        """

    private func status(
        plistPresent: Bool,
        listing: String? = nil,
        printError: Error? = nil
    ) -> ServeLaunchAgentStatus {
        ServeLaunchAgentStatus(
            plistURL: URL(fileURLWithPath: "/tmp/\(UUID().uuidString).plist"),
            plistExists: { _ in plistPresent },
            printListing: {
                if let printError { throw printError }
                guard let listing else {
                    throw ServeLaunchAgentStatus.PrintError(terminationStatus: 113)
                }
                return listing
            }
        )
    }

    // MARK: - Observation classification

    func testAbsentPlistReadsAbsent() {
        let s = status(plistPresent: false)
        let o = s.observe()
        XCTAssertEqual(o.state, .absent)
        XCTAssertNil(o.pid)
    }

    func testWedgedSpawnScheduledExit78WithLWCRMarks() {
        let o = status(plistPresent: true, listing: wedgedListing).observe()
        XCTAssertEqual(o.state, .wedged)
        XCTAssertEqual(o.lastExitCode, 78)
        XCTAssertNil(o.pid)
    }

    /// Rule B: plist present + last exit 78 + active count 0, no LWCR marks.
    func testWedgedExit78ZeroActiveCountWithoutLWCRMarks() {
        let listing = """
            gui/501/com.allnighter.resident-coordinator = {
            	active count = 0
            	last exit code = 78
            	state = waiting
            }
            """
        XCTAssertEqual(status(plistPresent: true, listing: listing).observe().state, .wedged)
    }

    /// LWCR-marked job spawn scheduled even with a clean last exit is wedged.
    func testLWCRMarkedSpawnScheduledIsWedged() {
        let listing = """
            gui/501/com.allnighter.resident-coordinator = {
            	active count = 0
            	last exit code = 0
            	state = spawn scheduled
            	properties = {
            		needs LWCR = 1
            	}
            }
            """
        XCTAssertEqual(status(plistPresent: true, listing: listing).observe().state, .wedged)
    }

    /// A live job pid is running, never wedged — even with a stale exit 78.
    func testRunningAgentWithLivePidIsNotWedged() {
        let o = status(plistPresent: true, listing: runningListing).observe()
        XCTAssertEqual(o.state, .running)
        XCTAssertEqual(o.pid, 4242)
    }

    /// Loaded but idle with a clean exit is not a wedge and not a failure.
    func testIdleLoadedAgentIsNotWedged() {
        let o = status(plistPresent: true, listing: idleListing).observe()
        XCTAssertEqual(o.state, .unknown)
        XCTAssertNotEqual(o.state, .wedged)
    }

    /// Plist present but the job is not loaded: honest unknown, never wedged
    /// on silence (fail loud, not closed, per the derived-signal law).
    func testPrintFailureWithPlistReadsUnknown() {
        let o = status(plistPresent: true,
                       printError: ServeLaunchAgentStatus.PrintError(terminationStatus: 113)).observe()
        XCTAssertEqual(o.state, .unknown)
        XCTAssertEqual(o.launchctlConsultability, .couldNotConsult)
    }

    // MARK: - Probe composition

    private func probe(
        launchAgent: ServeLaunchAgentStatus
    ) -> (URL, ServeDaemonProbe) {
        let root = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("sla-\(UUID().uuidString)")
        let probe = ServeDaemonProbe(
            store: ServeDaemonStore(directory: root.appendingPathComponent("Coordinator", isDirectory: true)),
            runsDirectory: root.appendingPathComponent("Runs", isDirectory: true),
            launchAgent: launchAgent
        )
        return (root, probe)
    }

    /// Wedged agent with no daemon: foreground-only health still exposes the
    /// wedge — it cannot read as "all fine".
    func testHealthExposesWedgeWhenForegroundOnly() {
        let (root, probe) = probe(launchAgent: status(plistPresent: true, listing: wedgedListing))
        defer { try? FileManager.default.removeItem(at: root) }

        let health = probe.health(binaryVersion: "0.1.0")
        XCTAssertEqual(health.state, .foregroundOnly)
        XCTAssertEqual(health.launchAgent?.state, .wedged)
        XCTAssertEqual(probe.doctorCoordinator().launchAgent?.state, .wedged)
    }

    /// Absent plist: no launchAgent field, no new failure surface.
    func testHealthOmitsLaunchAgentWhenPlistAbsent() {
        let (root, probe) = probe(launchAgent: status(plistPresent: false))
        defer { try? FileManager.default.removeItem(at: root) }

        let health = probe.health(binaryVersion: "0.1.0")
        XCTAssertEqual(health.state, .foregroundOnly)
        XCTAssertNil(health.launchAgent)
        XCTAssertNil(probe.doctorCoordinator().launchAgent)
    }

    /// Running agent: observation reports running, not wedged.
    func testHealthReportsRunningAgent() {
        let (root, probe) = probe(launchAgent: status(plistPresent: true, listing: runningListing))
        defer { try? FileManager.default.removeItem(at: root) }

        XCTAssertEqual(probe.health(binaryVersion: "0.1.0").launchAgent?.state, .running)
    }

    // MARK: - Doctor projection

    private func doctorResult(coordinator: DoctorResult.Coordinator) -> DoctorResult {
        DoctorReport.build(
            models: [Model(id: "model_opus", displayName: "Opus 5", modelLabel: "opus", driverId: "claude_code", role: .both)],
            manifests: [DriverManifest(id: "claude_code", displayName: "Claude Code", kind: .headlessCLI)],
            records: [ToolProbeRecord(driverId: "claude_code", status: .installedNotProbed(version: "1.2"), version: "1.2", lastProbeAt: Date(timeIntervalSince1970: 0))],
            inputs: .init(binaryVersion: "0.1.0", contractVersion: "1.0.0",
                          configDirWritable: true, runsDirWritable: true,
                          coordinator: coordinator, full: false)
        )
    }

    /// Wedged fixture → doctor check not ok + overall status cannot be ok.
    func testWedgedLaunchAgentFailsDoctorCheck() {
        let coordinator = DoctorResult.Coordinator(
            state: .foregroundOnly,
            detail: "foreground CLI only; background scheduler not running",
            launchAgent: .init(state: .wedged, lastExitCode: 78,
                               detail: "com.allnighter.resident-coordinator wedged: spawn scheduled, last exit 78, no live job pid")
        )
        let r = doctorResult(coordinator: coordinator)
        let check = r.checks.first { $0.name == "serve.launchAgent" }
        XCTAssertEqual(check?.status, .critical)
        XCTAssertEqual(check?.fixCommand, "alln serve")
        XCTAssertEqual(r.status, .degraded, "a wedged LaunchAgent can never read as all fine")
    }

    /// Absent plist (nil launchAgent) → serve.launchAgent stays ok, no new failure.
    func testAbsentLaunchAgentKeepsDoctorOk() {
        let coordinator = DoctorResult.Coordinator(state: .foregroundOnly, detail: "foreground CLI only")
        let r = doctorResult(coordinator: coordinator)
        XCTAssertEqual(r.checks.first { $0.name == "serve.launchAgent" }?.status, .ok)
        XCTAssertEqual(r.status, .ok)
    }

    /// Running agent → serve.launchAgent ok, doctor overall ok.
    func testRunningLaunchAgentKeepsDoctorOk() {
        let coordinator = DoctorResult.Coordinator(
            state: .foregroundOnly,
            detail: "foreground CLI only; background scheduler not running",
            launchAgent: .init(state: .running, pid: 4242, detail: "com.allnighter.resident-coordinator running (pid 4242)")
        )
        let r = doctorResult(coordinator: coordinator)
        XCTAssertEqual(r.checks.first { $0.name == "serve.launchAgent" }?.status, .ok)
        XCTAssertEqual(r.status, .ok)
    }

    /// The additive field round-trips through the DoctorResult contract.
    func testCoordinatorLaunchAgentCodableRoundTrip() throws {
        let coordinator = DoctorResult.Coordinator(
            state: .foregroundOnly, detail: "d",
            launchAgent: .init(state: .wedged, lastExitCode: 78, detail: "wedged")
        )
        let data = try JSONEncoder().encode(coordinator)
        let decoded = try JSONDecoder().decode(DoctorResult.Coordinator.self, from: data)
        XCTAssertEqual(decoded, coordinator)

        let absent = DoctorResult.Coordinator(state: .foregroundOnly, detail: "d")
        let absentJSON = String(decoding: try JSONEncoder().encode(absent), as: UTF8.self)
        XCTAssertFalse(absentJSON.contains("launchAgent"), "nil launchAgent must be omitted from the contract")
    }
}
