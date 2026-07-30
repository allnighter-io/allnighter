import XCTest
import AllnighterCore
@testable import AllnighterCLI

/// RSC-S03 (`docs/archive/phases/Round_Survives_The_Caller.md`): the shared "re-launch this
/// same binary as a detached background process" helper — extracted from
/// `PilotCLI.dispatchHandoffInBackground` so `pair relay` / `relay-resume` /
/// `relay adopt`'s own `--no-wait` reuse it instead of growing a second
/// implementation. Mirrors `PilotCLITests`' `detachedHandoffLaunch` tests (real,
/// hermetic subprocess behavior — no network, no live workers).
final class DetachedDispatchTests: XCTestCase {
    private var tmp: URL!

    override func setUpWithError() throws {
        tmp = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("alln-detached-dispatch-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tmp)
    }

    // MARK: - launch: cwd + arguments actually reach the child

    /// Spawns a tiny shell script (never the real `alln` binary — hermetic, no
    /// network) that writes its cwd and argv to a marker file, then asserts both
    /// match what `launch` was given. The child's own stdio is null per the detached
    /// contract (agents poll status, they never tail a detached child's stdout), so
    /// verification goes through a side-effect file instead of captured output.
    func testLaunchSpawnsChildWithExpectedCwdAndArguments() throws {
        let cwd = tmp.appendingPathComponent("cwd-dir")
        try FileManager.default.createDirectory(at: cwd, withIntermediateDirectories: true)
        let marker = tmp.appendingPathComponent("marker.txt")
        let script = tmp.appendingPathComponent("probe.sh")
        let scriptBody = """
        #!/bin/sh
        pwd > "\(marker.path)"
        echo "$@" >> "\(marker.path)"
        """
        try scriptBody.write(to: script, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: script.path)

        let process = try DetachedDispatch.launch(
            cwd: cwd.path,
            arguments: ["alpha", "beta"],
            executableURL: script
        )
        process.waitUntilExit()
        XCTAssertEqual(process.terminationStatus, 0)

        let contents = try String(contentsOf: marker, encoding: .utf8)
        let lines = contents.split(separator: "\n", omittingEmptySubsequences: true).map(String.init)
        XCTAssertEqual(lines.count, 2)
        XCTAssertEqual(
            URL(fileURLWithPath: lines[0]).resolvingSymlinksInPath().path,
            cwd.resolvingSymlinksInPath().path
        )
        XCTAssertEqual(lines[1], "alpha beta")
    }

    /// Null stdio: the child's own stdout/stderr never reach the parent's — a detached
    /// dispatch is fire-and-forget by design (matches `pilot handoff --no-wait`).
    func testLaunchSetsNullStdio() throws {
        let script = tmp.appendingPathComponent("noisy.sh")
        try "#!/bin/sh\necho should never be seen\n".write(to: script, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: script.path)

        let process = try DetachedDispatch.launch(cwd: tmp.path, arguments: [], executableURL: script)
        XCTAssertTrue(process.standardOutput is FileHandle)
        XCTAssertTrue(process.standardError is FileHandle)
        XCTAssertTrue(process.standardInput is FileHandle)
        process.waitUntilExit()
    }

    func testLaunchThrowsUnresolvedExecutableWhenResolutionFails() {
        XCTAssertThrowsError(try DetachedDispatch.launch(
            cwd: tmp.path, arguments: [],
            argv0: "alln", pathEnvironment: tmp.appendingPathComponent("empty-bin").path,
            currentExecutablePath: { nil }
        )) { error in
            XCTAssertEqual(error as? DetachedDispatch.LaunchError, .unresolvedExecutable)
        }
    }

    // MARK: - childArguments: detached routing flags removed

    func testChildArgumentsRemovesOnlyTheNoWaitToken() {
        let argv = ["pair", "relay-resume", "--relay", "relay_1", "--answer", "go", "--no-wait", "--json"]
        XCTAssertEqual(
            DetachedDispatch.childArguments(from: argv),
            ["pair", "relay-resume", "--relay", "relay_1", "--answer", "go", "--json"]
        )
    }

    func testChildArgumentsNoOpWhenNoWaitAbsent() {
        let argv = ["pair", "relay", "--doc", "docs/spec.md", "--json"]
        XCTAssertEqual(DetachedDispatch.childArguments(from: argv), argv)
    }

    func testChildArgumentsPreservesNoAutoServe() {
        let argv = ["pair", "relay-resume", "--relay", "relay_1", "--answer", "go", "--no-wait", "--no-auto-serve"]
        XCTAssertEqual(
            DetachedDispatch.childArguments(from: argv),
            ["pair", "relay-resume", "--relay", "relay_1", "--answer", "go", "--no-auto-serve"]
        )
    }

    func testChildArgumentsRemovesWakeDeliveryValue() {
        let argv = ["run", "work", "--no-wait", "--delivery", "wake", "--json"]
        XCTAssertEqual(DetachedDispatch.childArguments(from: argv), ["run", "work", "--json"])
    }

    func testLaunchAndAwaitAcceptanceAccepted() throws {
        let script = tmp.appendingPathComponent("accept.sh")
        // Child writes runner_ready.json into $ALLNIGHTER_DETACHED_HANDOFF then exits.
        let scriptBody = """
        #!/bin/sh
        dir="$ALLNIGHTER_DETACHED_HANDOFF"
        printf '%s' '{"outcome":"accepted","runId":"relay_from_child"}' > "$dir/runner_ready.json"
        """
        try scriptBody.write(to: script, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: script.path)

        let acceptance = try DetachedDispatch.launchAndAwaitAcceptance(
            cwd: tmp.path,
            arguments: [],
            timeout: 5,
            executableURL: script
        )
        guard case .accepted(let id, _) = acceptance else {
            return XCTFail("expected accepted, got \(acceptance)")
        }
        XCTAssertEqual(id, "relay_from_child")
    }

    func testLaunchAndAwaitAcceptanceRefused() throws {
        let script = tmp.appendingPathComponent("refuse.sh")
        let scriptBody = """
        #!/bin/sh
        dir="$ALLNIGHTER_DETACHED_HANDOFF"
        printf '%s' '{"outcome":"refused","runId":"","refusalCode":"RELAY_ALREADY_ACTIVE","refusalMessage":"busy"}' > "$dir/runner_ready.json"
        """
        try scriptBody.write(to: script, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: script.path)

        let acceptance = try DetachedDispatch.launchAndAwaitAcceptance(
            cwd: tmp.path,
            arguments: [],
            timeout: 5,
            executableURL: script
        )
        guard case .refused(_, let code, let message, _) = acceptance else {
            return XCTFail("expected refused, got \(acceptance)")
        }
        XCTAssertEqual(code, "RELAY_ALREADY_ACTIVE")
        XCTAssertEqual(message, "busy")
    }

    // MARK: - DetachedDispatchJSON: one ack shape for every --no-wait verb

    func testDetachedDispatchJSONShape() throws {
        let ack = DetachedDispatchJSON(
            kind: "relay", id: "relay_test", status: "dispatched", pid: 4242,
            delivery: DetachedDispatch.waitDelivery(kind: "relay", id: "relay_test", commandPrefix: "alln"))
        let line = AllnighterCLI.jsonLine(ack)
        XCTAssertFalse(line.contains("\n"), "one-line NDJSON-style ack")
        let data = try XCTUnwrap(line.data(using: .utf8))
        let obj = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(obj["kind"] as? String, "relay")
        XCTAssertEqual(obj["id"] as? String, "relay_test")
        XCTAssertEqual(obj["status"] as? String, "dispatched")
        XCTAssertEqual(obj["pid"] as? Int, 4242)
        let delivery = try XCTUnwrap(obj["delivery"] as? [String: Any])
        XCTAssertEqual(delivery["path"] as? String, "wait")
        XCTAssertEqual(
            delivery["command"] as? String,
            "alln pair relay-status --relay relay_test --wait-for terminal --timeout 7200 --json"
        )
    }

    func testWaitDeliveryUsesExactSurfaceWaiters() {
        XCTAssertEqual(
            DetachedDispatch.waitDelivery(kind: "run", id: "run_test", commandPrefix: "/usr/local/bin/alln").command,
            "/usr/local/bin/alln team status run_test --wait-for terminal --timeout 7200 --json"
        )
        XCTAssertEqual(
            DetachedDispatch.waitDelivery(kind: "pilot", id: "relay_test", commandPrefix: "/usr/local/bin/alln").command,
            "/usr/local/bin/alln pair pilot status --relay relay_test --wait-for parked --timeout 7200 --json"
        )
    }

    func testWakeDeliveryAckOmitsWaitCommand() throws {
        let ack = DetachedDispatchJSON(
            kind: "run", id: "run_test", status: "dispatched", pid: 4242,
            delivery: DetachedDispatch.wakeDelivery())
        let data = try XCTUnwrap(AllnighterCLI.jsonLine(ack).data(using: .utf8))
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let delivery = try XCTUnwrap(object["delivery"] as? [String: Any])
        XCTAssertEqual(delivery["path"] as? String, "wake")
        XCTAssertNil(delivery["command"])
    }

    // MARK: - Structural: exactly one "resolve binary, build Process" implementation

    /// `PilotCLI.swift` and `RelayCLI.swift` must route detached spawn through
    /// `DetachedDispatch` — neither should construct its own `Process()` for
    /// this purpose.
    func testPilotAndRelayCLIDoNotConstructProcessDirectly() throws {
        let cliDir = sourcesRoot().appendingPathComponent("AllnighterCLI")
        for name in ["PilotCLI.swift", "RelayCLI.swift"] {
            let url = cliDir.appendingPathComponent(name)
            let text = try String(contentsOf: url, encoding: .utf8)
            XCTAssertFalse(
                text.contains("Process()"),
                "\(name) should route detached spawn through DetachedDispatch, not construct Process() directly"
            )
        }
    }

    private func sourcesRoot() -> URL {
        var url = URL(fileURLWithPath: #filePath)
        for _ in 0..<3 { url.deleteLastPathComponent() }
        return url.appendingPathComponent("Sources")
    }
}
