import XCTest
import AllnighterCore
@testable import AllnighterCLI

/// Pins the spawn mechanics that let a detached child outlive its launcher.
///
/// **Scope, stated honestly.** This does NOT prove end-to-end survival of a real
/// `alln run --no-wait` after the launching `alln` exits. That needs a launcher
/// process which itself calls `DetachedDispatch`, i.e. a helper executable
/// target, and it remains an open gap — see the note at the bottom of this file.
///
/// What it does prove is the specific configuration that makes survival
/// possible, against the real `DetachedDispatch.launch`: the child gets
/// `/dev/null` for all three streams and is never waited on. Inherited stdio is
/// what ties a background process to a terminal, so a child holding the
/// launcher's descriptors dies on SIGHUP when that terminal closes — the exact
/// shape of the orphaned-run failures this file exists to prevent.
///
/// A previous attempt at this (reverted, `91c5bb7b`) spawned `/bin/sh` with
/// `nohup` and never referenced `DetachedDispatch` at all, so it proved that
/// `nohup` works on macOS rather than anything about our code. Everything here
/// goes through the real function; delete the `nullDevice` lines from
/// `DetachedDispatch.launch` and these tests go red.
final class DetachedSpawnMechanismTests: XCTestCase {

    private var tmp: URL!
    private var spawned: Process?

    override func setUpWithError() throws {
        tmp = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("alln-detached-spawn-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        // Never leave a child behind, even on failure.
        if let p = spawned, p.isRunning { p.terminate() }
        try? FileManager.default.removeItem(at: tmp)
    }

    /// Reports the device identity behind fd 0/1/2 alongside `/dev/null`'s, so
    /// the test can compare them.
    ///
    /// `readlink /dev/fd/N` does not resolve on macOS — it returns nothing —
    /// so identity is taken from `stat -f %d:%i` (device + inode of what the
    /// descriptor actually points at) and compared against `/dev/null` measured
    /// in the same child. Comparing to a value measured here rather than a
    /// hardcoded one keeps it correct on any host.
    private func makeProbe() throws -> URL {
        let out = tmp.appendingPathComponent("streams.txt")
        let script = tmp.appendingPathComponent("probe.sh")
        try """
        #!/bin/sh
        # Duplicate the INHERITED descriptors before doing anything that
        # rebinds them. Writing the report with `> file` replaces fd 1, and
        # `$(...)` replaces it with a pipe — so reading /dev/fd/1 after either
        # would measure the probe's own plumbing instead of what was inherited.
        exec 3<&0 4>&1 5>&2
        id_of() { stat -f '%d:%i' "$1" 2>/dev/null || echo unknown; }
        {
          echo "null=$(id_of /dev/null)"
          echo "stdin=$(id_of /dev/fd/3)"
          echo "stdout=$(id_of /dev/fd/4)"
          echo "stderr=$(id_of /dev/fd/5)"
        } > "\(out.path)"
        """.write(to: script, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: script.path)
        return script
    }

    private func field(_ name: String, in text: String) -> String? {
        text.split(separator: "\n")
            .first { $0.hasPrefix(name + "=") }
            .map { String($0.dropFirst(name.count + 1)) }
    }

    /// Wait for the probe's report to be COMPLETE, not merely present.
    ///
    /// Returning on "non-empty" was a race: the probe writes four lines, and a
    /// read landing between them yielded a file with `null=` but no `stdin=`,
    /// so the assertion compared against `<missing>` and failed. It passed in
    /// isolation and failed under full-wall load, which is the signature of a
    /// timing bug in the proof rather than in the thing being proved.
    private func waitForFile(
        _ url: URL,
        requiring keys: [String] = [],
        timeout: TimeInterval = 10
    ) -> String? {
        let deadline = Date().addingTimeInterval(timeout)
        var last: String?
        while Date() < deadline {
            if let text = try? String(contentsOf: url, encoding: .utf8), !text.isEmpty {
                last = text
                if keys.allSatisfy({ text.contains($0 + "=") }) { return text }
            }
            usleep(50_000)
        }
        // Return whatever arrived so the failure message shows the partial
        // report instead of a bare nil.
        return last
    }

    /// The child must not inherit the launcher's descriptors. This is the
    /// property that keeps it alive when the launcher's terminal goes away.
    func testDetachedChildGetsNullStdioNotTheLaunchersDescriptors() throws {
        let probe = try makeProbe()
        let out = tmp.appendingPathComponent("streams.txt")

        spawned = try DetachedDispatch.launch(
            cwd: tmp.path,
            arguments: [],
            executableURL: probe
        )

        let observed = try XCTUnwrap(
            waitForFile(out, requiring: ["null", "stdin", "stdout", "stderr"]),
            "detached child never ran — DetachedDispatch.launch did not start the probe"
        )
        let nullId = try XCTUnwrap(field("null", in: observed), "probe did not report /dev/null identity")
        XCTAssertNotEqual(nullId, "unknown", "probe could not stat /dev/null, so the comparison below is meaningless")

        for stream in ["stdin", "stdout", "stderr"] {
            let actual = field(stream, in: observed) ?? "<missing>"
            XCTAssertEqual(
                actual, nullId,
                "\(stream) must be /dev/null in a detached child (expected \(nullId), got \(actual)). "
                + "An inherited descriptor ties the run to the launcher's terminal and "
                + "kills it on SIGHUP when that terminal closes."
            )
        }
    }

    /// The launcher must not block on the child. `launch` is fire-and-forget by
    /// contract, so it returns while the child is still running and never reaps
    /// it — a `waitUntilExit` here would make `--no-wait` synchronous.
    func testLaunchReturnsWithoutWaitingForTheChild() throws {
        let marker = tmp.appendingPathComponent("started.txt")
        let script = tmp.appendingPathComponent("slow.sh")
        try """
        #!/bin/sh
        echo started > "\(marker.path)"
        sleep 30
        """.write(to: script, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: script.path)

        let before = Date()
        spawned = try DetachedDispatch.launch(cwd: tmp.path, arguments: [], executableURL: script)
        let elapsed = Date().timeIntervalSince(before)

        XCTAssertLessThan(
            elapsed, 5,
            "launch() blocked for \(elapsed)s on a child that sleeps 30s — it must not wait"
        )
        XCTAssertNotNil(
            waitForFile(marker),
            "child never started, so the timing assertion above proved nothing"
        )
        XCTAssertTrue(
            try XCTUnwrap(spawned).isRunning,
            "child should still be running after launch() returned"
        )
    }

    /// An unresolvable executable must fail loudly at spawn time rather than
    /// returning a Process that was never started — a silently-dead child is
    /// indistinguishable from one that died later.
    func testUnresolvableExecutableFailsLoudly() {
        XCTAssertThrowsError(
            try DetachedDispatch.launch(
                cwd: tmp.path,
                arguments: [],
                executableURL: tmp.appendingPathComponent("does-not-exist")
            )
        )
    }
}

// MARK: - Known gap
//
// Still unproven: that a real `alln run --no-wait` child reaches a terminal
// state after the launching `alln` process exits. Proving it needs a launcher
// that itself calls `DetachedDispatch` and then dies, which means a helper
// executable target (the test process cannot be the dying launcher). Two
// delegated attempts produced a test that could not fail and a reconnaissance
// report; it is deliberately left open rather than papered over.
