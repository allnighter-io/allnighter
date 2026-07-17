import XCTest
import AgentOSTeam
import AllnighterCore
@testable import AllnighterEngine

/// PERF-S05: a running team's progress save writes only the truth (run.json + liveness),
/// not every derived artifact. The full inspectable artifact set is built on the terminal
/// save (or when explicitly forced at a stage boundary).
final class RunStoreProgressFastPathTests: XCTestCase {

    private func tempStore() -> (RunStore, URL) {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("alln-runstore-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return (RunStore(rootDirectory: root), root)
    }

    private func run(status: RunStatus) -> TeamRun {
        TeamRun(
            id: "r1", prompt: "p", status: status, origin: .cli,
            workers: [Worker(id: "model_a#0", modelId: "model_a", instanceIndex: 0)],
            workerAnswers: [TeamAnswer(memberId: "model_a#0", modelId: "model_a", role: "answer",
                                       result: WorkerRunResult(status: .done, output: "answer A"))],
            createdAt: Date())
    }

    private func exists(_ dir: URL, _ rel: String) -> Bool {
        FileManager.default.fileExists(atPath: dir.appendingPathComponent("run_r1/\(rel)").path)
    }

    func testProgressSaveWritesRunJSONButNotArtifacts() throws {
        let (store, root) = tempStore()
        _ = try store.save(run(status: .fanningOut), models: [])
        XCTAssertTrue(exists(root, "run.json"), "the truth is always written")
        XCTAssertTrue(exists(root, "owner.json"), "a running run keeps its owner identity")
        XCTAssertFalse(exists(root, "bundle.md"), "no derived artifact regen on a progress save")
        XCTAssertFalse(exists(root, "workers/model_a_0.answer.md"))
    }

    func testTerminalSaveWritesArtifacts() throws {
        let (store, root) = tempStore()
        _ = try store.save(run(status: .complete), models: [])
        XCTAssertTrue(exists(root, "run.json"))
        XCTAssertTrue(exists(root, "bundle.md"), "the terminal save builds the inspectable receipt")
        XCTAssertTrue(exists(root, "workers/model_a_0.answer.md"))
    }

    func testForceArtifactsOnNonTerminalRun() throws {
        let (store, root) = tempStore()
        _ = try store.save(run(status: .fanningOut), models: [], forceArtifacts: true)
        XCTAssertTrue(exists(root, "bundle.md"), "an explicit stage-boundary save can force artifacts")
    }
}
