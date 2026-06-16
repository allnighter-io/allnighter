import XCTest
import AllnighterCore
@testable import AllnighterEngine

/// C5: bare-path aliases resolve to a direct `.shim` (quiet runs, no per-run
/// login shell), while aliases that add flags / functions stay ambiguous so we
/// never silently drop the user's arguments.
final class AliasResolutionTests: XCTestCase {

    private func makeExecutable() throws -> String {
        let dir = NSTemporaryDirectory() + "alias-\(UUID().uuidString)"
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        let path = dir + "/claude"
        FileManager.default.createFile(atPath: path, contents: Data("#!/bin/sh\n".utf8),
                                       attributes: [.posixPermissions: 0o755])
        return path
    }

    func testBarePathZshAliasResolvesToTarget() throws {
        let path = try makeExecutable()
        let resolved = CLIDetector.barePathAliasTarget(fromCommandV: "claude: aliased to \(path)")
        XCTAssertEqual(resolved, path)
    }

    func testBarePathBashAliasResolvesToTarget() throws {
        let path = try makeExecutable()
        let resolved = CLIDetector.barePathAliasTarget(fromCommandV: "claude is aliased to `\(path)'")
        XCTAssertEqual(resolved, path)
    }

    func testAliasWithFlagsIsNotAutoResolved() throws {
        let path = try makeExecutable()
        // Dropping "--model opus" would change behavior → must stay ambiguous.
        XCTAssertNil(CLIDetector.barePathAliasTarget(fromCommandV: "claude: aliased to \(path) --model opus"))
    }

    func testSameNameWrapperAliasIsNotResolved() {
        XCTAssertNil(CLIDetector.barePathAliasTarget(fromCommandV: "claude: aliased to claude --dangerously-skip"))
    }

    func testNonExecutableTargetIsNotResolved() {
        XCTAssertNil(CLIDetector.barePathAliasTarget(fromCommandV: "claude: aliased to /no/such/binary/claude"))
    }

    func testFunctionAndPlainOutputAreNotResolved() {
        XCTAssertNil(CLIDetector.barePathAliasTarget(fromCommandV: "claude () { ... }"))
        XCTAssertNil(CLIDetector.barePathAliasTarget(fromCommandV: "claude: shell function"))
    }

    /// End-to-end: a bare-path alias makes the probe resolve to a runnable .shim,
    /// not a confirm-required shim — so the tool runs without the login shell.
    func testProbeResolvesBarePathAliasToShim() async throws {
        let path = try makeExecutable()
        let manifest = DriverManifest(
            id: "claude_code", displayName: "Claude Code", kind: .headlessCLI,
            detectCommand: "claude --version",
            invoke: .init(command: "claude", args: ["-p", "{{prompt}}"]),
            setup: SetupBlock(bins: ["claude"])
        )
        let runner = ClosureRunner { command, args in
            if args.first == "-lc" { return CommandResult(stdout: "<<<ALR:claude|claude: aliased to \(path)>>>\n", exitCode: 0) }
            if command == path, args.contains("--version") { return CommandResult(stdout: "claude 1.0", exitCode: 0) }
            return CommandResult(launchError: "unexpected \(command)")
        }
        let det = CLIDetector(commandRunner: runner, shellPath: "/bin/zsh", home: "/tmp/home")
        let rec = await det.probe(manifest, model: "opus", now: .init(timeIntervalSince1970: 0), smoke: false)

        XCTAssertEqual(rec.invocation, .shim(path: path))
        XCTAssertEqual(rec.status.kind, .installedNotProbed)
    }

    private struct ClosureRunner: CommandRunner {
        let handler: @Sendable (String, [String]) -> CommandResult
        func run(command: String, args: [String], stdin: String?, env: [String: String],
                 workingDirectory: String?, timeout: Duration) async -> CommandResult {
            handler(command, args)
        }
    }
}
