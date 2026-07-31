import XCTest
import AgentOSCLI
import AgentOSTeam
import AllnighterCore
import AllnighterEngine
@testable import AllnighterCLI

/// OUR-S02 — live pilot/relay status duration + tok/blame.
final class OURLiveStatusUsageTests: XCTestCase {
    private var tmp: URL!

    override func setUpWithError() throws {
        tmp = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("alln-our-s02-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tmp)
    }

    func testAliveElapsedAndTokWhenJournalHasUsage() throws {
        let runStore = RunStore(rootDirectory: tmp.appendingPathComponent("runs"))
        let relayStore = RelayStateStore(rootDirectory: tmp.appendingPathComponent("relays"))
        let devRunId = "run_our_tok"
        var round = RelayRound(roundNumber: 1, startedAt: Date().addingTimeInterval(-160))
        round.devRunId = devRunId
        let state = RelayState(
            id: "relay_our", projectRoot: "/repo", docPath: "d.md",
            pmModelId: RelayState.callerPMModelId, devModelId: "model_grok",
            status: .running, rounds: [round], createdAt: Date()
        )
        var run = TeamRun(id: devRunId, prompt: "p", status: .running, createdAt: Date())
        run.lastActivityAt = Date().addingTimeInterval(-12)
        run.answers = [
            TeamAnswer(
                memberId: "m#0", modelId: "model_opus", role: "answer",
                result: WorkerRunResult(
                    status: .running, output: "…",
                    reportedTokenUsage: ReportedTokenUsage(inputTokens: 80000, outputTokens: 9100))
            )
        ]
        try runStore.save(run, models: [])

        let status = PilotCLI.makeStatusJSON(
            state: state, recovery: .handoffAlive, stateStore: relayStore, runStore: runStore
        )
        XCTAssertEqual(status.ownerAlive, true)
        XCTAssertNotNil(status.elapsedSeconds)
        XCTAssertNotNil(status.silenceAgeSeconds)
        XCTAssertTrue(status.usagePresentation?.contains("tok") == true, status.usagePresentation ?? "")
        XCTAssertTrue(status.liveLine?.contains("alive") == true, status.liveLine ?? "")
        XCTAssertTrue(status.liveLine?.contains("tok") == true)
        XCTAssertEqual(status.observedUsage?.inputTokens, 80000)
    }

    func testRunningSilentSeatNotYetReported() throws {
        let runStore = RunStore(rootDirectory: tmp.appendingPathComponent("runs2"))
        let relayStore = RelayStateStore(rootDirectory: tmp.appendingPathComponent("relays2"))
        let devRunId = "run_silent"
        var round = RelayRound(roundNumber: 1, startedAt: Date().addingTimeInterval(-60))
        round.devRunId = devRunId
        let state = RelayState(
            id: "relay_silent", projectRoot: "/repo", docPath: "d.md",
            pmModelId: RelayState.callerPMModelId, devModelId: "model_grok",
            status: .running, rounds: [round], createdAt: Date()
        )
        var run = TeamRun(id: devRunId, prompt: "p", status: .running, createdAt: Date())
        run.lastActivityAt = Date().addingTimeInterval(-20)
        run.answers = [
            TeamAnswer(
                memberId: "g#0", modelId: "model_grok", role: "answer",
                result: WorkerRunResult(status: .running, output: nil)
            )
        ]
        try runStore.save(run, models: [])

        let status = PilotCLI.makeStatusJSON(
            state: state, recovery: .handoffAlive, stateStore: relayStore, runStore: runStore
        )
        XCTAssertTrue(
            status.usagePresentation?.contains("not yet reported") == true,
            status.usagePresentation ?? "nil"
        )
        XCTAssertFalse(status.usagePresentation?.contains("tokens not reported by") == true)
        XCTAssertNotNil(status.silenceAgeSeconds)
    }

    func testNoDevRunIdOmitsUsageSegment() throws {
        let relayStore = RelayStateStore(rootDirectory: tmp.appendingPathComponent("relays3"))
        let state = RelayState(
            id: "relay_nodev", projectRoot: "/repo", docPath: "d.md",
            pmModelId: RelayState.callerPMModelId, devModelId: "model_grok",
            status: .running,
            rounds: [RelayRound(roundNumber: 1, startedAt: Date())],
            createdAt: Date()
        )
        let status = PilotCLI.makeStatusJSON(
            state: state, recovery: .handoffAlive, stateStore: relayStore
        )
        XCTAssertNil(status.observedUsage)
        XCTAssertNil(status.usagePresentation)
        // Long-job may still show elapsed when handoffAlive without devRunId.
        XCTAssertEqual(status.ownerAlive, true)
    }

    func testDeadOwnerStillEmitsLongJobWithDevRunId() throws {
        let runStore = RunStore(rootDirectory: tmp.appendingPathComponent("runs4"))
        let relayStore = RelayStateStore(rootDirectory: tmp.appendingPathComponent("relays4"))
        let devRunId = "run_dead"
        var round = RelayRound(roundNumber: 1, startedAt: Date().addingTimeInterval(-250))
        round.devRunId = devRunId
        let state = RelayState(
            id: "relay_dead", projectRoot: "/repo", docPath: "d.md",
            pmModelId: RelayState.callerPMModelId, devModelId: "model_grok",
            status: .running, rounds: [round], createdAt: Date()
        )
        var run = TeamRun(id: devRunId, prompt: "p", status: .running, createdAt: Date())
        run.lastActivityAt = Date().addingTimeInterval(-240)
        try runStore.save(run, models: [])

        let status = PilotCLI.makeStatusJSON(
            state: state, recovery: .none, stateStore: relayStore, runStore: runStore
        )
        XCTAssertEqual(status.ownerAlive, false)
        XCTAssertNotNil(status.elapsedSeconds)
        XCTAssertNotNil(status.silenceAgeSeconds)
        XCTAssertTrue(status.liveLine?.contains("dead") == true, status.liveLine ?? "")
        XCTAssertTrue(
            status.usagePresentation?.contains("not yet reported") == true
                || status.usagePresentation != nil
        )
    }

    func testLiveHeroLineFormatting() {
        let line = ObservedUsagePresentation.liveHeroLine(
            ownerAlive: true,
            silenceAgeSeconds: 12,
            elapsedSeconds: 160,
            usagePresentation: "89.1k tok"
        )
        XCTAssertTrue(line.contains("alive"))
        XCTAssertTrue(line.contains("12s") || line.contains("stream"))
        XCTAssertTrue(line.contains("2m") || line.contains("160"))
        XCTAssertTrue(line.contains("89.1k tok"))
    }
}
