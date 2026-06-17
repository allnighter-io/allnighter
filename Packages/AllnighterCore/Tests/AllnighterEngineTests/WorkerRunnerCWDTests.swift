import XCTest
import AllnighterCore
@testable import AllnighterEngine

/// Regression: a worker run must NOT inherit the app's process CWD (in dev that
/// is the checkout under ~/Documents, which raised a TCC Documents prompt on the
/// first chat send — code red). With no explicit working dir, the child spawns in
/// an Allnighter-owned neutral scratch; an explicit dir (dispatch) is preserved.
final class WorkerRunnerCWDTests: XCTestCase {

    private actor CWDRecorder: CommandRunner {
        private(set) var workingDirs: [String?] = []
        func run(command: String, args: [String], stdin: String?, env: [String: String],
                 workingDirectory: String?, timeout: Duration) async -> CommandResult {
            workingDirs.append(workingDirectory)
            return CommandResult(stdout: "ok", exitCode: 0)
        }
        func recorded() -> [String?] { workingDirs }
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
        XCTAssertEqual(dirs.first ?? nil, "/tmp/some-repo", "dispatch/explicit working dir must be preserved")
    }
}
