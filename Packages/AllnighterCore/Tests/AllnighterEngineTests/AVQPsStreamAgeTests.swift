import XCTest
import AllnighterCore
@testable import AllnighterEngine

/// AVQ-S02 — `alln ps` human table labels stream age accurately and marks stale.
final class AVQPsStreamAgeTests: XCTestCase {
    func testHumanTableSaysStreamAgeNotHeartbeatAge() {
        let row = OwnershipProcessJSON(
            id: "run_stale",
            kind: "run",
            projectRoot: "/tmp/repo",
            identity: nil,
            identityAlive: true,
            wouldReconcile: false,
            lastProgressAt: Date().addingTimeInterval(-120),
            heartbeatAgeSeconds: 120,
            progressStale: true,
            endReason: nil,
            status: "running",
            phase: "working",
            silenceStatus: "alive, no stream for 120s"
        )
        let envelope = OwnershipPsJSON(countedAt: Date(), processes: [row])
        let table = ProcessOwnershipSurface.humanTable(envelope)
        XCTAssertTrue(table.contains("STREAM_AGE"), table)
        XCTAssertFalse(table.contains("HB_AGE"), table)
        XCTAssertTrue(table.contains("STALE"), "stale owner must be marked on the primary row: \(table)")
        XCTAssertTrue(table.contains("120s") || table.contains("120"), table)
    }

    func testHumanTableFreshStreamNotMarkedStale() {
        let row = OwnershipProcessJSON(
            id: "run_fresh",
            kind: "run",
            projectRoot: "/tmp/repo",
            identity: nil,
            identityAlive: true,
            wouldReconcile: false,
            lastProgressAt: Date().addingTimeInterval(-5),
            heartbeatAgeSeconds: 5,
            progressStale: false,
            endReason: nil,
            status: "running",
            phase: "working"
        )
        let table = ProcessOwnershipSurface.humanTable(
            OwnershipPsJSON(countedAt: Date(), processes: [row])
        )
        XCTAssertTrue(table.contains("STREAM_AGE"))
        XCTAssertFalse(table.contains("*STALE"))
    }
}
