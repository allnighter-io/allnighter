import XCTest
@testable import AllnighterCore
@testable import AllnighterEngine

/// CONT-S1c: the pure session decision layer — which argv a turn runs and which vendor id
/// it carries. This is the policy the streaming runner delegates to.
final class WorkerSessionPlannerTests: XCTestCase {

    private let setSession = DriverManifest.Session(
        continuity: .vendorSession, acquire: .set,
        firstTurnArgs: ["--session-id", "{{sessionId}}"], resumeArgs: ["--resume", "{{sessionId}}"])
    private let captureSession = DriverManifest.Session(
        continuity: .vendorSession, acquire: .capture,
        resumeArgs: ["--resume", "{{sessionId}}"],
        capture: .init(from: .streamJson, field: "session_id"))

    /// Stand-in for `manifest.resolvedSessionArgs` — echoes the id + resuming flag.
    private func resolver(_ id: String?, _ resuming: Bool) -> [String]? {
        guard let id else { return nil }
        return resuming ? ["--resume", id] : ["--session-id", id]
    }

    func testResumePlansResumeArgsAndKeepsId() {
        let plan = WorkerSessionPlan(session: captureSession, resumeSessionId: "stored-9", mintSessionId: nil)
        let (args, id) = WorkerSessionPlanner.plan(plan, resolveArgs: resolver)
        XCTAssertEqual(args, ["--resume", "stored-9"])
        XCTAssertEqual(id, "stored-9")
    }

    func testSetFirstTurnMintsAndAssigns() {
        let plan = WorkerSessionPlan(session: setSession, resumeSessionId: nil, mintSessionId: "minted-7")
        let (args, id) = WorkerSessionPlanner.plan(plan, resolveArgs: resolver)
        XCTAssertEqual(args, ["--session-id", "minted-7"])
        XCTAssertEqual(id, "minted-7")
    }

    func testCaptureFirstTurnRunsBaseArgs() {
        let plan = WorkerSessionPlan(session: captureSession, resumeSessionId: nil, mintSessionId: nil)
        let (args, id) = WorkerSessionPlanner.plan(plan, resolveArgs: resolver)
        XCTAssertNil(args, "capture first turn uses the base args")
        XCTAssertNil(id, "id is captured from output, not planned")
    }

    func testNoPlanOrPromptContextOnly() {
        XCTAssertEqual(WorkerSessionPlanner.plan(nil, resolveArgs: resolver).args, nil)
        let agy = WorkerSessionPlan(
            session: .init(continuity: .promptContextOnly), resumeSessionId: "x", mintSessionId: nil)
        XCTAssertNil(WorkerSessionPlanner.plan(agy, resolveArgs: resolver).args)
    }

    func testCapturedIdResumeAndMintPassThrough() {
        let resume = WorkerSessionPlan(session: captureSession, resumeSessionId: "r", mintSessionId: nil)
        XCTAssertEqual(WorkerSessionPlanner.capturedId(resume, plannedSessionId: "r", stdout: "", outputFileContents: nil), "r")
        let mint = WorkerSessionPlan(session: setSession, resumeSessionId: nil, mintSessionId: "m")
        XCTAssertEqual(WorkerSessionPlanner.capturedId(mint, plannedSessionId: "m", stdout: "", outputFileContents: nil), "m")
    }

    func testCapturedIdReadsFromOutputOnCaptureFirstTurn() {
        let plan = WorkerSessionPlan(session: captureSession, resumeSessionId: nil, mintSessionId: nil)
        let stdout = #"{"type":"init","session_id":"cap-42"}"#
        XCTAssertEqual(WorkerSessionPlanner.capturedId(plan, plannedSessionId: nil, stdout: stdout, outputFileContents: nil), "cap-42")
    }
}
