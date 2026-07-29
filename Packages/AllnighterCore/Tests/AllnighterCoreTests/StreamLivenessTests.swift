import XCTest
import AllnighterCore

final class StreamLivenessTests: XCTestCase {
    func testStreamSilenceWarningThreshold() {
        let now = Date()
        let fresh = now.addingTimeInterval(-100)
        XCTAssertFalse(StreamLiveness.streamSilenceWarning(lastActivityAt: fresh, now: now))

        let stale = now.addingTimeInterval(-(StreamLiveness.waitHintSeconds * StreamLiveness.warningMultiplier + 1))
        XCTAssertTrue(StreamLiveness.streamSilenceWarning(lastActivityAt: stale, now: now))
    }

    func testRelayStreamLastActivityAtUsesDevJournalOnly() {
        let frozen = Date().addingTimeInterval(-400)
        var relay = RelayState(
            id: "r1", projectRoot: "/tmp", docPath: "d.md",
            pmWorkerId: "pm", devWorkerId: "dev", status: .running, createdAt: Date()
        )
        var round = RelayRound(roundNumber: 1, startedAt: Date())
        round.devRunId = "run1"
        relay.rounds = [round]
        let store = FakeRunStore(runs: [
            "run1": TeamRun(
                id: "run1", prompt: "p", status: .running,
                createdAt: Date(), repoRoot: "/tmp", lastActivityAt: frozen
            ),
        ])
        XCTAssertEqual(StreamLiveness.relayStreamLastActivityAt(state: relay, runStore: store), frozen)
    }
}

private struct FakeRunStore: RunStoreReading {
    var runs: [String: TeamRun]
    func load(runId: String) -> TeamRun? { runs[runId] }
}
