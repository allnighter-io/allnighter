import XCTest
import AllnighterCore
@testable import AllnighterEngine

/// Captures the last `(command, args)` a `StreamingCommandRunner` was asked to run,
/// then replies with a canned single-shot completion.
private final class SpawnSpy: StreamingCommandRunner, @unchecked Sendable {
    private let lock = NSLock()
    private(set) var command: String?
    private(set) var args: [String]?

    func runStreaming(
        command: String, args: [String], stdin: String?, env: [String: String],
        workingDirectory: String?, timeout: Duration
    ) -> AsyncThrowingStream<CommandEvent, Error> {
        lock.lock()
        self.command = command
        self.args = args
        lock.unlock()
        return AsyncThrowingStream { continuation in
            continuation.yield(.completed(CommandResult(stdout: "ok", exitCode: 0)))
            continuation.finish()
        }
    }
}

final class SpawnResolvingCommandRunnerTests: XCTestCase {
    func testDirectInvocationRewritesCommandToResolvedPath() async throws {
        let spy = SpawnSpy()
        let runner = SpawnResolvingCommandRunner(
            inner: spy, invocations: ["claude": .direct(path: "/opt/test/claude")])

        for try await _ in runner.runStreaming(
            command: "claude", args: ["-p", "hi"], stdin: nil, env: [:],
            workingDirectory: nil, timeout: .seconds(5)
        ) {}

        XCTAssertEqual(spy.command, "/opt/test/claude")
        XCTAssertEqual(spy.args, ["-p", "hi"])
    }

    func testShimInvocationRewritesCommandToResolvedPath() async throws {
        let spy = SpawnSpy()
        let runner = SpawnResolvingCommandRunner(
            inner: spy, invocations: ["codex": .shim(path: "/Users/x/.nvm/versions/node/v20/bin/codex")])

        for try await _ in runner.runStreaming(
            command: "codex", args: ["exec", "hi"], stdin: nil, env: [:],
            workingDirectory: nil, timeout: .seconds(5)
        ) {}

        XCTAssertEqual(spy.command, "/Users/x/.nvm/versions/node/v20/bin/codex")
        XCTAssertEqual(spy.args, ["exec", "hi"])
    }

    func testLoginShellInvocationWrapsThroughShellPreservingArgv() async throws {
        let spy = SpawnSpy()
        let runner = SpawnResolvingCommandRunner(
            inner: spy, invocations: ["claude": .loginShell(commandName: "claude")], shellPath: "/bin/zsh")

        for try await _ in runner.runStreaming(
            command: "claude", args: ["-p", "hi"], stdin: nil, env: [:],
            workingDirectory: nil, timeout: .seconds(5)
        ) {}

        XCTAssertEqual(spy.command, "/bin/zsh")
        XCTAssertEqual(spy.args, ["-lic", "claude \"$@\"", "claude", "-p", "hi"])
    }

    func testAmbientCommandPassesThroughUnchangedWhenUnmapped() async throws {
        let spy = SpawnSpy()
        let runner = SpawnResolvingCommandRunner(inner: spy, invocations: [:])

        for try await _ in runner.runStreaming(
            command: "grok", args: ["-p", "hi"], stdin: nil, env: [:],
            workingDirectory: nil, timeout: .seconds(5)
        ) {}

        XCTAssertEqual(spy.command, "grok")
        XCTAssertEqual(spy.args, ["-p", "hi"])
    }

    /// End-to-end proof of the intended composition:
    /// `DefaultWorkerRunner(streamingRunner: SpawnResolvingCommandRunner(...))`
    /// reproduces `WorkerRunner.resolveSpawn`'s health==runs behavior — the manifest's
    /// literal command resolves to the SAME path Setup detected before the CLI spawns.
    func testComposesWithDefaultWorkerRunnerToResolveDirectPath() async {
        let manifest = TestSupport.headlessManifest(id: "claude_code", command: "claude")
        let worker = TestSupport.worker("w", driverId: "claude_code")
        let streaming = AgentOSCLI.MockStreamingCommandRunner(scripts: [
            "/opt/test/claude": .init(events: [
                .completed(CommandResult(stdout: "hello from resolved path", exitCode: 0))
            ])
        ])
        let spawnResolving = SpawnResolvingCommandRunner(
            inner: streaming, invocations: ["claude": .direct(path: "/opt/test/claude")])
        let runner = DefaultWorkerRunner(streamingRunner: spawnResolving)

        let result = await runner.collect(WorkerInvocation(model: worker, manifest: manifest, prompt: "hi"))

        XCTAssertEqual(result.status, .done)
        XCTAssertEqual(result.output, "hello from resolved path")
    }
}
