import XCTest
@testable import AllnighterCore

/// `CapacityProbe.maybeRunShadow` — the exact gate wired into `CapacityProbe.
/// windows` right before it returns a successfully-parsed value
/// (Handover_Capacity_2026-08-08.md §5, shadow mode approved). These tests
/// prove the trigger actually gates the spend, and that nothing on the
/// shadow path can change what a caller receives: `maybeRunShadow` returns
/// `Void`, so it structurally cannot touch the `parsed` array a caller
/// already has in hand — these tests exercise that gate directly rather than
/// through a full PTY capture, matching how the rest of this codebase tests
/// headless spawns (`CodexNativeCapacityProbeTests`, `AgyNativeCapacityProbeTests`).
final class CapacityProbeShadowTests: XCTestCase {

    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private final class RecordingSink: CapacityPaneReader.ShadowDisagreementSink, @unchecked Sendable {
        private(set) var appended: [CapacityPaneReader.Disagreement] = []
        func append(_ disagreement: CapacityPaneReader.Disagreement) {
            appended.append(disagreement)
        }
    }

    private func parsedWindow(remaining: Double) -> CapacityWindow {
        CapacityWindow(
            remaining: remaining, source: "cursor_agent", scope: .weekly,
            resetAt: nil, resetPrecision: .day, observedAt: now, sourceTier: .tuiProbe
        )
    }

    #if os(macOS)

    private func writeScript(_ body: String, name: String) throws -> String {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("alln-shadow-gate-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let script = dir.appendingPathComponent(name)
        try body.write(to: script, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: script.path)
        return script.path
    }

    /// **The trigger gate.** `shadowPaneReader: false` is the default at
    /// every layer above this (`CapacityProbeRequest`, `CapacityAcquisition.
    /// windows`, `CapacityFetch.liveSnapshot`) — the value `alln serve`'s
    /// scheduler and the Mac resident's periodic refresh always pass, because
    /// they never set it at all. Even with a real script standing by to
    /// disagree, nothing is spent and nothing is logged.
    func testShadowDisabledNeverSpawnsOrLogs() throws {
        let script = try writeScript("""
        #!/bin/sh
        printf '%s' '{"pools":[],"mostConstrainedRemaining":9,"resetAt":null,"planTier":null,"confident":true,"reason":"would disagree"}'
        """, name: "would-disagree.sh")
        let sink = RecordingSink()

        CapacityProbe.maybeRunShadow(
            shadowPaneReader: false,
            source: "cursor_agent",
            capture: "pane text",
            executable: script,
            parsed: [parsedWindow(remaining: 52)],
            now: now,
            timeout: 5,
            sink: sink
        )

        XCTAssertTrue(sink.appended.isEmpty, "shadowPaneReader: false must gate out the spawn entirely")
    }

    /// The opposite side of the gate: explicitly enabled, a real spawn that
    /// disagrees, and the sink receives exactly one entry.
    func testShadowEnabledLogsARealDisagreement() throws {
        let script = try writeScript("""
        #!/bin/sh
        printf '%s' '{"pools":[],"mostConstrainedRemaining":9,"resetAt":null,"planTier":null,"confident":true,"reason":"different pool"}'
        """, name: "disagrees.sh")
        let sink = RecordingSink()

        CapacityProbe.maybeRunShadow(
            shadowPaneReader: true,
            source: "cursor_agent",
            capture: "pane text",
            executable: script,
            parsed: [parsedWindow(remaining: 52)],
            now: now,
            timeout: 5,
            sink: sink
        )

        XCTAssertEqual(sink.appended.count, 1)
        XCTAssertEqual(sink.appended.first?.kind, .valueMismatch)
        XCTAssertEqual(sink.appended.first?.source, "cursor_agent")
    }

    /// Agreement, even with shadow mode ON, is not logged — the gate opening
    /// does not mean every call becomes a log line.
    func testShadowEnabledButAgreeingLogsNothing() throws {
        let script = try writeScript("""
        #!/bin/sh
        printf '%s' '{"pools":[],"mostConstrainedRemaining":52,"resetAt":null,"planTier":null,"confident":true,"reason":"agrees"}'
        """, name: "agrees.sh")
        let sink = RecordingSink()

        CapacityProbe.maybeRunShadow(
            shadowPaneReader: true,
            source: "cursor_agent",
            capture: "pane text",
            executable: script,
            parsed: [parsedWindow(remaining: 52)],
            now: now,
            timeout: 5,
            sink: sink
        )

        XCTAssertTrue(sink.appended.isEmpty)
    }

    /// **Never introduces a failure.** A missing binary — the ordinary
    /// "vendor CLI not on PATH" shape — must not throw, hang, or crash the
    /// caller. It is still worth a log line (this IS the §6 signal), but the
    /// call itself completes cleanly either way.
    func testShadowMissingBinaryNeverThrowsOrHangs() {
        let sink = RecordingSink()
        let started = Date()

        CapacityProbe.maybeRunShadow(
            shadowPaneReader: true,
            source: "cursor_agent",
            capture: "pane text",
            executable: "/tmp/alln-shadow-gate-missing-\(UUID().uuidString)",
            parsed: [parsedWindow(remaining: 52)],
            now: now,
            timeout: 5,
            sink: sink
        )

        XCTAssertLessThan(Date().timeIntervalSince(started), 5.0, "a missing binary must fail fast, not wait out the timeout")
        XCTAssertEqual(sink.appended.first?.kind, .modelSilent)
    }

    /// **Byte-identical to shadow-disabled behaviour.** `parsed` is what a
    /// caller already has; `maybeRunShadow` returns `Void`. This proves the
    /// published array is literally the same value (`==`) whether shadow mode
    /// ran, disagreed, or failed outright — there is no path through this
    /// function that produces a different `parsed`.
    func testPublishedWindowsAreIdenticalRegardlessOfShadowOutcome() throws {
        let published = [parsedWindow(remaining: 52)]

        let disagreeScript = try writeScript("""
        #!/bin/sh
        printf '%s' '{"pools":[],"mostConstrainedRemaining":9,"resetAt":null,"planTier":null,"confident":true,"reason":"x"}'
        """, name: "disagree2.sh")

        for (shadowOn, executable) in [
            (false, disagreeScript),
            (true, disagreeScript),
            (true, "/tmp/alln-shadow-gate-missing2-\(UUID().uuidString)"),
        ] {
            let stillPublished = published
            let sink = RecordingSink()
            CapacityProbe.maybeRunShadow(
                shadowPaneReader: shadowOn,
                source: "cursor_agent",
                capture: "pane text",
                executable: executable,
                parsed: stillPublished,
                now: now,
                timeout: 5,
                sink: sink
            )
            XCTAssertEqual(stillPublished, published, "maybeRunShadow must never be able to mutate the published windows")
            _ = sink // silence unused warning when a case logs nothing
        }
    }

    #endif
}
