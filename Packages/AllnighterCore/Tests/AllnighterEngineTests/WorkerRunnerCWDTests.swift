import XCTest
import AllnighterCore
@testable import AllnighterEngine

/// Regression: a worker run must NOT inherit the app's process CWD (in dev that
/// is the checkout under ~/Documents, which raised a TCC Documents prompt on the
/// first chat send — code red). With no explicit working dir, the child spawns in
/// an Allnighter-owned neutral scratch; an explicit dir is preserved.
///
/// F2_B.3c: the cwd rule moved out of the deleted `WorkerRunner` into the pure
/// `WorkerInvocationCWD.resolve` helper (unit-tested directly below) plus the
/// composed `WorkerInvokerFactory` stack (end-to-end tests below, replacing the
/// `WorkerRunner`-specific spawn recorder tests).
final class WorkerRunnerCWDTests: XCTestCase {

    private final class CWDRecorder: StreamingCommandRunner, @unchecked Sendable {
        private let lock = NSLock()
        private var workingDirs: [String?] = []
        private var argv: [[String]] = []
        func runStreaming(
            command: String, args: [String], stdin: String?, env: [String: String],
            workingDirectory: String?, timeout: Duration
        ) -> AsyncThrowingStream<CommandEvent, Error> {
            lock.lock()
            workingDirs.append(workingDirectory)
            argv.append(args)
            lock.unlock()
            return AsyncThrowingStream { continuation in
                continuation.yield(.started(startedAt: Date()))
                continuation.yield(.completed(CommandResult(stdout: "ok", exitCode: 0)))
                continuation.finish()
            }
        }
        func recorded() -> [String?] { lock.lock(); defer { lock.unlock() }; return workingDirs }
        func recordedArgs() -> [[String]] { lock.lock(); defer { lock.unlock() }; return argv }
    }

    // MARK: - Pure helper

    func testResolveUsesOverrideFirst() {
        let resolved = WorkerInvocationCWD.resolve(override: "/tmp/explicit", default: "/tmp/default")
        XCTAssertEqual(resolved, "/tmp/explicit")
    }

    func testResolveFallsBackToDefaultWorkingDirectory() {
        let resolved = WorkerInvocationCWD.resolve(override: nil, default: "/tmp/default")
        XCTAssertEqual(resolved, "/tmp/default")
    }

    func testResolveFallsBackToNeutralScratchWhenNothingExplicit() {
        let resolved = WorkerInvocationCWD.resolve(override: nil, default: nil)
        XCTAssertEqual(resolved, AllnighterPaths.probeScratch.path,
                       "no explicit dir anywhere must resolve to the owned scratch, never nil (inherited app CWD)")
    }

    // MARK: - End-to-end through the composed factory

    func testChatRunSpawnsInNeutralScratchNotInheritedCWD() async {
        let recorder = CWDRecorder()
        let runner = WorkerInvokerFactory.makeWorkerInvoker(
            commandRunner: recorder,
            invocations: ["claude_code": .direct(path: "/opt/test/claude")]
        )
        _ = await runner.collect(WorkerInvocation(
            model: TestSupport.worker("w", driverId: "claude_code"),
            manifest: TestSupport.headlessManifest(id: "claude_code", command: "claude"),
            prompt: "say hi"
        ))
        let dirs = recorder.recorded()
        XCTAssertEqual(dirs.first ?? nil, AllnighterPaths.probeScratch.path,
                       "a chat run with no explicit dir must spawn in the owned scratch, never inherit (nil) the app CWD")
    }

    func testWorkingDirTokenUsesScratchWhenNoExplicitRootExists() async {
        let recorder = CWDRecorder()
        let manifest = DriverManifest(
            id: "grok",
            displayName: "Grok",
            kind: .headlessCLI,
            invoke: .init(
                command: "grok",
                args: ["-p", "{{prompt}}", "--cwd", "{{workingDir}}"],
                timeoutSeconds: 5
            ),
            output: .init()
        )
        let runner = WorkerInvokerFactory.makeWorkerInvoker(commandRunner: recorder)

        _ = await runner.collect(WorkerInvocation(
            model: TestSupport.worker("w", driverId: "grok"),
            manifest: manifest,
            prompt: "say hi"
        ))

        let args = recorder.recordedArgs()
        let firstArgs = try! XCTUnwrap(args.first)
        let cwdIndex = try! XCTUnwrap(firstArgs.firstIndex(of: "--cwd"))
        XCTAssertEqual(firstArgs[cwdIndex + 1], AllnighterPaths.probeScratch.path)
        XCTAssertFalse(firstArgs[cwdIndex + 1].isEmpty, "`{{workingDir}}` must not resolve to an empty argv value")
    }

    func testExplicitWorkingDirIsPreserved() async {
        let recorder = CWDRecorder()
        let runner = WorkerInvokerFactory.makeWorkerInvoker(
            commandRunner: recorder,
            invocations: ["claude_code": .direct(path: "/opt/test/claude")]
        )
        _ = await runner.collect(WorkerInvocation(
            model: TestSupport.worker("w", driverId: "claude_code"),
            manifest: TestSupport.headlessManifest(id: "claude_code", command: "claude"),
            prompt: "fix the bug",
            workingDirectory: "/tmp/some-repo"
        ))
        let dirs = recorder.recorded()
        XCTAssertEqual(dirs.first ?? nil, "/tmp/some-repo", "explicit working dir must be preserved")
    }

    func testCatalogWorkerRunPassesRepoRoot() async {
        let recorder = CWDRecorder()
        var manifest = TestSupport.headlessManifest(id: "claude_code", command: "claude")
        manifest.streaming = nil
        let runner = WorkerInvokerFactory.makeWorkerInvoker(
            commandRunner: recorder,
            invocations: ["claude_code": .direct(path: "/opt/test/claude")]
        )
        _ = await runner.collect(WorkerInvocation(
            model: TestSupport.worker("w", driverId: "claude_code"),
            manifest: manifest,
            prompt: "trace the bug",
            workingDirectory: "/tmp/team-repo"
        ))
        let dirs = recorder.recorded()
        XCTAssertEqual(dirs.first ?? nil, "/tmp/team-repo", "team catalog run must spawn in repoRoot")
    }
}
