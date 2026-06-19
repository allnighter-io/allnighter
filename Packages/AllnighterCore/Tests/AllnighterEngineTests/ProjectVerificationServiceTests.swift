import XCTest
import AllnighterCore
@testable import AllnighterEngine

/// PRJ-S12: proof-command verification. A non-zero exit, timeout, or unrunnable
/// command never yields `verified`. Uses a mock runner — no real proof runs.
final class ProjectVerificationServiceTests: XCTestCase {

    private func project() -> Project {
        Project(id: "prj_v", displayName: "V", localRootPath: "/tmp/v", normalizedRootPath: "/tmp/v",
                kind: .gitRepo, rootState: .available,
                createdAt: Date(timeIntervalSince1970: 1), lastOpenedAt: Date(timeIntervalSince1970: 1))
    }

    private func order(proof: [String], waiver: String? = nil, root: String = "/tmp/v") -> WorkOrder {
        WorkOrder(id: "wo_v", proposalId: "prop_v", projectId: "prj_v", title: "t", lane: .code,
                  mode: .dispatch, promptBody: "p", expectedReturn: "r", proofCommands: proof,
                  proofWaiver: waiver, localRootPathSnapshot: root, createdAt: Date(timeIntervalSince1970: 2))
    }

    private func service(_ scripts: [String: MockCommandRunner.Script]) -> ProjectVerificationService {
        // Proof commands run as `/bin/sh -c <cmd>`, so the mock keys on "/bin/sh".
        ProjectVerificationService(runner: MockCommandRunner(scripts: scripts, fallback: scripts["/bin/sh"] ?? .init()),
                                   git: GitObserver())
    }

    func testAllProofPassesVerified() async {
        let svc = service(["/bin/sh": .init(stdout: "ok", exitCode: 0)])
        let rec = await svc.verify(workOrder: order(proof: ["swift test", "swift build"]), workReturn: nil, project: project())
        XCTAssertEqual(rec.outcome, .verified)
        XCTAssertEqual(rec.proofResults.count, 2)
        XCTAssertTrue(rec.proofResults.allSatisfy(\.passed))
    }

    func testNonzeroExitIsNotVerifiedNeverDone() async {
        let svc = service(["/bin/sh": .init(stdout: "boom", exitCode: 1)])
        let rec = await svc.verify(workOrder: order(proof: ["swift test"]), workReturn: nil, project: project())
        XCTAssertEqual(rec.outcome, .notVerified)
        XCTAssertFalse(rec.outcome.isDone, "a failed proof never advances to done")
    }

    func testTimeoutIsNotVerified() async {
        let svc = service(["/bin/sh": .init(forcesTimeout: true)])
        let rec = await svc.verify(workOrder: order(proof: ["sleep 999"]), workReturn: nil, project: project())
        XCTAssertEqual(rec.outcome, .notVerified)
        XCTAssertTrue(rec.proofResults.first?.timedOut ?? false)
    }

    func testCommandAllnighterCannotRunIsNeedsHuman() async {
        let svc = service(["/bin/sh": .init(launchError: "no /bin/sh")])
        let rec = await svc.verify(workOrder: order(proof: ["swift test"]), workReturn: nil, project: project())
        XCTAssertEqual(rec.outcome, .needsHuman, "if Allnighter can't run proof, a human must — not a fail")
        XCTAssertEqual(rec.missingProof, ["swift test"])
    }

    func testNoCommandsWithWaiverIsWaived() async {
        let svc = service([:])
        let rec = await svc.verify(workOrder: order(proof: [], waiver: "no proof for this folder"), workReturn: nil, project: project())
        XCTAssertEqual(rec.outcome, .waived)
        XCTAssertTrue(rec.outcome.isDone)
    }

    func testNoCommandsNoWaiverIsNeedsHuman() async {
        let rec = await service([:]).verify(workOrder: order(proof: []), workReturn: nil, project: project())
        XCTAssertEqual(rec.outcome, .needsHuman)
    }

    /// Integration: actually spawn `/bin/sh -c` via SubprocessCommandRunner so the
    /// real proof path is exercised end-to-end (deterministic shell builtins).
    func testRealSubprocessProofPassAndFail() async {
        let tmp = NSTemporaryDirectory()
        let p = Project(id: "prj_rs", displayName: "RS", localRootPath: tmp, normalizedRootPath: tmp,
                        kind: .folder, rootState: .available,
                        createdAt: Date(timeIntervalSince1970: 1), lastOpenedAt: Date(timeIntervalSince1970: 1))
        let svc = ProjectVerificationService(runner: SubprocessCommandRunner())
        let pass = await svc.verify(workOrder: order(proof: ["true"], root: tmp), workReturn: nil, project: p)
        XCTAssertEqual(pass.outcome, .verified)
        let fail = await svc.verify(workOrder: order(proof: ["false"], root: tmp), workReturn: nil, project: p)
        XCTAssertEqual(fail.outcome, .notVerified)
        XCTAssertEqual(fail.proofResults.first?.exitCode, 1)
    }

    func testRevealOnlyDoesNotRunProof() async {
        // forcesTimeout would hang if run; reveal-only must not invoke it.
        let svc = service(["/bin/sh": .init(forcesTimeout: true)])
        let rec = await svc.verify(workOrder: order(proof: ["swift test"], waiver: nil), workReturn: nil, project: project(), runProof: false)
        XCTAssertEqual(rec.outcome, .needsHuman)
        XCTAssertTrue(rec.proofResults.isEmpty, "reveal-only runs nothing")
        XCTAssertEqual(rec.missingProof, ["swift test"])
    }
}
