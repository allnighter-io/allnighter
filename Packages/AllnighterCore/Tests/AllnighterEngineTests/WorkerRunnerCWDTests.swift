import XCTest
import AllnighterCore
@testable import AllnighterEngine

/// Regression: a worker run must NOT inherit the app's process CWD (in dev that
/// is the checkout under ~/Documents, which raised a TCC Documents prompt on the
/// first chat send — code red). With no explicit working dir, the child spawns in
/// an Allnighter-owned neutral scratch; an explicit dir is preserved.
final class WorkerRunnerCWDTests: XCTestCase {

    private actor CWDRecorder: CommandRunner {
        private(set) var workingDirs: [String?] = []
        private(set) var argv: [[String]] = []
        func run(command: String, args: [String], stdin: String?, env: [String: String],
                 workingDirectory: String?, timeout: Duration) async -> CommandResult {
            workingDirs.append(workingDirectory)
            argv.append(args)
            return CommandResult(stdout: "ok", exitCode: 0)
        }
        func recorded() -> [String?] { workingDirs }
        func recordedArgs() -> [[String]] { argv }
    }

    func testChatRunSpawnsInNeutralScratchNotInheritedCWD() async {
        let recorder = CWDRecorder()
        let runner = WorkerRunner(
            commandRunner: recorder,
            invocations: ["claude_code": .direct(path: "/opt/test/claude")]
        )
        _ = await runner.invoke(
            worker: TestSupport.worker("w", driverId: "claude_code"),
            manifest: TestSupport.headlessManifest(id: "claude_code", command: "claude"),
            prompt: "say hi"
        )
        let dirs = await recorder.recorded()
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
        let runner = WorkerRunner(commandRunner: recorder)

        _ = await runner.invoke(
            worker: TestSupport.worker("w", driverId: "grok"),
            manifest: manifest,
            prompt: "say hi"
        )

        let args = await recorder.recordedArgs()
        let firstArgs = try! XCTUnwrap(args.first)
        let cwdIndex = try! XCTUnwrap(firstArgs.firstIndex(of: "--cwd"))
        XCTAssertEqual(firstArgs[cwdIndex + 1], AllnighterPaths.probeScratch.path)
        XCTAssertFalse(firstArgs[cwdIndex + 1].isEmpty, "`{{workingDir}}` must not resolve to an empty argv value")
    }

    func testExplicitWorkingDirIsPreserved() async {
        let recorder = CWDRecorder()
        let runner = WorkerRunner(
            commandRunner: recorder,
            invocations: ["claude_code": .direct(path: "/opt/test/claude")]
        )
        _ = await runner.invoke(
            worker: TestSupport.worker("w", driverId: "claude_code"),
            manifest: TestSupport.headlessManifest(id: "claude_code", command: "claude"),
            prompt: "fix the bug",
            workingDirectoryOverride: "/tmp/some-repo"
        )
        let dirs = await recorder.recorded()
        XCTAssertEqual(dirs.first ?? nil, "/tmp/some-repo", "explicit working dir must be preserved")
    }

    func testCatalogWorkerRunPassesRepoRoot() async {
        let recorder = CWDRecorder()
        var manifest = TestSupport.headlessManifest(id: "claude_code", command: "claude")
        manifest.streaming = nil
        let runner = WorkerRunner(
            commandRunner: recorder,
            invocations: ["claude_code": .direct(path: "/opt/test/claude")]
        )
        _ = await runner.run(
            assignment: Worker(id: "w#0", modelId: "w", instanceIndex: 0, purpose: .answer),
            model: TestSupport.worker("w", driverId: "claude_code"),
            manifest: manifest,
            prompt: "trace the bug",
            workingDirectoryOverride: "/tmp/team-repo"
        )
        let dirs = await recorder.recorded()
        XCTAssertEqual(dirs.first ?? nil, "/tmp/team-repo", "team catalog run must spawn in repoRoot")
    }
}
