import XCTest
@testable import AllnighterCore

final class ResidentExecutionContractTests: XCTestCase {
    func testPendingRunOperationRoundTripsThroughBrokerContract() throws {
        let operation = ResidentExecutionOperation.pendingRun(.init(pendingItemId: "pending_123"))

        let decoded = try CoreJSON.decode(
            ResidentExecutionOperation.self,
            from: CoreJSON.encode(operation)
        )

        XCTAssertEqual(decoded, operation)
    }
}
