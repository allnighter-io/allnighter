import XCTest
@testable import AllnighterCore

/// RLR-S01a design spine: the frozen public `RunLifecycle`/`RunPhase` and the
/// total `RunStatus.lifecycle` projection every surface converges onto (RLR-L3).
final class RunLifecycleProjectionTests: XCTestCase {

    // MARK: - Totality

    func testEveryRunStatusProjectsToALifecycle() {
        // Exhaustive by construction: `.lifecycle` is a total switch. Assert the
        // expected mapping for every durable case so a future case-add is caught.
        let expected: [RunStatus: RunLifecycle] = [
            .draft: .queued,
            .queued: .queued,
            .running: .running,
            .fanningOut: .running,
            .answersIn: .running,
            .planning: .running,
            .reviewing: .running,
            .finalizing: .running,
            .complete: .done,
            .partial: .done,
            .done: .done,
            .timedOut: .timedOut,
            .cancelled: .cancelled,
            .failed: .failed,
            .interrupted: .failed,
        ]
        XCTAssertEqual(Set(expected.keys), Set(RunStatus.allCases),
                       "every RunStatus needs an explicit lifecycle expectation")
        for status in RunStatus.allCases {
            XCTAssertEqual(status.lifecycle, expected[status],
                           "\(status).lifecycle mismatch")
        }
    }

    // MARK: - Terminality agreement

    func testLifecycleTerminalityAgreesWithRunStatus() {
        for status in RunStatus.allCases {
            XCTAssertEqual(status.isTerminal, status.lifecycle.isTerminal,
                           "\(status).isTerminal must agree with its lifecycle projection")
        }
    }

    func testRunLifecycleTerminality() {
        XCTAssertFalse(RunLifecycle.queued.isTerminal)
        XCTAssertFalse(RunLifecycle.running.isTerminal)
        XCTAssertTrue(RunLifecycle.done.isTerminal)
        XCTAssertTrue(RunLifecycle.failed.isTerminal)
        XCTAssertTrue(RunLifecycle.timedOut.isTerminal)
        XCTAssertTrue(RunLifecycle.cancelled.isTerminal)
    }

    // MARK: - Phase ↔ lifecycle legality table (RLR-L3)

    func testPhaseLifecycleLegalityTable() {
        XCTAssertEqual(RunPhase.waitingForWriteLock.lifecycle, .queued)
        XCTAssertEqual(RunPhase.spawningWorker.lifecycle, .queued)
        XCTAssertEqual(RunPhase.working.lifecycle, .running)
        XCTAssertEqual(RunPhase.proving.lifecycle, .running)
        XCTAssertEqual(RunPhase.settling.lifecycle, .running)
        // Every phase is legal only under a non-terminal lifecycle.
        for phase in RunPhase.allCases {
            XCTAssertFalse(phase.lifecycle.isTerminal, "\(phase) must map to a non-terminal lifecycle")
        }
    }

    // MARK: - Durable phase field

    func testTeamRunPhaseDefaultsNilAndRoundTrips() throws {
        let run = TeamRun(id: "r", prompt: "p", status: .running, phase: .working, createdAt: Date(timeIntervalSince1970: 0))
        let data = try CoreJSON.encode(run)
        let decoded = try CoreJSON.decode(TeamRun.self, from: data)
        XCTAssertEqual(decoded.phase, .working)

        // Legacy journal with no `phase` key decodes to nil.
        let legacy = TeamRun(id: "r2", prompt: "p", status: .fanningOut, createdAt: Date(timeIntervalSince1970: 0))
        XCTAssertNil(legacy.phase)
        let legacyDecoded = try CoreJSON.decode(TeamRun.self, from: CoreJSON.encode(legacy))
        XCTAssertNil(legacyDecoded.phase)
    }
}
