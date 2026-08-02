import XCTest
import AgentOSCLI
import AgentOSTeam
@testable import AllnighterCore

/// OUR-S01 — per-answer usage, outcome honesty, presentation helper.
final class ObservedUsagePresentationTests: XCTestCase {

    private func answer(
        id: String,
        modelId: String,
        usage: ReportedTokenUsage? = nil,
        status: WorkerAnswerStatus = .done
    ) -> TeamAnswer {
        TeamAnswer(
            memberId: id, modelId: modelId, role: "answer",
            result: WorkerRunResult(
                status: status, output: "ok",
                reportedTokenUsage: usage)
        )
    }

    func testTwoSeatMapsPerAnswerOmitsOutcomeUsage() {
        let run = TeamRun(
            id: "multi", prompt: "p", status: .complete,
            answers: [
                answer(id: "a#0", modelId: "model_opus",
                       usage: ReportedTokenUsage(inputTokens: 1000, outputTokens: 50)),
                answer(id: "b#0", modelId: "model_grok", usage: nil as ReportedTokenUsage?),
            ],
            stages: [], createdAt: Date()
        )
        let trj = TeamRunJSONMapper.map(
            run, models: [], manifests: [],
            context: .init()
        )
        XCTAssertEqual(trj.answers.count, 2)
        XCTAssertEqual(trj.answers[0].usage?.inputTokens, 1000)
        XCTAssertEqual(trj.answers[0].usage?.outputTokens, 50)
        XCTAssertNil(trj.answers[1].usage, "silent seat must omit usage key")
        XCTAssertNil(trj.outcome?.usage, "multi-seat must not copy first-answer usage")
        XCTAssertFalse(trj.outcome?.headline.contains("tok") ?? true)
    }

    func testSingleSeatPreservesOutcomeUsageAndHeadline() {
        let run = TeamRun(
            id: "single", prompt: "p", status: .complete,
            answers: [
                answer(id: "a#0", modelId: "model_opus",
                       usage: ReportedTokenUsage(inputTokens: 12000, outputTokens: 400)),
            ],
            stages: [], createdAt: Date(), mutating: true,
            repoDelta: RepoDelta(
                changed: true, baseline: "a", head: "b", commits: [],
                filesChanged: 1, files: ["x"], truncated: false)
        )
        let trj = TeamRunJSONMapper.map(
            run, models: [], manifests: [],
            context: .init()
        )
        XCTAssertEqual(trj.answers[0].usage?.inputTokens, 12000)
        XCTAssertEqual(trj.outcome?.usage?.inputTokens, 12000)
        XCTAssertEqual(trj.outcome?.usage?.outputTokens, 400)
        XCTAssertTrue(trj.outcome?.headline.contains("12.4k tok") == true)
    }

    func testEmptyUsageAbsentOnAnswerAndOutcome() {
        let run = TeamRun(
            id: "empty", prompt: "p", status: .complete,
            answers: [answer(id: "a#0", modelId: "model_grok", usage: ReportedTokenUsage())],
            stages: [], createdAt: Date()
        )
        let trj = TeamRunJSONMapper.map(
            run, models: [], manifests: [],
            context: .init()
        )
        XCTAssertNil(trj.answers[0].usage)
        XCTAssertNil(trj.outcome?.usage)
    }

    func testBackwardDecodeAnswerWithoutUsage() throws {
        let json = """
        {"agentId":"a","status":"done","durationMs":100}
        """
        let info = try JSONDecoder().decode(TeamRunJSON.AnswerInfo.self, from: Data(json.utf8))
        XCTAssertEqual(info.agentId, "a")
        XCTAssertNil(info.usage)
    }

    func testInputOnlyAndOutputOnlyFormatting() {
        XCTAssertEqual(
            ObservedUsagePresentation.compactTok(ReportedTokenUsage(inputTokens: 12400)),
            "input 12.4k tok"
        )
        XCTAssertEqual(
            ObservedUsagePresentation.compactTok(ReportedTokenUsage(outputTokens: 400)),
            "output 400 tok"
        )
        XCTAssertEqual(
            ObservedUsagePresentation.compactTok(
                ReportedTokenUsage(inputTokens: 1000, outputTokens: 200)),
            "1.2k tok"
        )
        XCTAssertNil(ObservedUsagePresentation.compactTok(nil as ReportedTokenUsage?))
        XCTAssertNil(ObservedUsagePresentation.compactTok(ReportedTokenUsage()))
    }

    func testRunningVsTerminalBlame() {
        XCTAssertEqual(
            ObservedUsagePresentation.runningBlame(sourceId: "grok"),
            "tokens not yet reported by grok"
        )
        XCTAssertEqual(
            ObservedUsagePresentation.terminalBlame(sourceId: "grok"),
            "tokens not reported by grok"
        )
        XCTAssertTrue(
            ObservedUsagePresentation.terminalBlame(sourceId: nil).contains("CLI")
        )
    }

    func testEncodeOmitsEmptyUsageKey() throws {
        let info = TeamRunJSON.AnswerInfo(
            agentId: "a", status: .done, durationMs: 10, usage: nil
        )
        let data = try JSONEncoder().encode(info)
        let obj = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertNil(obj["usage"])
    }
}
