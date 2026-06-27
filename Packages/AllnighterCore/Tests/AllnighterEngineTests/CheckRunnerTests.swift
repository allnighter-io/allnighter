import XCTest
@testable import AllnighterEngine

final class CheckRunnerTests: XCTestCase {
    func testRunsRepoCheckCommand() async {
        let runner = CheckRunner(commandRunner: MockCommandRunner(scripts: [
            "/bin/sh": .init(stdout: "ok\n", exitCode: 0),
        ]))
        let result = await runner.run(
            check: .init(method: .command, command: "echo ok"),
            repoRoot: "/tmp"
        )
        XCTAssertEqual(result.exitCode, 0)
        XCTAssertTrue(result.passed)
        XCTAssertFalse(result.skipped)
    }

    func testNonZeroCheckFails() async {
        let runner = CheckRunner(commandRunner: MockCommandRunner(scripts: [
            "/bin/sh": .init(stdout: "fail", exitCode: 1),
        ]))
        let result = await runner.run(
            check: .init(method: .command, command: "false"),
            repoRoot: "/tmp"
        )
        XCTAssertEqual(result.exitCode, 1)
        XCTAssertFalse(result.passed)
    }
}
