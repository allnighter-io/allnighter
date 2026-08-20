import XCTest
@testable import AllnighterCore

final class StuckRunDisclosureTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private var silentAt: Date {
        now.addingTimeInterval(-(StreamLiveness.waitHintSeconds * StreamLiveness.warningMultiplier + 1))
    }
    private var freshAt: Date { now.addingTimeInterval(-10) }

    func testTerminalRunEmitsNothing() {
        let facts = StuckRunDisclosure.Facts(
            subjectId: "holder",
            subjectIsTerminal: true,
            subjectMutating: true,
            subjectLastActivityAt: silentAt,
            subjectBaselineHead: "aaa",
            currentHead: "bbb",
            now: now
        )
        XCTAssertNil(StuckRunDisclosure.evaluate(facts))
    }

    func testReadOnlyRunEmitsNothing() {
        let facts = StuckRunDisclosure.Facts(
            subjectId: "r",
            subjectIsTerminal: false,
            subjectMutating: false,
            subjectLastActivityAt: silentAt,
            subjectBaselineHead: "aaa",
            currentHead: "bbb",
            now: now
        )
        XCTAssertNil(StuckRunDisclosure.evaluate(facts))
    }

    func testMissingBaselineFailsClosed() {
        let facts = StuckRunDisclosure.Facts(
            subjectId: "holder",
            subjectIsTerminal: false,
            subjectMutating: true,
            subjectLastActivityAt: silentAt,
            subjectBaselineHead: nil,
            currentHead: "bbb",
            now: now
        )
        XCTAssertNil(StuckRunDisclosure.evaluate(facts))
    }

    func testHeadUnchangedEmitsNothing() {
        let facts = StuckRunDisclosure.Facts(
            subjectId: "holder",
            subjectIsTerminal: false,
            subjectMutating: true,
            subjectLastActivityAt: silentAt,
            subjectBaselineHead: "aaa",
            currentHead: "aaa",
            now: now
        )
        XCTAssertNil(StuckRunDisclosure.evaluate(facts))
    }

    func testLandedButNotSilentDisclosesGitWithoutStop() throws {
        let facts = StuckRunDisclosure.Facts(
            subjectId: "holder",
            subjectIsTerminal: false,
            subjectMutating: true,
            subjectLastActivityAt: freshAt,
            subjectBaselineHead: "aaa",
            currentHead: "bbb",
            commits: [.init(sha: "bbb", subject: "landed")],
            now: now
        )
        let result = StuckRunDisclosure.evaluate(facts)
        let activity = try XCTUnwrap(result?.repoActivity)
        XCTAssertTrue(activity.changedDuringRunWindow)
        XCTAssertEqual(activity.attribution, "notProven")
        XCTAssertNil(result?.stopRunId)
        XCTAssertNil(result?.warning)
    }

    func testSilentHolderWithLandedFilesRecommendsStop() throws {
        let facts = StuckRunDisclosure.Facts(
            subjectId: "holder",
            subjectIsTerminal: false,
            subjectMutating: true,
            subjectLastActivityAt: silentAt,
            subjectBaselineHead: "aaa",
            currentHead: "bbb",
            now: now
        )
        let result = try XCTUnwrap(StuckRunDisclosure.evaluate(facts))
        XCTAssertEqual(result.stopRunId, "holder")
        XCTAssertTrue(result.warning?.contains("Files already landed") == true)
        XCTAssertEqual(StuckRunDisclosure.stopAction(runId: "holder").command, "alln kill holder --json")
        XCTAssertEqual(StuckRunDisclosure.stopAction(runId: "holder").kind, .stopStuckRun)
    }

    func testWaiterRecommendsKillingTheHolderNotItself() throws {
        let facts = StuckRunDisclosure.Facts(
            subjectId: "waiter",
            subjectIsTerminal: false,
            subjectMutating: true,
            waitingOnWriteLock: true,
            holderId: "holder",
            holderIsTerminal: false,
            holderLastActivityAt: silentAt,
            holderBaselineHead: "aaa",
            currentHead: "bbb",
            now: now
        )
        let result = try XCTUnwrap(StuckRunDisclosure.evaluate(facts))
        XCTAssertEqual(result.stopRunId, "holder")
        XCTAssertTrue(result.warning?.contains("You're waiting on job holder") == true)
        XCTAssertNotEqual(result.stopRunId, "waiter")
    }

    func testWaiterDoesNotInferOwnWorkFromGit() {
        // Waiter's own baseline is irrelevant; without a silent holder window, no stop.
        let facts = StuckRunDisclosure.Facts(
            subjectId: "waiter",
            subjectIsTerminal: false,
            subjectMutating: true,
            subjectBaselineHead: "ccc",
            waitingOnWriteLock: true,
            holderId: "holder",
            holderLastActivityAt: freshAt,
            holderBaselineHead: "aaa",
            currentHead: "bbb",
            now: now
        )
        let result = StuckRunDisclosure.evaluate(facts)
        XCTAssertNil(result?.stopRunId)
        XCTAssertEqual(result?.repoActivity.attribution, "notProven")
    }

    func testMapperPrependsStopAndDoesNotFlipObservation() throws {
        var run = TeamRun(
            id: "holder", prompt: "p", status: .running, phase: .working,
            createdAt: now, mutating: true, lastActivityAt: silentAt
        )
        run.baselineHead = "aaa"
        let disclosure = StuckRunDisclosure.Result(
            repoActivity: .init(
                changedDuringRunWindow: true, attribution: "notProven",
                baseline: "aaa", head: "bbb"),
            stopRunId: "holder",
            warning: "Files already landed in git, but this job still shows running. That does not mean the job is done. Stop it so the next job can start."
        )
        let trj = TeamRunJSONMapper.map(
            run, models: [], manifests: [],
            context: .init(stuckDisclosure: disclosure)
        )
        XCTAssertEqual(trj.teamRun.status, .running)
        XCTAssertEqual(trj.observation.ownerState, .unknown)
        XCTAssertEqual(trj.repoActivity?.attribution, "notProven")
        XCTAssertEqual(trj.nextActions.first?.kind, .stopStuckRun)
        XCTAssertEqual(trj.nextActions.first?.command, "alln kill holder --json")
        XCTAssertEqual(trj.warnings.first?.message, disclosure.warning)
        XCTAssertNil(trj.outcome)
    }
}
