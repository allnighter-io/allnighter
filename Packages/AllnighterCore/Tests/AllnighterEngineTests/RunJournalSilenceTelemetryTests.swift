import XCTest
import AgentOSTeam
import AllnighterCore
@testable import AllnighterEngine

/// IDLE-HF-S04 — journal mining for idle-timeout histograms.
final class RunJournalSilenceTelemetryTests: XCTestCase {

    func testClassifyIdleTimeoutFromSpawnDiagnosticsFixture() throws {
        let created = Date(timeIntervalSince1970: 1_700_000_000)
        let lastActivity = Date(timeIntervalSince1970: 1_700_000_100)
        let terminal = Date(timeIntervalSince1970: 1_700_000_800)
        let diagnostics = WorkerSpawnDiagnostics(
            command: "claude",
            argCount: 2,
            workingDirectory: "/tmp/repo",
            timeoutSeconds: 600,
            timeoutKind: .idle,
            stdoutBytes: 0,
            stderrBytes: 0,
            stderrTail: nil,
            invocationKind: "direct"
        )
        var timing = RunTimingReport()
        timing.stamp(RunTimingKey.runOutcomePersisted, at: terminal)
        let run = TeamRun(
            id: "idle-fixture",
            prompt: "p",
            status: .timedOut,
            workers: [Worker(id: "model_opus#0", modelId: "model_opus", instanceIndex: 0)],
            workerAnswers: [
                TeamAnswer(
                    memberId: "model_opus#0",
                    modelId: "model_opus",
                    role: "answer",
                    result: WorkerRunResult(
                        status: .timedOut,
                        errorKind: .timedOut,
                        errorReason: "progress stalled",
                        spawnDiagnostics: diagnostics
                    )
                ),
            ],
            createdAt: created,
            executionSourceId: "claude_code",
            timing: timing,
            endReason: .timedOut,
            lastActivityAt: lastActivity,
            clockBudgets: RunClockBudgets(idleTimeoutSeconds: 600)
        )

        let sample = try XCTUnwrap(RunJournalSilenceTelemetry.classifyIdleTimeout(run: run))
        XCTAssertEqual(sample.driverId, "claude_code")
        XCTAssertEqual(sample.silenceSeconds, 700)
        XCTAssertEqual(RunJournalSilenceTelemetry.bucketLabel(for: sample.silenceSeconds), "0-1800")
    }

    func testMineFixtureJournalIntoHistogram() throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("idle-telemetry-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let store = RunStore(rootDirectory: root)
        let runDir = try store.runDirectory(forRunId: "idle-hist-1")
        let created = Date(timeIntervalSince1970: 1_700_000_000)
        let lastActivity = Date(timeIntervalSince1970: 1_700_000_050)
        let terminal = Date(timeIntervalSince1970: 1_700_000_120)
        let diagnostics = WorkerSpawnDiagnostics(
            command: "grok",
            argCount: 1,
            workingDirectory: nil,
            timeoutSeconds: 60,
            timeoutKind: .idle,
            stdoutBytes: 0,
            stderrBytes: 0,
            stderrTail: nil,
            invocationKind: nil
        )
        var timing = RunTimingReport()
        timing.stamp(RunTimingKey.processExit, at: terminal)
        let run = TeamRun(
            id: "idle-hist-1",
            prompt: "quiet",
            status: .timedOut,
            workers: [Worker(id: "model_grok#0", modelId: "model_grok", instanceIndex: 0)],
            workerAnswers: [
                TeamAnswer(
                    memberId: "model_grok#0",
                    modelId: "model_grok",
                    role: "answer",
                    result: WorkerRunResult(
                        status: .timedOut,
                        spawnDiagnostics: diagnostics
                    )
                ),
            ],
            createdAt: created,
            executionSourceId: "grok",
            timing: timing,
            endReason: .timedOut,
            lastActivityAt: lastActivity,
            clockBudgets: RunClockBudgets(idleTimeoutSeconds: 60)
        )
        try CoreJSON.encode(run).write(to: runDir.appendingPathComponent("run.json"), options: .atomic)

        let report = RunJournalSilenceTelemetry.mine(runStore: store)
        XCTAssertEqual(report.scannedRuns, 1)
        XCTAssertEqual(report.idleTimeoutCount, 1)
        XCTAssertEqual(report.byDriver.count, 1)
        XCTAssertEqual(report.byDriver[0].driverId, "grok")
        XCTAssertEqual(report.byDriver[0].idleTimeoutCount, 1)
        XCTAssertEqual(report.byDriver[0].buckets.first?.label, "0-300")
    }
}
