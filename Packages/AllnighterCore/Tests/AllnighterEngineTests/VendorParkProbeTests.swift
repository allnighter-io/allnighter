import XCTest
@testable import AllnighterCore
@testable import AllnighterEngine

/// QABC-S01a: pure `LoopTurnClassifier.vendorPark` probe + `LoopState.capacityPark`
/// side-field decode. No dispatch behaviour here — that is QABC-S01b.
final class VendorParkProbeTests: XCTestCase {
    private func parkedRun(
        status: RunStatus = .queued,
        phase: RunPhase? = .waitingForVendor,
        blocker: RunBlocker? = RunBlocker(
            resource: .vendorBackoff,
            quotaScope: "claude_code",
            wakeAfter: Date(timeIntervalSince1970: 1_800_000_000)
        )
    ) -> TeamRun {
        TeamRun(
            id: "run-parked",
            prompt: "work",
            status: status,
            phase: phase,
            workers: [Agent(id: "worker-1", modelId: "model_opus", instanceIndex: 0)],
            createdAt: Date(timeIntervalSince1970: 1_700_000_000),
            mutating: true,
            executionSourceId: "claude_code",
            blocker: blocker
        )
    }

    func testVendorParkReturnsFactsWhenAllThreeConditionsHold() {
        let run = parkedRun()
        let park = LoopTurnClassifier.vendorPark(run)
        XCTAssertEqual(park?.runId, "run-parked")
        XCTAssertEqual(park?.wakeAfter, Date(timeIntervalSince1970: 1_800_000_000))
        XCTAssertEqual(park?.source, "claude_code")
    }

    func testVendorParkNilWhenStatusIsNotQueued() {
        let run = parkedRun(status: .running)
        XCTAssertNil(LoopTurnClassifier.vendorPark(run))
    }

    func testVendorParkNilWhenPhaseIsNotWaitingForVendor() {
        let run = parkedRun(phase: .waitingForWriteLock)
        XCTAssertNil(LoopTurnClassifier.vendorPark(run))
    }

    func testVendorParkNilWhenBlockerResourceIsNotVendorBackoff() {
        let run = parkedRun(blocker: RunBlocker(resource: .repoWriteLock))
        XCTAssertNil(LoopTurnClassifier.vendorPark(run))
    }

    func testVendorParkNilWhenNoBlockerAtAll() {
        let run = parkedRun(blocker: nil)
        XCTAssertNil(LoopTurnClassifier.vendorPark(run))
    }

    /// REGRESSION-IN-WAITING: the same parked run's worker answer genuinely carries a
    /// structured `capacityObservation`, so `LoopTurnClassifier.classify` confidently —
    /// and wrongly — reads it as `.infraBackoff`. This is exactly why `vendorPark` must
    /// run BEFORE `classify` in the dispatch loop (QABC-S01b), and this test should keep
    /// failing that way until S01b wires the ordering.
    func testClassifyMisreadsTheParkedRunsAnswerAsInfraBackoff() {
        let observation = CapacityObservation(
            kind: .accountRateLimit,
            source: "claude_code",
            sourceConfidence: .structured,
            rawSnippet: "limited",
            observedAt: Date(timeIntervalSince1970: 1_700_000_000)
        )
        let outcome = WorkerRunOutcome(status: .failed, capacityObservation: observation)
        XCTAssertEqual(LoopTurnClassifier.classify(.init(outcome: outcome)), .infraBackoff)
    }

    func testLoopStateWithoutCapacityParkStillDecodes() throws {
        let legacy = """
        {
            "id": "relay_legacy",
            "projectRoot": "/repo",
            "docPath": "docs/spec.md",
            "pmModelId": "model_pm",
            "devModelId": "model_dev",
            "status": "running",
            "createdAt": 731000000
        }
        """.data(using: .utf8)!
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        let state = try decoder.decode(LoopState.self, from: legacy)
        XCTAssertNil(state.capacityPark)
    }

    func testLoopStateWithCapacityParkRoundTrips() throws {
        let park = CapacityPark(
            runId: "run-parked",
            wakeAfter: Date(timeIntervalSince1970: 1_800_000_000),
            source: "claude_code",
            since: Date(timeIntervalSince1970: 1_700_000_000)
        )
        let state = LoopState(
            id: "relay_parked",
            projectRoot: "/repo",
            docPath: "docs/spec.md",
            pmModelId: "model_pm",
            devModelId: "model_dev",
            status: .running,
            createdAt: Date(timeIntervalSince1970: 1_700_000_000),
            capacityPark: park
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        let data = try encoder.encode(state)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        let decoded = try decoder.decode(LoopState.self, from: data)
        XCTAssertEqual(decoded.capacityPark, park)
    }
}
