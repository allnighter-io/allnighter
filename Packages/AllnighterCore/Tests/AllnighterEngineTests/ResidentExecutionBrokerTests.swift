import XCTest
import AllnighterCore
@testable import AllnighterEngine

final class ResidentExecutionBrokerTests: XCTestCase {
    func testBrokerAcceptsHealthAndRejectsUnrunnableTeamWithoutForegroundFallback() async throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("resident-broker-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)

        let rendezvous = ResidentExecutionRendezvous(root: root.appendingPathComponent("rendezvous", isDirectory: true))
        _ = try rendezvous.prepareCoordinator(
            coordinatorId: "coord", binaryVersion: "1", contractVersion: ContractRegistry.contractVersion
        )
        let service = AsyncTeamService(
            models: [], registry: DefaultConfig.registry,
            runStore: RunStore(rootDirectory: root.appendingPathComponent("runs", isDirectory: true))
        )
        let cancelled = BrokerCancellation()
        let broker = ResidentExecutionBroker(
            rendezvous: rendezvous,
            dependencies: .init(asyncTeam: service, readyModels: { [] }, executablePath: { "/usr/bin/false" })
        )
        let task = Task { await broker.run(isCancelled: { cancelled.value }) }
        defer {
            cancelled.value = true
            task.cancel()
        }

        let health = try rendezvous.submit(
            operation: .query(.init(kind: .health)), idempotencyKey: "health", requestId: "health-request"
        )
        let healthMaybeReceipt = try await rendezvous.waitForReceipt(requestId: health.requestId)
        let healthReceipt = try XCTUnwrap(healthMaybeReceipt)
        XCTAssertEqual(healthReceipt.state, .accepted)
        XCTAssertEqual(healthReceipt.canonicalId, "coord")

        let missingStatus = try rendezvous.submit(
            operation: .query(.init(kind: .runStatus, canonicalId: "missing")),
            idempotencyKey: "missing-status", requestId: "missing-status-request"
        )
        let missingStatusMaybeReceipt = try await rendezvous.waitForReceipt(requestId: missingStatus.requestId)
        let missingStatusReceipt = try XCTUnwrap(missingStatusMaybeReceipt)
        XCTAssertEqual(missingStatusReceipt.state, .rejected)
        XCTAssertEqual(missingStatusReceipt.rejection?.code, "RUN_NOT_FOUND")

        let foreground = try rendezvous.submit(
            operation: .foregroundTeamRun(.init(message: "hello", repoRoot: root.path)),
            idempotencyKey: "foreground", requestId: "foreground-request"
        )
        let foregroundMaybeReceipt = try await rendezvous.waitForReceipt(requestId: foreground.requestId)
        let foregroundReceipt = try XCTUnwrap(foregroundMaybeReceipt)
        XCTAssertEqual(foregroundReceipt.state, .rejected)
        XCTAssertEqual(foregroundReceipt.rejection?.code, "DEFAULT_TEAM_INVALID")

        let team = try rendezvous.submit(
            operation: .teamRun(.init(question: "hello", repoRoot: root.path)),
            idempotencyKey: "team", requestId: "team-request"
        )
        let teamMaybeReceipt = try await rendezvous.waitForReceipt(requestId: team.requestId)
        let teamReceipt = try XCTUnwrap(teamMaybeReceipt)
        XCTAssertEqual(teamReceipt.state, .rejected)
        XCTAssertNotNil(teamReceipt.rejection, "unrunnable request is classified, never executed in the client")
    }
}

private final class BrokerCancellation: @unchecked Sendable {
    private let lock = NSLock()
    private var stored = false
    var value: Bool {
        get { lock.withLock { stored } }
        set { lock.withLock { stored = newValue } }
    }
}

private extension NSLock {
    func withLock<T>(_ body: () -> T) -> T {
        lock()
        defer { unlock() }
        return body()
    }
}
