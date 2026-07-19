import XCTest
import AllnighterCore
@testable import AllnighterEngine

final class UtilizationSeedExecutorTests: XCTestCase {
    private func tempLedger() -> UtilizationSeedLedger {
        let file = FileManager.default.temporaryDirectory
            .appendingPathComponent("seed-ledger-\(UUID().uuidString).json")
        return UtilizationSeedLedger(fileURL: file)
    }

    private func claudeWorker() -> Model {
        TestSupport.worker("w", driverId: "claude_code", model: "opus")
    }

    func testSuccessfulSeedRecordsEvent() async {
        let manifest = TestSupport.headlessManifest(id: "claude_code", command: "claude")
        let registry = DriverRegistry([manifest])
        let runner = MockCommandRunner(scripts: ["claude": .init(stdout: "ready", exitCode: 0)])
        let ledger = tempLedger()
        let executor = UtilizationSeedExecutor(
            models: [claudeWorker()],
            registry: registry,
            commandRunner: runner,
            seedLedger: ledger
        )
        let settings = BoostWindowSettings(enabled: true, windowStart: 8 * 60, appliesTo: ["claude_code"])
        let event = await executor.execute(sourceId: "claude_code", settings: settings, force: true)
        XCTAssertEqual(event.outcome, UtilizationSeedOutcome.succeeded)
        XCTAssertEqual(ledger.load().count, 1)
    }

    func testAuthFailureMapsToAuthRequired() async {
        let manifest = TestSupport.headlessManifest(id: "claude_code", command: "claude")
        let registry = DriverRegistry([manifest])
        let runner = MockCommandRunner(scripts: [
            "claude": .init(stderr: "Please run /login to continue", exitCode: 1)
        ])
        let executor = UtilizationSeedExecutor(
            models: [claudeWorker()],
            registry: registry,
            commandRunner: runner,
            seedLedger: tempLedger()
        )
        let settings = BoostWindowSettings(enabled: true, appliesTo: ["claude_code"])
        let event = await executor.execute(sourceId: "claude_code", settings: settings, force: true)
        XCTAssertEqual(event.outcome, UtilizationSeedOutcome.authRequired)
    }

    func testDaytimeWindowWithoutForceReturnsNoQuietRunUp() async {
        let manifest = TestSupport.headlessManifest(id: "claude_code", command: "claude")
        let registry = DriverRegistry([manifest])
        let executor = UtilizationSeedExecutor(
            models: [claudeWorker()],
            registry: registry,
            commandRunner: MockCommandRunner(scripts: [:]),
            seedLedger: tempLedger()
        )
        let settings = BoostWindowSettings(enabled: true, windowStart: 14 * 60, appliesTo: ["claude_code"])
        let event = await executor.execute(sourceId: "claude_code", settings: settings, force: false)
        XCTAssertEqual(event.outcome, UtilizationSeedOutcome.noQuietRunUp)
    }

    func testCapacityReaderPicksLatestReset() {
        let obs = CapacityObservation(
            kind: .accountRateLimit,
            source: "claude_code",
            sourceConfidence: .structured,
            rawSnippet: "limited",
            observedAt: Date(timeIntervalSince1970: 100),
            observedResetAt: Date(timeIntervalSince1970: 500)
        )
        let ledger = tempLedger()
        let event = UtilizationSeedEvent(
            sourceId: "claude_code",
            outcome: .rateLimited,
            capacityObservation: obs
        )
        try? ledger.append(event)
        let map = UtilizationCapacityReader.lastObservedResetPerSource(
            runStore: RunStore(rootDirectory: FileManager.default.temporaryDirectory.appendingPathComponent("empty-runs-\(UUID().uuidString)")),
            seedLedger: ledger,
            now: Date(timeIntervalSince1970: 600)
        )
        XCTAssertEqual(map["claude_code"], Date(timeIntervalSince1970: 500))
    }

}

final class UtilizationCapacityReaderTests: XCTestCase {
    private func tempLedger() -> UtilizationSeedLedger {
        let file = FileManager.default.temporaryDirectory
            .appendingPathComponent("seed-ledger-\(UUID().uuidString).json")
        return UtilizationSeedLedger(fileURL: file)
    }

    func testFutureResetFromOldRunSurvivesLookback() throws {
        let now = Date(timeIntervalSince1970: 2_000_000)
        let reset = now.addingTimeInterval(5 * 24 * 60 * 60)
        let observation = CapacityObservation(
            kind: .accountRateLimit,
            source: "claude_code",
            sourceConfidence: .structured,
            rawSnippet: "weekly limit",
            observedAt: now.addingTimeInterval(-2 * 24 * 60 * 60),
            observedResetAt: reset
        )
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("old-capacity-run-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let store = RunStore(rootDirectory: root)
        let run = TeamRun(
            id: "old",
            prompt: "p",
            status: .failed,
            createdAt: now.addingTimeInterval(-2 * 24 * 60 * 60),
            attempts: [
                RunAttempt(
                    attemptNumber: 1,
                    startedAt: now.addingTimeInterval(-2 * 24 * 60 * 60),
                    endedAt: now.addingTimeInterval(-2 * 24 * 60 * 60),
                    capacityObservation: observation,
                    terminalStatus: .failed
                ),
            ]
        )
        try store.save(run, models: [])

        let map = UtilizationCapacityReader.lastObservedResetPerSource(
            runStore: store,
            seedLedger: tempLedger(),
            now: now
        )
        XCTAssertEqual(map["claude_code"], reset)
    }
}
