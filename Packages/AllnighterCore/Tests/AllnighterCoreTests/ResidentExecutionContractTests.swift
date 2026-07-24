import XCTest
@testable import AllnighterCore

final class ResidentExecutionContractTests: XCTestCase {
    func testLongResidentOperationsHaveExplicitWaitBudgets() {
        XCTAssertEqual(ResidentExecutionWaitBudget.sourceProbe, 130)
        XCTAssertEqual(ResidentExecutionWaitBudget.panelRound, 1_800)
    }

    func testPendingRunOperationRoundTripsThroughBrokerContract() throws {
        let operation = ResidentExecutionOperation.pendingRun(.init(pendingItemId: "pending_123"))

        let decoded = try CoreJSON.decode(
            ResidentExecutionOperation.self,
            from: CoreJSON.encode(operation)
        )

        XCTAssertEqual(decoded, operation)
    }

    func testProjectRecheckOperationRoundTripsThroughBrokerContract() throws {
        let operation = ResidentExecutionOperation.projectRecheck(
            .init(projectId: "project_123", rootPath: "/tmp/project")
        )

        let decoded = try CoreJSON.decode(
            ResidentExecutionOperation.self,
            from: CoreJSON.encode(operation)
        )

        XCTAssertEqual(decoded, operation)
    }

    func testSourceProbeRoundTripsACommitIdentityWithoutAWorkspacePath() throws {
        let operation = ResidentExecutionOperation.sourceProbe(.init(
            sourceId: "codex",
            full: false,
            workspaceHeadSha: "0123456789abcdef0123456789abcdef01234567"
        ))

        let decoded = try CoreJSON.decode(
            ResidentExecutionOperation.self,
            from: CoreJSON.encode(operation)
        )

        XCTAssertEqual(decoded, operation)
        guard case let .sourceProbe(payload) = decoded else {
            return XCTFail("expected source probe")
        }
        XCTAssertNil(payload.workingDirectory)
        XCTAssertEqual(payload.workspaceHeadSha, "0123456789abcdef0123456789abcdef01234567")
    }
}
