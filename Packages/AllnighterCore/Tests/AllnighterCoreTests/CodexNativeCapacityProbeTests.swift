import XCTest
@testable import AllnighterCore

/// Tests for `CodexNativeCapacityProbe` — codex's app-server JSON-RPC channel
/// (`Capacity_Native_Channels.md` §2). The response fixture below is the REAL
/// payload observed live from `account/rateLimits/read` on the dogfood host on
/// 2026-08-08, not an invented shape. `resetsAt: 1786825938` is
/// `2026-08-15T20:32:18Z` — the exact instant the TUI's `HH:MM on D Mon`
/// string was being misread as UTC instead of the host's local time (the
/// bug fixed alongside this channel in `CodexCapacityProbe`).
final class CodexNativeCapacityProbeTests: XCTestCase {

    /// Verbatim shape from the real `id: 2` response.
    private let realResponseLine = #"""
    {"id":2,"result":{"rateLimits":{"limitId":"codex","primary":{"usedPercent":5,"windowDurationMins":10080,"resetsAt":1786825938},"secondary":null,"credits":{"hasCredits":false,"unlimited":false,"balance":"0"},"individualLimit":null,"spendControlReached":false,"planType":"plus","rateLimitReachedType":null},"rateLimitsByLimitId":{"codex":{"limitId":"codex","primary":{"usedPercent":5,"windowDurationMins":10080,"resetsAt":1786825938},"secondary":null}},"rateLimitResetCredits":{"availableCount":0,"credits":[]}}}
    """#

    private var fixedObservedAt: Date {
        Date(timeIntervalSince1970: 1_753_786_860)
    }

    // MARK: - The real response

    func testRealResponseParsesWeeklyPrimaryWindow() throws {
        let windows = CodexNativeCapacityProbe.capacityWindows(
            fromResponseLine: realResponseLine, observedAt: fixedObservedAt
        )
        XCTAssertEqual(windows.count, 1, "secondary is null on this plan — must not be fabricated into a second window")
        let w = try XCTUnwrap(windows.first)

        XCTAssertEqual(w.source, "codex")
        XCTAssertEqual(w.scope, .weekly)
        XCTAssertEqual(w.sourceTier, .headlessJSON)
        XCTAssertEqual(w.resetPrecision, .exact)
        XCTAssertEqual(w.planTier, "plus")
        XCTAssertNil(w.unknownReason)

        // Used-polarity, never inverted: usedPercent 5 → remaining 95.
        XCTAssertEqual(w.usedPercent ?? -1, 5.0, accuracy: 1e-9)
        XCTAssertEqual(w.remainingPercent ?? -1, 95.0, accuracy: 1e-9)

        // THE acceptance bar: the epoch, not a rendered/re-derived string.
        let reset = try XCTUnwrap(w.resetAt)
        XCTAssertEqual(reset, Date(timeIntervalSince1970: 1_786_825_938))
        let iso = ISO8601DateFormatter()
        XCTAssertEqual(iso.string(from: reset), "2026-08-15T20:32:18Z")
    }

    // MARK: - Fail closed: JSON-RPC error

    func testJSONRPCErrorResponseYieldsNoObservation() {
        let payload = #"{"id":2,"error":{"code":-32000,"message":"boom"}}"#
        XCTAssertTrue(
            CodexNativeCapacityProbe.capacityWindows(fromResponseLine: payload, observedAt: fixedObservedAt).isEmpty
        )
    }

    // MARK: - Fail closed: unrecognized / missing shape

    func testMissingResultOrRateLimitsYieldsNoObservation() {
        for payload in [
            #"{"id":2}"#,
            #"{"id":2,"result":{}}"#,
            #"{"id":2,"result":{"rateLimits":null}}"#,
        ] {
            XCTAssertTrue(
                CodexNativeCapacityProbe.capacityWindows(fromResponseLine: payload, observedAt: fixedObservedAt).isEmpty,
                "must fail closed on: \(payload)"
            )
        }
    }

    func testMalformedAndEmptyInputYieldsNoObservationWithoutThrowing() {
        for garbage in ["", "not json", "{", "null", "[]", "   \n\t  "] {
            XCTAssertTrue(
                CodexNativeCapacityProbe.capacityWindows(fromResponseLine: garbage, observedAt: fixedObservedAt).isEmpty,
                "must fail closed on: \(garbage)"
            )
        }
    }

    func testUnrecognizedWindowDurationIsSkippedNotGuessed() {
        // 43200 (free-tier monthly-ish) is not one of the two recognized
        // scopes — must be dropped, not guessed into weekly or fiveHour.
        let payload = #"""
        {"id":2,"result":{"rateLimits":{"planType":"free","primary":\#
        {"usedPercent":10,"windowDurationMins":43200,"resetsAt":1786825938},"secondary":null}}}
        """#
        XCTAssertTrue(
            CodexNativeCapacityProbe.capacityWindows(fromResponseLine: payload, observedAt: fixedObservedAt).isEmpty
        )
    }

    func testMissingResetsAtIsSkipped() {
        let payload = #"""
        {"id":2,"result":{"rateLimits":{"planType":"plus","primary":\#
        {"usedPercent":10,"windowDurationMins":10080},"secondary":null}}}
        """#
        XCTAssertTrue(
            CodexNativeCapacityProbe.capacityWindows(fromResponseLine: payload, observedAt: fixedObservedAt).isEmpty
        )
    }

    func testMissingUsedPercentIsSkipped() {
        let payload = #"""
        {"id":2,"result":{"rateLimits":{"planType":"plus","primary":\#
        {"windowDurationMins":10080,"resetsAt":1786825938},"secondary":null}}}
        """#
        XCTAssertTrue(
            CodexNativeCapacityProbe.capacityWindows(fromResponseLine: payload, observedAt: fixedObservedAt).isEmpty
        )
    }

    /// `doubleValue`/`intValue`/`unixDate` all check `any as? Double`/`any as?
    /// Int` before their `CFBoolean` guard — Swift's dynamic cast coerces a
    /// JSON `true`/`false` straight through those casts into `1.0`/`1`/etc,
    /// so an unfixed helper would silently turn a boolean `usedPercent` into
    /// a valid-looking 1% instead of refusing the whole slot. Same bug shape
    /// `ClaudeNativeCapacityProbe` fixed in 335d96a1; this is the untested
    /// sibling `335d96a1` flagged and left for a follow-up.
    func testBooleanUsedPercentIsRefusedNotCoerced() {
        let payload = #"""
        {"id":2,"result":{"rateLimits":{"planType":"plus","primary":\#
        {"usedPercent":true,"windowDurationMins":10080,"resetsAt":1786825938},"secondary":null}}}
        """#
        XCTAssertTrue(
            CodexNativeCapacityProbe.capacityWindows(fromResponseLine: payload, observedAt: fixedObservedAt).isEmpty,
            "a boolean usedPercent must be refused, never coerced into 1.0/0.0"
        )
    }

    /// Regression for a real trap in the naive fix: `(0 as NSNumber) is Bool`
    /// and `(1 as NSNumber) is Bool` are BOTH `true` on Darwin — a helper
    /// "fixed" with a blanket `any is Bool` pre-check (rather than checking
    /// `CFGetTypeID` on the `NSNumber` branch first) would silently refuse a
    /// legitimate `usedPercent: 0` or `usedPercent: 1`, which are completely
    /// ordinary real values. Both must parse normally.
    func testZeroAndOneUsedPercentAreNotRefusedAsBooleans() throws {
        let payload = #"""
        {"id":2,"result":{"rateLimits":{"planType":"plus","primary":\#
        {"usedPercent":0,"windowDurationMins":10080,"resetsAt":1786825938},\#
        "secondary":{"usedPercent":1,"windowDurationMins":300,"resetsAt":1786800000}}}}
        """#
        let windows = CodexNativeCapacityProbe.capacityWindows(fromResponseLine: payload, observedAt: fixedObservedAt)
        XCTAssertEqual(windows.count, 2, "usedPercent: 0 and 1 must both parse, never refused as booleans")
        let weekly = try XCTUnwrap(windows.first { $0.scope == .weekly })
        XCTAssertEqual(weekly.usedPercent ?? -1, 0.0, accuracy: 1e-9)
        let fiveHour = try XCTUnwrap(windows.first { $0.scope == .fiveHour })
        XCTAssertEqual(fiveHour.usedPercent ?? -1, 1.0, accuracy: 1e-9)
    }

    func testBothWindowsPresentWhenSecondaryIsNotNull() throws {
        // Not observed live on this host (plan has no short window), but the
        // parser must not special-case "secondary is always null" — a
        // five-hour secondary on another plan must come through too.
        let payload = #"""
        {"id":2,"result":{"rateLimits":{"planType":"pro","primary":\#
        {"usedPercent":5,"windowDurationMins":10080,"resetsAt":1786825938},\#
        "secondary":{"usedPercent":20,"windowDurationMins":300,"resetsAt":1786800000}}}}
        """#
        let windows = CodexNativeCapacityProbe.capacityWindows(fromResponseLine: payload, observedAt: fixedObservedAt)
        XCTAssertEqual(Set(windows.map(\.scope)), [.weekly, .fiveHour])
        for w in windows {
            XCTAssertEqual(w.sourceTier, .headlessJSON)
            XCTAssertEqual(w.planTier, "pro")
        }
    }

    // MARK: - Request construction

    func testRequestLinesAreTwoNewlineDelimitedJSONRPCObjects() throws {
        let body = CodexNativeCapacityProbe.requestLines()
        let lines = body.split(separator: "\n", omittingEmptySubsequences: true).map(String.init)
        XCTAssertEqual(lines.count, 2)

        let first = try decodeObject(lines[0])
        XCTAssertEqual(first["method"] as? String, "initialize")
        XCTAssertEqual(first["id"] as? Int, CodexNativeCapacityProbe.initializeRequestId)
        XCTAssertEqual(first["jsonrpc"] as? String, "2.0")

        let second = try decodeObject(lines[1])
        XCTAssertEqual(second["method"] as? String, "account/rateLimits/read")
        XCTAssertEqual(second["id"] as? Int, CodexNativeCapacityProbe.rateLimitsRequestId)
    }

    private func decodeObject(_ line: String) throws -> [String: Any] {
        let data = try XCTUnwrap(line.data(using: .utf8))
        let obj = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        return obj
    }

    // MARK: - Line matching (interleaved notifications, wrong id)

    func testMatchingLineIgnoresNotificationsAndOtherIds() {
        // An unsolicited notification has no "id" at all.
        XCTAssertNil(CodexNativeCapacityProbe.matchingLine(
            #"{"jsonrpc":"2.0","method":"remoteControl/status/changed","params":{}}"#, id: 2
        ))
        // The initialize ack (id 1) must not satisfy a match for id 2.
        XCTAssertNil(CodexNativeCapacityProbe.matchingLine(
            #"{"jsonrpc":"2.0","id":1,"result":{}}"#, id: 2
        ))
        // Garbage never throws, never matches.
        XCTAssertNil(CodexNativeCapacityProbe.matchingLine("not json", id: 2))
        XCTAssertNil(CodexNativeCapacityProbe.matchingLine("", id: 2))
        // The real match.
        XCTAssertEqual(
            CodexNativeCapacityProbe.matchingLine(#"{"id":2,"result":{}}"#, id: 2),
            #"{"id":2,"result":{}}"#
        )
    }

    // MARK: - Live process I/O (fixture "vendor CLI" scripts, macOS only)

    #if os(macOS)

    /// Writes an executable shell script and returns its path.
    private func writeScript(_ body: String, name: String) throws -> String {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("alln-codex-native-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let script = dir.appendingPathComponent(name)
        try body.write(to: script, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: script.path)
        return script.path
    }

    /// Real end-to-end shape: an unsolicited notification interleaved between
    /// the `initialize` ack and the `account/rateLimits/read` answer, on a
    /// process that — like the real `codex app-server` — never exits on its
    /// own (`exec sleep 60`, matching the timeout-kill test convention already
    /// used for `kimi` in `CapacityAcquisitionTests`).
    func testRunJSONRPCMatchesIdThroughInterleavedNotificationOnPersistentServer() throws {
        let script = try writeScript("""
        #!/bin/sh
        printf '%s\\n' '{"jsonrpc":"2.0","id":1,"result":{"ok":true}}'
        printf '%s\\n' '{"jsonrpc":"2.0","method":"remoteControl/status/changed","params":{}}'
        printf '%s\\n' '\(realResponseLine)'
        exec /bin/sleep 60
        """, name: "fake-app-server.sh")

        let started = Date()
        let line = CodexNativeCapacityProbe.runJSONRPC(
            executable: script,
            requestBody: CodexNativeCapacityProbe.requestLines(),
            timeout: 8,
            matchId: CodexNativeCapacityProbe.rateLimitsRequestId
        )
        let elapsed = Date().timeIntervalSince(started)

        let matched = try XCTUnwrap(line)
        let windows = CodexNativeCapacityProbe.capacityWindows(fromResponseLine: matched, observedAt: fixedObservedAt)
        XCTAssertEqual(windows.first?.scope, .weekly)
        XCTAssertEqual(windows.first?.usedPercent ?? -1, 5.0, accuracy: 1e-9)

        // Must return as soon as it matched — nowhere near the 8s budget or
        // the 60s sleep.
        XCTAssertLessThan(elapsed, 4.0, "must return promptly on match, not wait out the budget")

        try assertNoOrphan(scriptPath: script)
    }

    /// **Regression for the real live bug, not a shape a fixture could pass by
    /// accident.** Measured live against `codex app-server` 0.147.0: writing
    /// both requests and then closing stdin — even after both were fully
    /// written — makes it exit without ever answering
    /// `account/rateLimits/read`. It reads EOF as shutdown and abandons
    /// in-flight work. The first version of this channel closed stdin right
    /// after writing (a reasonable-looking cleanup step) and silently never
    /// worked end to end, while every fixture test here still passed, because
    /// none of those fixture scripts cared whether stdin was open or closed.
    ///
    /// This fixture DOES care: it consumes the two incoming request lines,
    /// answers `id 1`, then probes whether stdin is still open. If the caller
    /// closed it, this script reproduces the real failure — it never answers
    /// `id 2` — so a caller that regresses to closing stdin gets a timeout and
    /// `nil` here, not a silent pass.
    func testFetchNeverClosesStdinBeforeTheAnswerArrives() throws {
        let script = try writeScript("""
        #!/bin/bash
        read -r _
        read -r _
        echo '{"jsonrpc":"2.0","id":1,"result":{"ok":true}}'

