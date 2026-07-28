import XCTest
import AllnighterCore
@testable import AllnighterCLI
@testable import AllnighterEngine

/// RSC-HF hostile subprocess proofs: real OS children + shell scripts (never live
/// vendor workers). Complements `DetachedDispatchTests` with acceptance-timing,
/// kill-before-ready, argv preservation, run-id path traversal, and doc-path
/// normalization for relay start keys.
final class RSCHostileDetachedTests: XCTestCase {
    private var tmp: URL!

    override func setUpWithError() throws {
        tmp = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("alln-rsc-hostile-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tmp)
    }

    // MARK: - Acceptance handshake across a real child process

    /// Parent must block until the child writes `runner_ready.json` — not merely
    /// until `Process.run` returns.
    func testParentAcceptsOnlyAfterChildWritesRunnerReady() throws {
        let marker = tmp.appendingPathComponent("ready-marker.txt")
        let script = tmp.appendingPathComponent("delayed-accept.sh")
        let scriptBody = """
        #!/bin/sh
        sleep 0.4
        dir="$ALLNIGHTER_DETACHED_HANDOFF"
        printf '%s' '{"outcome":"accepted","runId":"relay_delayed"}' > "$dir/runner_ready.json"
        date +%s > "\(marker.path)"
        """
        try scriptBody.write(to: script, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: script.path)

        let start = Date()
        let acceptance = try DetachedDispatch.launchAndAwaitAcceptance(
            cwd: tmp.path,
            arguments: [],
            timeout: 5,
            executableURL: script
        )
        let elapsed = Date().timeIntervalSince(start)

        guard case .accepted(let id, _) = acceptance else {
            return XCTFail("expected accepted, got \(acceptance)")
        }
        XCTAssertEqual(id, "relay_delayed")
        XCTAssertGreaterThanOrEqual(elapsed, 0.35, "parent must wait for child's runner_ready, not just Process.run")
        XCTAssertTrue(FileManager.default.fileExists(atPath: marker.path), "child must finish writing ready before parent returns")
    }

    /// Child killed before writing ready → parent surfaces `.timedOut`, not a false accept.
    func testParentTimesOutWhenChildDiesBeforeReady() throws {
        let script = tmp.appendingPathComponent("die-early.sh")
        try "#!/bin/sh\nexit 0\n".write(to: script, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: script.path)

        let acceptance = try DetachedDispatch.launchAndAwaitAcceptance(
            cwd: tmp.path,
            arguments: [],
            timeout: 0.5,
            executableURL: script
        )
        guard case .timedOut = acceptance else {
            return XCTFail("expected timedOut when child exits without runner_ready, got \(acceptance)")
        }
    }

    /// `childArguments` strips only `--no-wait`; `--no-auto-serve` must reach the child argv.
    func testChildProcessReceivesNoAutoServeAfterChildArguments() throws {
        let marker = tmp.appendingPathComponent("argv-marker.txt")
        let script = tmp.appendingPathComponent("argv-probe.sh")
        let scriptBody = """
        #!/bin/sh
        printf '%s' "$@" > "\(marker.path)"
        dir="$ALLNIGHTER_DETACHED_HANDOFF"
        printf '%s' '{"outcome":"accepted","runId":"relay_argv"}' > "$dir/runner_ready.json"
        """
        try scriptBody.write(to: script, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: script.path)

        let parentArgv = [
            "pair", "relay-resume", "--relay", "relay_1", "--answer", "go",
            "--no-wait", "--no-auto-serve", "--json"
        ]
        let childArgv = DetachedDispatch.childArguments(from: parentArgv)
        XCTAssertTrue(childArgv.contains("--no-auto-serve"))
        XCTAssertFalse(childArgv.contains("--no-wait"))

        let acceptance = try DetachedDispatch.launchAndAwaitAcceptance(
            cwd: tmp.path,
            arguments: childArgv,
            timeout: 5,
            executableURL: script
        )
        guard case .accepted = acceptance else {
            return XCTFail("expected accepted, got \(acceptance)")
        }
        let recorded = try String(contentsOf: marker, encoding: .utf8)
        XCTAssertTrue(recorded.contains("--no-auto-serve"), "child argv must preserve --no-auto-serve: \(recorded)")
        XCTAssertFalse(recorded.contains("--no-wait"), "child argv must not contain --no-wait: \(recorded)")
    }

    // MARK: - Run id path traversal (defense in depth)

    func testValidateRunIdRejectsTraversalSegments() {
        XCTAssertThrowsError(try RunStore.validateRunId("../x")) { error in
            XCTAssertEqual(error as? RunStore.RunStoreError, .unsafeRunId("../x"))
        }
        XCTAssertThrowsError(try RunStore.validateRunId("a/b")) { error in
            XCTAssertEqual(error as? RunStore.RunStoreError, .unsafeRunId("a/b"))
        }
    }

    func testRunDirectoryRejectsTraversalSegments() throws {
        let store = RunStore(rootDirectory: tmp.appendingPathComponent("runs"))
        XCTAssertThrowsError(try store.runDirectory(forRunId: "../x"))
        XCTAssertThrowsError(try store.runDirectory(forRunId: "a/b"))
    }

    // MARK: - Relay start-key doc path normalization

    func testNormalizeDocPathCollapsesLeadingDotSlash() {
        XCTAssertEqual(RelayDispatchLock.normalizeDocPath("./docs/spec.md"), "docs/spec.md")
        XCTAssertEqual(RelayDispatchLock.normalizeDocPath("docs/spec.md"), "docs/spec.md")
    }

    func testStartKeyEqualForEquivalentDocPaths() {
        let root = "/Users/test/project"
        let keyPlain = RelayDispatchLock.startKey(projectRoot: root, docPath: "docs/spec.md")
        let keyDotted = RelayDispatchLock.startKey(projectRoot: root, docPath: "./docs/spec.md")
        XCTAssertEqual(keyPlain, keyDotted)
    }
}
