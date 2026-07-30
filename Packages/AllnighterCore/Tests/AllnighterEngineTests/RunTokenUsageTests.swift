import XCTest
import AgentOSCLI
import AgentOSTeam
import AllnighterCore
@testable import AllnighterEngine

/// FR14 — surface driver-reported token usage on `outcome` + headline (Field_Reports_4.md).
final class RunTokenUsageTests: XCTestCase {

    private func claudeManifest() -> DriverManifest {
        try! XCTUnwrap(DefaultConfig.manifests.first { $0.id == "claude_code" })
    }

    private func grokManifest() -> DriverManifest {
        try! XCTUnwrap(DefaultConfig.manifests.first { $0.id == "grok" })
    }

    private func collectTerminal(
        runner: DefaultWorkerRunner, manifest: DriverManifest, modelId: String
    ) async throws -> WorkerRunResult {
        let model = Model(id: modelId, displayName: modelId, modelLabel: "m", driverId: manifest.id, role: .both)
        var terminal: WorkerRunResult?
        for try await event in runner.invoke(WorkerInvocation(
            model: model, manifest: manifest, prompt: "hi", effort: .med,
            workingDirectory: FileManager.default.currentDirectoryPath
        )) {
            if case .completed(let o) = event { terminal = o }
            if case .failed(let o) = event { terminal = o }
        }
        return try XCTUnwrap(terminal)
    }

    func testClaudeColdStreamReportsUsage() async throws {
        let stdout = [
            #"{"type":"stream_event","event":{"type":"content_block_delta","delta":{"type":"text_delta","text":"OK"}}}"#,
            #"{"type":"result","subtype":"success","is_error":false,"usage":{"input_tokens":2655,"output_tokens":18}}"#,
        ].joined(separator: "\n") + "\n"
        let runner = DefaultWorkerRunner(streamingRunner: CommandRunnerAsStreaming(
            MockCommandRunner(scripts: ["claude": .init(stdout: stdout, exitCode: 0)])))
        let result = try await collectTerminal(
            runner: runner, manifest: claudeManifest(), modelId: "model_opus")
        XCTAssertEqual(result.reportedTokenUsage?.inputTokens, 2655)
        XCTAssertEqual(result.reportedTokenUsage?.outputTokens, 18)
    }

    func testGrokColdStreamHasNoUsage() async throws {
        let stdout = [
            #"{"type":"text","data":"PONG"}"#,
            #"{"type":"end","stopReason":"EndTurn","sessionId":"gs-1"}"#,
        ].joined(separator: "\n") + "\n"
        let runner = DefaultWorkerRunner(streamingRunner: CommandRunnerAsStreaming(
            MockCommandRunner(scripts: ["grok": .init(stdout: stdout, exitCode: 0)])))
        let result = try await collectTerminal(
            runner: runner, manifest: grokManifest(), modelId: "model_grok")
        XCTAssertNil(result.reportedTokenUsage)
    }

    func testOutcomeMapsUsageAndHeadlineSuffix() {
        var run = TeamRun(
            id: "u1", prompt: "p", status: .complete, workers: [],
            answers: [
                TeamAnswer(
                    memberId: "model_opus#0", modelId: "model_opus", role: "answer",
                    result: WorkerRunResult(
                        status: .done, output: "done",
                        reportedTokenUsage: ReportedTokenUsage(inputTokens: 12000, outputTokens: 400)))
            ],
            stages: [], createdAt: Date(), mutating: true, repoDelta: RepoDelta(
                changed: true, baseline: "a", head: "b", commits: [], filesChanged: 1, files: ["x"], truncated: false))
        let trj = TeamRunJSONMapper.map(run, models: [], manifests: [], context: .init(runJournalPath: "/tmp/r.json"))
        let outcome = try! XCTUnwrap(trj.outcome)
        XCTAssertEqual(outcome.usage?.inputTokens, 12000)
        XCTAssertEqual(outcome.usage?.outputTokens, 400)
        XCTAssertTrue(outcome.headline.contains("12.4k tok"))
    }

    func testOutcomeOmitsUsageWhenDriverReportsNothing() {
        var run = TeamRun(
            id: "u2", prompt: "p", status: .complete, workers: [],
            answers: [
                TeamAnswer(
                    memberId: "model_grok#0", modelId: "model_grok", role: "answer",
                    result: WorkerRunResult(status: .done, output: "done"))
            ],
            stages: [], createdAt: Date(), mutating: false)
        let trj = TeamRunJSONMapper.map(run, models: [], manifests: [], context: .init(runJournalPath: "/tmp/r.json"))
        XCTAssertNil(trj.outcome?.usage)
        XCTAssertFalse(trj.outcome?.headline.contains("tok") ?? true)
    }

    func testHeadlineFormatCompact() {
        XCTAssertEqual(ReportedTokenUsage(inputTokens: 12400, outputTokens: 0).headlineSuffix, "12.4k tok")
        // OUR-S01: partial side — do not assume the missing side is zero.
        XCTAssertEqual(ReportedTokenUsage(outputTokens: 500).headlineSuffix, "output 500 tok")
        XCTAssertNil(ReportedTokenUsage().headlineSuffix)
    }
}
