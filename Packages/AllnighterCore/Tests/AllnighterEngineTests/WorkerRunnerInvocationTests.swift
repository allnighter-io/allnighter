import XCTest
import AllnighterCore
@testable import AllnighterEngine

/// Proves `health == runs`: WorkerRunner spawns through the SAME `ToolInvocation`
/// detection resolved, not the bare command on the ambient PATH
/// (docs/phases/setup/01 §4.3, §10). MockCommandRunner is keyed by the spawned
/// command, so the output reveals which command actually ran.
final class WorkerRunnerInvocationTests: XCTestCase {
    private let manifest = TestSupport.headlessManifest(id: "claude_code", command: "claude")
    private let model = Model(id: "model_opus", displayName: "Opus", modelLabel: "opus", driverId: "claude_code", role: .both)

    private func output(_ outcome: WorkerRunOutcome) -> String? {
        outcome.output?.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func testUsesCachedDirectPathNotBareCommand() async {
        let mock = MockCommandRunner(scripts: [
            "/abs/bin/claude": .init(stdout: "ABSOLUTE", exitCode: 0),
            "claude": .init(stdout: "BARE", exitCode: 0),
        ])
        let runner = WorkerRunner(commandRunner: mock, invocations: ["claude_code": .direct(path: "/abs/bin/claude")])
        let outcome = await runner.invoke(worker: model, manifest: manifest, prompt: "hi")
        XCTAssertEqual(outcome.status, .done)
        XCTAssertEqual(output(outcome), "ABSOLUTE")   // ran the cached resolved path, not bare `claude`
    }

    func testFallsBackToBareCommandWithoutCachedInvocation() async {
        let mock = MockCommandRunner(scripts: ["claude": .init(stdout: "BARE", exitCode: 0)])
        let runner = WorkerRunner(commandRunner: mock)   // no cached invocations
        let outcome = await runner.invoke(worker: model, manifest: manifest, prompt: "hi")
        XCTAssertEqual(output(outcome), "BARE")
    }

    func testLoginShellInvocationRunsViaShell() async {
        let mock = MockCommandRunner(scripts: ["/bin/zsh": .init(stdout: "VIA SHELL", exitCode: 0)])
        let runner = WorkerRunner(commandRunner: mock,
                                  invocations: ["claude_code": .loginShell(commandName: "claude")],
                                  shellPath: "/bin/zsh")
        let outcome = await runner.invoke(worker: model, manifest: manifest, prompt: "hi")
        XCTAssertEqual(output(outcome), "VIA SHELL")   // alias resolved via the login shell
    }

    func testSetupStorePersistsAssembledTeam() throws {
        let url = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("setup-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }
        let store = SetupStore(fileURL: url)
        let assembled = TeamAssembler.Assembled(
            benchModelIds: ["model_opus"], workerSpecs: [WorkerSpec(modelId: "model_opus")],
            planWriterModelId: "model_opus", assembledAt: Date(timeIntervalSince1970: 0))
        try store.save(.init(records: [], setupCompletedAt: nil, assembledTeam: assembled))
        XCTAssertEqual(store.load().assembledTeam, assembled)
    }
}
