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
}