        start=$(date +%s)
        read -r -t 2 extra
        elapsed=$(( $(date +%s) - start ))

        if [ "$elapsed" -eq 0 ]; then
          # stdin was already closed (EOF) — reproduce the real bug: hang
          # without ever answering, exactly like the real process does.
          exec /bin/sleep 60
        fi

        echo '\(realResponseLine)'
        exec /bin/sleep 60
        """, name: "fake-app-server-stdin-probe.sh")

        let windows = CodexNativeCapacityProbe.fetch(executable: script, now: fixedObservedAt, timeout: 6)

        try assertNoOrphan(scriptPath: script)

        let unwrapped = try XCTUnwrap(
            windows,
            "fetch must keep stdin open until it has its answer — closing it early reproduces the real app-server bug where account/rateLimits/read is never answered"
        )
        XCTAssertEqual(unwrapped.first?.scope, .weekly)
        XCTAssertEqual(unwrapped.first?.resetAt, Date(timeIntervalSince1970: 1_786_825_938))
    }

    /// A server that never answers `account/rateLimits/read` (only
    /// notifications, then hangs like the real, persistent process) must time
    /// out and be killed — never hang the caller, never fabricate a window.
    func testRunJSONRPCTimesOutAndKillsChildWhenIdNeverArrives() throws {
        let script = try writeScript("""
        #!/bin/sh
        printf '%s\\n' '{"jsonrpc":"2.0","method":"remoteControl/status/changed","params":{}}'
        exec /bin/sleep 60
        """, name: "fake-app-server-hang.sh")

        let started = Date()
        let line = CodexNativeCapacityProbe.runJSONRPC(
            executable: script,
            requestBody: CodexNativeCapacityProbe.requestLines(),
            timeout: 1.2,
            matchId: CodexNativeCapacityProbe.rateLimitsRequestId
        )
        let elapsed = Date().timeIntervalSince(started)

        XCTAssertNil(line)
        XCTAssertLessThan(elapsed, 5.0, "must not wait out the 60s sleep")

        try assertNoOrphan(scriptPath: script)
    }

    /// `fetch` end to end against the missing-binary case — never throws,
    /// returns nil so `CapacityProbe.windows` is free to fall through to the
    /// TUI probe.
    func testFetchReturnsNilWhenBinaryMissing() {
        let windows = CodexNativeCapacityProbe.fetch(
            executable: "/tmp/alln-codex-native-missing-\(UUID().uuidString)",
            now: fixedObservedAt,
            timeout: 2
        )
        XCTAssertNil(windows)
    }

    /// Best-effort orphan check — write `ps` output to a file rather than a
    /// Pipe (a Pipe deadlocks on large output before the parent drains it;
    /// same convention as `CapacityAcquisitionTests`'s timeout-kill test).
    private func assertNoOrphan(scriptPath: String, file: StaticString = #filePath, line: UInt = #line) throws {
        let psOut = FileManager.default.temporaryDirectory
            .appendingPathComponent("alln-codex-native-ps-\(UUID().uuidString).txt")
        FileManager.default.createFile(atPath: psOut.path, contents: nil)
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/ps")
        task.arguments = ["-ax", "-o", "command="]
        task.standardOutput = try FileHandle(forWritingTo: psOut)
        task.standardError = FileHandle.nullDevice
        try task.run()
        task.waitUntilExit()
        try (task.standardOutput as? FileHandle)?.close()
        let ps = (try? String(contentsOf: psOut, encoding: .utf8)) ?? ""
        try? FileManager.default.removeItem(at: psOut)
        XCTAssertFalse(
            ps.contains(scriptPath),
            "app-server fixture must be terminated, not orphaned",
            file: file, line: line
        )
    }

    #endif

    // MARK: - Fallback still engages (mirrors AgyNativeCapacityProbeTests)

    /// A native probe against a missing binary must fail closed (never throw,
    /// never fabricate), leaving `CapacityProbe.windows` free to fall through
    /// to the `/status` TUI scrape as codex's fallback.
    func testCapacityProbeFallsThroughToSpawnFailedWhenNativeChannelUnavailable() throws {
        #if os(macOS)
        let windows = CapacityProbe.windows(
            source: "codex",
            now: fixedObservedAt,
            timeout: 2,
            executableOverride: "/tmp/alln-codex-native-missing-\(UUID().uuidString)"
        )
        XCTAssertEqual(windows.count, 1)
        XCTAssertEqual(windows[0].unknownReason, .spawnFailed(observedAt: fixedObservedAt))
        XCTAssertNil(windows[0].usedPercent)
        XCTAssertNil(windows[0].remainingPercent)
        #else
        throw XCTSkip("PTY probe is macOS-only")
        #endif
    }
}
