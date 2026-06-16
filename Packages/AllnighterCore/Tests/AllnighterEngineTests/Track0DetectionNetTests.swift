import XCTest
import AllnighterCore
@testable import AllnighterEngine

/// `command -v grok` → not found (empty sentinel value), forcing the fallbacks.
private let kResolveEmptyGrok = CommandResult(stdout: "<<<ALR:grok|>>>\n", exitCode: 0)

/// Track 0.2: the free detection net resolves tools the shell can't — via shared
/// common install dirs and a Spotlight (`mdfind`) fallback — so an agent census
/// is rarely needed.
final class Track0DetectionNetTests: XCTestCase {

    private struct ClosureRunner: CommandRunner {
        let handler: @Sendable (String, [String]) -> CommandResult
        func run(command: String, args: [String], stdin: String?, env: [String: String],
                 workingDirectory: String?, timeout: Duration) async -> CommandResult {
            handler(command, args)
        }
    }

    private func makeExecutable(_ path: String) throws {
        let dir = (path as NSString).deletingLastPathComponent
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: path, contents: Data("#!/bin/sh\n".utf8),
                                       attributes: [.posixPermissions: 0o755])
    }

    private func tmp() throws -> String {
        let root = NSTemporaryDirectory() + "net-\(UUID().uuidString)"
        try FileManager.default.createDirectory(atPath: root, withIntermediateDirectories: true)
        return root
    }

    private func grok(knownPaths: [String] = []) -> DriverManifest {
        DriverManifest(id: "grok", displayName: "Grok", kind: .headlessCLI,
                       detectCommand: "grok --version",
                       invoke: .init(command: "grok", args: []),
                       setup: SetupBlock(bins: ["grok"], knownPaths: knownPaths))
    }

    func testCommonBinDirResolvesWhenShellAndManifestMiss() async throws {
        let root = try tmp()
        let path = "\(root)/commonbin/grok"
        try makeExecutable(path)
        let runner = ClosureRunner { command, args in
            if args.first == "-lc" || args.first == "-lic" { return kResolveEmptyGrok }
            if command == path, args.contains("--version") { return CommandResult(stdout: "grok 1.0", exitCode: 0) }
            return CommandResult(launchError: "unexpected \(command)")
        }
        let det = CLIDetector(commandRunner: runner, shellPath: "/bin/zsh", home: root,
                              commonBinDirs: ["\(root)/commonbin"])
        let rec = await det.probe(grok(knownPaths: []), model: "x", now: .init(timeIntervalSince1970: 0), smoke: false)

        XCTAssertEqual(rec.invocation, .direct(path: path))
        XCTAssertEqual(rec.status.kind, .installedNotProbed)
    }

    func testSpotlightResolvesNonStandardInstall() async throws {
        let root = try tmp()
        let weird = "\(root)/Apps/grok-cli/grok"
        try makeExecutable(weird)
        let runner = ClosureRunner { command, args in
            if args.first == "-lc" || args.first == "-lic" { return kResolveEmptyGrok }
            if command == "/usr/bin/mdfind", args == ["-name", "grok"] {
                return CommandResult(stdout: "\(root)/Apps/grok-cli/grok\n\(root)/notes/grok.md\n", exitCode: 0)
            }
            if command == weird, args.contains("--version") { return CommandResult(stdout: "grok 1.0", exitCode: 0) }
            return CommandResult(launchError: "unexpected \(command)")
        }
        // No common dirs → forces the Spotlight rung.
        let det = CLIDetector(commandRunner: runner, shellPath: "/bin/zsh", home: root, commonBinDirs: [])
        let rec = await det.probe(grok(), model: "x", now: .init(timeIntervalSince1970: 0), smoke: false)

        XCTAssertEqual(rec.invocation, .direct(path: weird),
                       "mdfind result (exact-name executable) resolves; the .md is ignored")
    }

    func testSpotlightPrefersStableOverEphemeral() async throws {
        let root = try tmp()
        let stable = "\(root)/.local/bin/grok"
        let ephemeral = "\(root)/.grok/downloads/grok-0.2.54/grok"
        try makeExecutable(stable)
        try makeExecutable(ephemeral)
        let runner = ClosureRunner { command, args in
            if args.first == "-lc" || args.first == "-lic" { return kResolveEmptyGrok }
            if command == "/usr/bin/mdfind" {
                return CommandResult(stdout: "\(ephemeral)\n\(stable)\n", exitCode: 0)
            }
            if args.contains("--version") { return CommandResult(stdout: "grok 1.0", exitCode: 0) }
            return CommandResult(launchError: "unexpected \(command)")
        }
        let det = CLIDetector(commandRunner: runner, shellPath: "/bin/zsh", home: root, commonBinDirs: [])
        let rec = await det.probe(grok(), model: "x", now: .init(timeIntervalSince1970: 0), smoke: false)

        XCTAssertEqual(rec.invocation, .direct(path: stable), "stable launcher beats the versioned blob")
    }

    func testStillNotInstalledWhenNothingResolves() async throws {
        let root = try tmp()
        let runner = ClosureRunner { command, _ in
            if command == "/usr/bin/mdfind" { return CommandResult(stdout: "", exitCode: 0) }
            return kResolveEmptyGrok
        }
        let det = CLIDetector(commandRunner: runner, shellPath: "/bin/zsh", home: root, commonBinDirs: [])
        let rec = await det.probe(grok(), model: "x", now: .init(timeIntervalSince1970: 0), smoke: false)
        XCTAssertEqual(rec.status, .notInstalled)
    }
}
