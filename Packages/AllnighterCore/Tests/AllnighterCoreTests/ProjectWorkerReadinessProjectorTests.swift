import XCTest
import AllnighterCore

final class ProjectWorkerReadinessProjectorTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_750_000_000)

    private func unsafeRow(sourceId: String = "claude_code") -> ProjectWorkerReadiness {
        ProjectWorkerReadiness(
            projectId: "prj_1", sourceId: sourceId, status: .unsafeToProbe,
            checkedAt: now, probeKind: .explicitRecheck
        )
    }

    func testUnsafeToProbeDetailWhenGlobalReady() {
        let detail = ProjectWorkerReadinessProjector.unsafeToProbeDetail(globalSeatReady: true)
        XCTAssertEqual(
            detail,
            "global seat ready; project-level trust unprobed (driver declares no safe probe); pilot/relay may start — this is not a blocker."
        )
    }

    func testUnsafeToProbeDetailWhenGlobalNotReady() {
        let detail = ProjectWorkerReadinessProjector.unsafeToProbeDetail(globalSeatReady: false)
        XCTAssertTrue(detail.hasPrefix("global seat not ready;"))
        XCTAssertTrue(detail.contains("pilot/relay may start — this is not a blocker."))
    }

    func testPilotReadyFromGlobalProbeOnly() {
        let records = [
            ToolProbeRecord(driverId: "claude_code", status: .ready(version: "1"), lastProbeAt: now),
            ToolProbeRecord(driverId: "codex", status: .notInstalled, lastProbeAt: now),
        ]
        let rows = ProjectWorkerReadinessProjector.build(
            workers: [unsafeRow(sourceId: "claude_code"), unsafeRow(sourceId: "codex")],
            probeRecords: records
        )
        XCTAssertEqual(rows[0].pilotReady, true)
        XCTAssertEqual(rows[1].pilotReady, false)
        XCTAssertEqual(rows[0].setupHint, ProjectWorkerReadinessProjector.unsafeToProbeDetail(globalSeatReady: true))
        XCTAssertEqual(rows[1].setupHint, ProjectWorkerReadinessProjector.unsafeToProbeDetail(globalSeatReady: false))
    }

    func testReadyProjectStatusKeepsProbeFacts() {
        let worker = ProjectWorkerReadiness(
            projectId: "prj_1", sourceId: "claude_code", status: .ready,
            checkedAt: now, probeKind: .explicitRecheck, lastError: nil
        )
        let rows = ProjectWorkerReadinessProjector.build(
            workers: [worker],
            probeRecords: [ToolProbeRecord(driverId: "claude_code", status: .ready(version: "1"), lastProbeAt: now)]
        )
        XCTAssertTrue(rows[0].pilotReady)
        XCTAssertNil(rows[0].lastError)
        XCTAssertNil(rows[0].setupHint)
    }
}
