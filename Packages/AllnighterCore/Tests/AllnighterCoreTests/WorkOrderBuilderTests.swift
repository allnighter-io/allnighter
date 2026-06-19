import XCTest
import AllnighterCore

/// PRJ-S10: the pure derivation of a WorkOrder from an approved proposal, and the
/// approval content hash that lets dispatch detect edits-after-approval.
final class WorkOrderBuilderTests: XCTestCase {

    private func project(proofCommands: [String] = []) -> Project {
        Project(
            id: "prj_1", displayName: "Demo", localRootPath: "/tmp/demo", normalizedRootPath: "/tmp/demo",
            kind: .gitRepo, createdAt: Date(timeIntervalSince1970: 1), lastOpenedAt: Date(timeIntervalSince1970: 1),
            proofCommands: proofCommands)
    }

    private func proposal(kind: ProposalKind = .execute_slice, lane: WorkLane? = .code) -> ProjectProposal {
        ProjectProposal(
            id: "prop_1", projectId: "prj_1", threadId: "t", createdFromTurnId: "mgr_1",
            kind: kind, title: "Do the thing", whyNow: "now", userGoal: "ship",
            scope: "one file", nonGoals: ["no CI"], risks: ["flaky"], suggestedLane: lane,
            createdAt: Date(timeIntervalSince1970: 2), updatedAt: Date(timeIntervalSince1970: 2))
    }

    func testBuildMapsLaneAndExpectedReturnAndIsRevealMode() {
        let wo = WorkOrderBuilder.build(from: proposal(lane: .design), project: project(proofCommands: ["swift test"]),
                                        baseGitHead: "abc123", now: Date(timeIntervalSince1970: 9), idSuffix: "deadbeef")
        XCTAssertEqual(wo.id, "wo_deadbeef")
        XCTAssertEqual(wo.lane, .design)
        XCTAssertEqual(wo.mode, .reveal, "approve creates a reveal-mode order; dispatch is a separate action")
        XCTAssertEqual(wo.proofCommands, ["swift test"])
        XCTAssertNil(wo.proofWaiver)
        XCTAssertEqual(wo.baseGitHead, "abc123")
        XCTAssertEqual(wo.localRootPathSnapshot, "/tmp/demo")
        XCTAssertTrue(wo.expectedReturn.contains("diff"))
        XCTAssertTrue(wo.isDispatchReady)
    }

    func testNoProofCommandsForcesExplicitWaiverStillDispatchReady() {
        let wo = WorkOrderBuilder.build(from: proposal(), project: project(proofCommands: []),
                                        baseGitHead: nil, now: Date(timeIntervalSince1970: 9), idSuffix: "x")
        XCTAssertTrue(wo.proofCommands.isEmpty)
        XCTAssertNotNil(wo.proofWaiver, "no commands → an explicit waiver, never silently nothing")
        XCTAssertTrue(wo.isDispatchReady, "a waiver satisfies the proof requirement")
    }

    func testSignalLaneMapsToNone() {
        let wo = WorkOrderBuilder.build(from: proposal(lane: .signal), project: project(proofCommands: ["x"]),
                                        baseGitHead: nil, now: Date(timeIntervalSince1970: 9), idSuffix: "x")
        XCTAssertEqual(wo.lane, .none)
    }

    func testApprovalContentHashIsStableAndContentSensitive() {
        let a = WorkOrderBuilder.approvalContentHash(proposal())
        let b = WorkOrderBuilder.approvalContentHash(proposal())
        XCTAssertEqual(a, b, "same content → same hash")
        var edited = proposal(); edited.scope = "two files"
        XCTAssertNotEqual(a, WorkOrderBuilder.approvalContentHash(edited), "an edit changes the hash")
        // Status/timestamps are NOT part of the content hash.
        var reStatused = proposal(); reStatused.status = .approved; reStatused.updatedAt = Date()
        XCTAssertEqual(a, WorkOrderBuilder.approvalContentHash(reStatused))
    }
}
