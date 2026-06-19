import XCTest
import AllnighterCore
@testable import AllnighterEngine

/// PRJ-S11b: dispatch under the execution lane. Uses a mock runner + a fresh lane
/// registry so nothing real is spawned and no repo is mutated.
final class ProjectDispatchServiceTests: XCTestCase {

    private func project() -> Project {
        Project(
            id: "prj_d", displayName: "D", localRootPath: "/tmp/disp", normalizedRootPath: "/tmp/disp",
            kind: .gitRepo, rootState: .available,
            createdAt: Date(timeIntervalSince1970: 1), lastOpenedAt: Date(timeIntervalSince1970: 1),
            proofCommands: ["true"])
    }

    private func proposal() -> ProjectProposal {
        ProjectProposal(
            id: "prop_d", projectId: "prj_d", threadId: "t", createdFromTurnId: "mgr",
            kind: .execute_slice, status: .approved, title: "Do it", scope: "x",
            createdAt: Date(timeIntervalSince1970: 2), updatedAt: Date(timeIntervalSince1970: 2))
    }

    /// A `.dispatch`-mode order targeting `claude_code`, with the worker ready.
    private func order(sourceId: String = "claude_code") -> WorkOrder {
        WorkOrder(
            id: "wo_d", proposalId: "prop_d", projectId: "prj_d", title: "Do it",
            lane: .code, mode: .dispatch, targetSourceId: sourceId,
            promptBody: "implement x", expectedReturn: "a diff", proofCommands: ["true"],
            baseGitHead: nil, localRootPathSnapshot: "/tmp/disp", createdAt: Date(timeIntervalSince1970: 3))
    }

    private func ready(_ sourceId: String = "claude_code") -> [ProjectWorkerReadiness] {
        [ProjectWorkerReadiness(projectId: "prj_d", sourceId: sourceId, workerId: nil,
                                status: .ready, checkedAt: Date(timeIntervalSince1970: 4), probeKind: .explicitRecheck)]
    }

    private func service(_ stdout: String, exit: Int32 = 0) -> ProjectDispatchService {
        let manifest = TestSupport.headlessManifest(id: "claude_code", command: "claude")
        return ProjectDispatchService(
            runner: MockCommandRunner(scripts: ["claude": .init(stdout: stdout, exitCode: exit)]),
            registry: DriverRegistry([manifest]))
    }

    func testDispatchInvokesUnderLaneAndCapturesReturn() async {
        let opus = TestSupport.worker("model_opus", driverId: "claude_code")
        let out = await service("done: edited file").dispatch(
            order: order(), project: project(), proposal: proposal(), targetModel: opus,
            workerReadiness: ready(), readyModels: [opus], currentGitHead: nil,
            dirtyFiles: [], observedRootState: .available, dirtyAcknowledged: false,
            lane: ExecutionLaneRegistry())
        guard case .dispatched(let ret) = out else { return XCTFail("expected dispatched, got \(out)") }
        XCTAssertEqual(ret.status, .returned)
        XCTAssertEqual(ret.targetWorkerId, "model_opus")
        XCTAssertEqual(ret.summary, "done: edited file")
        XCTAssertEqual(ret.workOrderId, "wo_d")
        XCTAssertTrue(ret.id.hasPrefix("ret_"))
    }

    func testWorkerFailureIsCapturedAsFailedReturnNotProof() async {
        let opus = TestSupport.worker("model_opus", driverId: "claude_code")
        let out = await service("", exit: 1).dispatch(
            order: order(), project: project(), proposal: proposal(), targetModel: opus,
            workerReadiness: ready(), readyModels: [opus], currentGitHead: nil,
            dirtyFiles: [], observedRootState: .available, dirtyAcknowledged: false,
            lane: ExecutionLaneRegistry())
        guard case .dispatched(let ret) = out else { return XCTFail("expected dispatched") }
        XCTAssertEqual(ret.status, .failed, "a failed worker is a failed return — never silently done")
    }

    func testGateBlocksWhenWorkerNotReadyInProject() async {
        let opus = TestSupport.worker("model_opus", driverId: "claude_code")
        let out = await service("done").dispatch(
            order: order(), project: project(), proposal: proposal(), targetModel: opus,
            workerReadiness: [], readyModels: [opus], currentGitHead: nil,   // no readiness → blocked
            dirtyFiles: [], observedRootState: .available, dirtyAcknowledged: false,
            lane: ExecutionLaneRegistry())
        guard case .blocked(let code, _) = out else { return XCTFail("expected blocked") }
        XCTAssertEqual(code, "WORKER_NOT_READY_IN_PROJECT")
    }

    func testMissingRootBlocksMutatingDispatch() async {
        let opus = TestSupport.worker("model_opus", driverId: "claude_code")
        let out = await service("done").dispatch(
            order: order(), project: project(), proposal: proposal(), targetModel: opus,
            workerReadiness: ready(), readyModels: [opus], currentGitHead: nil,
            dirtyFiles: [], observedRootState: .missing, dirtyAcknowledged: false,
            lane: ExecutionLaneRegistry())
        guard case .blocked(let code, _) = out else { return XCTFail("expected blocked") }
        XCTAssertEqual(code, "PROJECT_ROOT_UNAVAILABLE")
    }

    func testBaseHeadChangedBlocks() async {
        let opus = TestSupport.worker("model_opus", driverId: "claude_code")
        var ord = order(); ord.baseGitHead = "old"
        let out = await service("done").dispatch(
            order: ord, project: project(), proposal: proposal(), targetModel: opus,
            workerReadiness: ready(), readyModels: [opus], currentGitHead: "new",
            dirtyFiles: [], observedRootState: .available, dirtyAcknowledged: false,
            lane: ExecutionLaneRegistry())
        guard case .blocked(let code, _) = out else { return XCTFail("expected blocked") }
        XCTAssertEqual(code, "BASE_HEAD_CHANGED")
    }

    func testSecondConcurrentDispatchOnSameLaneIsRefused() async {
        let opus = TestSupport.worker("model_opus", driverId: "claude_code")
        let lane = ExecutionLaneRegistry()
        // Pre-hold the lane for /tmp/disp so the dispatch sees it busy.
        let key = ExecutionLane.key(workingDirectory: "/tmp/disp")
        _ = await lane.acquire(key)
        let out = await service("done").dispatch(
            order: order(), project: project(), proposal: proposal(), targetModel: opus,
            workerReadiness: ready(), readyModels: [opus], currentGitHead: nil,
            dirtyFiles: [], observedRootState: .available, dirtyAcknowledged: false,
            lane: lane)
        guard case .laneBusy = out else { return XCTFail("expected laneBusy, got \(out)") }
    }
}
