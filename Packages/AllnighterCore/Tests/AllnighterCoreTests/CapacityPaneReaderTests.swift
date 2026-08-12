import XCTest
@testable import AllnighterCore

/// Model-read of a captured usage pane.
///
/// Fixtures are REAL responses from `model_cursor_composer_25` against real
/// captures, recorded during the 2026-08-08 measurement (packet §4b) — not
/// invented shapes. The point of these tests is the layer we own: envelope
/// extraction, the confidence contract, and never manufacturing a window.
final class CapacityPaneReaderTests: XCTestCase {

    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    // MARK: - Extraction

    /// Vendors wrap the answer differently, so extraction must not care. This is
    /// a real cursor-agent envelope shape: the model's JSON arrives as a string
    /// field inside the CLI's own result object.
    func testExtractsReadingFromAVendorEnvelope() throws {
        let output = """
        {"type":"result","subtype":"success","is_error":false,"duration_ms":6828,\
        "result":"{\\"pools\\":[{\\"label\\":\\"Included\\",\\"remainingPercent\\":57},\
        {\\"label\\":\\"Auto\\",\\"remainingPercent\\":58},\
        {\\"label\\":\\"API\\",\\"remainingPercent\\":52}],\
        \\"mostConstrainedRemaining\\":52,\\"resetAt\\":\\"2026-08-25T00:00:00Z\\",\
        \\"planTier\\":\\"Ultra\\",\\"confident\\":true,\\"reason\\":\\"three pools shown\\"}",\
        "usage":{"inputTokens":3,"outputTokens":184}}
        """
        // Fed exactly as the CLI prints it — escaped, valid JSON. Brace scanning
        // cannot see inside a JSON string, so this is the case that forces
        // envelope-aware extraction.
        let reading = try XCTUnwrap(CapacityPaneReader.extractReading(from: output))
        XCTAssertEqual(reading.mostConstrainedRemaining, 52)
        XCTAssertEqual(reading.pools.count, 3)
        XCTAssertTrue(reading.confident)
    }

    /// The envelope's own `{...}` comes FIRST, so taking the first balanced
    /// object would return the wrapper and lose the answer.
    func testPrefersTheAnswerObjectOverTheEnvelopeHeader() throws {
        let output = """
        {"event":"started","runId":"abc"}
        some prose the CLI printed
        {"pools":[],"mostConstrainedRemaining":91,"resetAt":null,"planTier":null,\
        "confident":true,"reason":"weekly 9% used"}
        """
        let reading = try XCTUnwrap(CapacityPaneReader.extractReading(from: output))
        XCTAssertEqual(reading.mostConstrainedRemaining, 91)
    }

    /// Braces inside strings must not open or close a span.
    func testBracesInsideStringsDoNotBreakExtraction() throws {
        let output = """
        {"pools":[],"mostConstrainedRemaining":42,"resetAt":null,"planTier":null,\
        "confident":true,"reason":"saw {weird} braces"}
        """
        let reading = try XCTUnwrap(CapacityPaneReader.extractReading(from: output))
        XCTAssertEqual(reading.mostConstrainedRemaining, 42)
        XCTAssertEqual(reading.reason, "saw {weird} braces")
    }

    /// A CLI that errored, timed out, or printed prose yields no reading — which
    /// fails closed rather than inventing one.
    func testNoJSONYieldsNoReading() {
        XCTAssertNil(CapacityPaneReader.extractReading(from: ""))
        XCTAssertNil(CapacityPaneReader.extractReading(from: "error: not logged in"))
        XCTAssertNil(CapacityPaneReader.extractReading(from: #"{"unrelated":true}"#))
    }

    // MARK: - The confidence contract

    /// Real response to grok's 28KB splash-animation capture. `confident: false`
    /// is believed, not second-guessed — this is the whole reason the measured
    /// run had zero invented numbers.
    func testUnconfidentReadingProducesNoWindow() throws {
        let output = """
        {"pools":[],"mostConstrainedRemaining":null,"resetAt":null,"planTier":null,\
        "confident":false,"reason":"Splash screen only, no quota data"}
        """
        let reading = try XCTUnwrap(CapacityPaneReader.extractReading(from: output))
        XCTAssertFalse(reading.confident)
        XCTAssertNil(CapacityPaneReader.windows(from: reading, source: "grok", now: now))
    }

    /// Confidence alone is not enough — a confident answer with no number is
    /// still no answer.
    func testConfidentButNumberlessProducesNoWindow() throws {
        let output = """
        {"pools":[],"mostConstrainedRemaining":null,"resetAt":null,"planTier":"Max",\
        "confident":true,"reason":"tier visible, no percentages"}
        """
        let reading = try XCTUnwrap(CapacityPaneReader.extractReading(from: output))
        XCTAssertNil(CapacityPaneReader.windows(from: reading, source: "claude_code", now: now))
    }

    /// Out-of-range values are refused rather than clamped. Clamping would turn
    /// a nonsense reading into a plausible one, which is the failure mode that
    /// costs the most.
    func testImpossiblePercentagesAreRefusedNotClamped() throws {
        for value in ["-5", "140"] {
            let output = """
            {"pools":[],"mostConstrainedRemaining":\(value),"resetAt":null,\
            "planTier":null,"confident":true,"reason":"x"}
            """
            let reading = try XCTUnwrap(CapacityPaneReader.extractReading(from: output))
            XCTAssertNil(
                CapacityPaneReader.windows(from: reading, source: "kimi", now: now),
                "\(value)% must not become a window")
        }
    }

    // MARK: - Window shape

    /// Real cursor reading. The window carries the MOST CONSTRAINED pool, since
    /// that is the one that actually gates the seat — reading a real but less
    /// constrained row (Included, 57) was the only miss in the measured run.
    func testWindowUsesTheMostConstrainedPool() throws {
        let output = """
        {"pools":[{"label":"Included","remainingPercent":57},\
        {"label":"Auto","remainingPercent":58},{"label":"API","remainingPercent":52}],\
        "mostConstrainedRemaining":52,"resetAt":"2026-08-25T00:00:00Z",\
        "planTier":"Ultra","confident":true,"reason":"three pools"}
        """
        let reading = try XCTUnwrap(CapacityPaneReader.extractReading(from: output))
        let windows = try XCTUnwrap(
            CapacityPaneReader.windows(from: reading, source: "cursor_agent", now: now))
        XCTAssertEqual(windows.count, 1)
        XCTAssertEqual(windows[0].remainingPercent, 52)
        XCTAssertEqual(windows[0].usedPercent, 48)
        XCTAssertEqual(windows[0].planTier, "Ultra")
        XCTAssertNil(windows[0].unknownReason)
    }

    /// A reading with no reset time still counts — the number is the useful part
    /// — but its precision must say so rather than implying an exact boundary.
    func testMissingResetIsNotAFakeExactTime() throws {
        let output = """
        {"pools":[],"mostConstrainedRemaining":51,"resetAt":null,"planTier":null,\
        "confident":true,"reason":"weekly 49% used"}
        """
        let reading = try XCTUnwrap(CapacityPaneReader.extractReading(from: output))
        let windows = try XCTUnwrap(
            CapacityPaneReader.windows(from: reading, source: "kimi", now: now))
        XCTAssertNil(windows[0].resetAt)
        XCTAssertNotEqual(windows[0].resetPrecision, .exact)
    }

    // MARK: - Reader invocation

    /// Cheapest seat per vendor: this is telemetry, and spending a premium model
    /// to measure how much of that model is left would be self-defeating.
    func testReaderUsesTheCheapestSeatAndFailsClosedOnUnknownSources() {
        let cursor = try? XCTUnwrap(CapacityPaneReader.readerArgv(for: "cursor_agent", prompt: "P"))
        XCTAssertEqual(cursor?.contains("composer-2.5"), true)
        XCTAssertEqual(cursor?.contains("P"), true, "the prompt must reach the CLI")
        XCTAssertEqual(
            CapacityPaneReader.readerArgv(for: "claude_code", prompt: "P")?.contains("haiku"), true)
        // agy takes the prompt immediately after --print, not last.
        let agy = CapacityPaneReader.readerArgv(for: "agy", prompt: "P")
        XCTAssertEqual(agy?.firstIndex(of: "P"), 1)
        for source in CapacityProbe.probeableSources {
            XCTAssertNotNil(
                CapacityPaneReader.readerArgv(for: source, prompt: "P"),
                "\(source) is probeable, so it needs a reader invocation")
            XCTAssertNotNil(CapacityPaneReader.readerSeat(for: source))
        }
        XCTAssertNil(CapacityPaneReader.readerArgv(for: "not_a_vendor", prompt: "P"))
    }

    /// The pool rule has to survive prompt edits — it is what turned the one
    /// measured miss (57 vs 52) into an exact answer.
    func testPromptSpecifiesTheMostConstrainedPoolRule() {
        XCTAssertTrue(CapacityPaneReader.prompt.contains("LOWEST remaining"))
        XCTAssertTrue(CapacityPaneReader.prompt.contains("Do NOT guess"))
        XCTAssertTrue(CapacityPaneReader.prompt.contains("confident: false"))
    }

    // MARK: - Shadow mode: compareToParser (pure, no spawn)

    private func parsedWindow(remaining: Double, resetAt: Date? = nil) -> CapacityWindow {
        CapacityWindow(
            remaining: remaining, source: "cursor_agent", scope: .weekly,
            resetAt: resetAt, resetPrecision: .day, observedAt: now, sourceTier: .tuiProbe
        )
    }

    /// Agreement within tolerance is not logged — a file of "agreed" lines is
    /// noise, and the whole point of the log is to be reviewable.
    func testAgreementProducesNoDisagreement() {
        let reading = CapacityPaneReader.Reading(
            pools: [], mostConstrainedRemaining: 52.4, resetAt: nil, planTier: nil,
            confident: true, reason: "matches"
        )
        let result = CapacityPaneReader.compareToParser(
            parsed: [parsedWindow(remaining: 52)], reading: reading,
            source: "cursor_agent", capture: "irrelevant", now: now
        )
        XCTAssertNil(result, "within tolerance must not be logged as a disagreement")
    }

    /// Beyond tolerance, with both sides confident, is the classic case: two
    /// real numbers that disagree.
    func testValueMismatchBeyondToleranceIsLogged() throws {
        let reading = CapacityPaneReader.Reading(
            pools: [], mostConstrainedRemaining: 40, resetAt: nil, planTier: nil,
            confident: true, reason: "model saw a different pool"
        )
        let result = CapacityPaneReader.compareToParser(
            parsed: [parsedWindow(remaining: 52)], reading: reading,
            source: "cursor_agent", capture: "pane text", now: now
        )
        let disagreement = try XCTUnwrap(result)
        XCTAssertEqual(disagreement.kind, .valueMismatch)
        XCTAssertEqual(disagreement.parserRemainingPercent, 52)
        XCTAssertEqual(disagreement.modelRemainingPercent, 40)
        XCTAssertEqual(disagreement.modelConfident, true)
    }

    /// The model answering `confident: false` while the parser found a real
    /// number on the SAME text is worth flagging — it means the two disagree
    /// about whether the pane was even readable.
    func testUnconfidentModelDespiteParserSuccessIsLogged() throws {
        let reading = CapacityPaneReader.Reading(
            pools: [], mostConstrainedRemaining: nil, resetAt: nil, planTier: nil,
            confident: false, reason: "half-painted"
        )
        let result = CapacityPaneReader.compareToParser(
            parsed: [parsedWindow(remaining: 52)], reading: reading,
            source: "kimi", capture: "pane text", now: now
        )
        let disagreement = try XCTUnwrap(result)
        XCTAssertEqual(disagreement.kind, .modelUnconfident)
        XCTAssertEqual(disagreement.modelConfident, false)
    }

    /// A `nil` reading (spawn failure, timeout, unparseable output) despite a
    /// successful parse is the load-bearing case named in §6: a wrong argv
    /// is otherwise indistinguishable from an unavailable vendor. Shadow mode
    /// exists to make this one visible.
    func testNilReadingDespiteParserSuccessIsLoggedAsModelSilent() throws {
        let result = CapacityPaneReader.compareToParser(
            parsed: [parsedWindow(remaining: 52)], reading: nil,
            source: "cursor_agent", capture: "pane text", now: now
        )
        let disagreement = try XCTUnwrap(result)
        XCTAssertEqual(disagreement.kind, .modelSilent)
        XCTAssertNil(disagreement.modelConfident)
        XCTAssertNil(disagreement.modelRemainingPercent)
        XCTAssertEqual(disagreement.parserRemainingPercent, 52)
    }

    /// The excerpt is bounded — a reviewable log, not an unbounded dump of
    /// full session content.
    func testCaptureExcerptIsTruncated() throws {
        let huge = String(repeating: "x", count: 20_000)
        let result = CapacityPaneReader.compareToParser(
            parsed: [parsedWindow(remaining: 52)], reading: nil,
            source: "cursor_agent", capture: huge, now: now
        )
        let disagreement = try XCTUnwrap(result)
        XCTAssertLessThan(disagreement.captureExcerpt.count, huge.count)
        XCTAssertEqual(disagreement.captureExcerpt.count, CapacityPaneReader.captureExcerptLimit)
    }

    // MARK: - Shadow mode: runShadowComparison (real spawn, fixture "vendor CLI")

    #if os(macOS)

    private func writeScript(_ body: String, name: String) throws -> String {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("alln-shadow-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let script = dir.appendingPathComponent(name)
        try body.write(to: script, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: script.path)
        return script.path
    }

    /// End-to-end agreement: the fixture "vendor CLI" answers with the SAME
    /// number the parser already has — no disagreement is produced.
    func testRunShadowComparisonReturnsNilOnRealAgreement() throws {
        let script = try writeScript("""
        #!/bin/sh
        printf '%s' '{"pools":[],"mostConstrainedRemaining":52,"resetAt":null,"planTier":null,"confident":true,"reason":"ok"}'
        """, name: "fake-agree.sh")
        let result = CapacityPaneReader.runShadowComparison(
            source: "cursor_agent", capture: "pane", executable: script,
            parsed: [parsedWindow(remaining: 52)], timeout: 5, now: now
        )
        XCTAssertNil(result)
    }

    /// End-to-end mismatch through a real spawn — proves extraction,
    /// comparison, and classification all compose, not just the pure pieces.
    func testRunShadowComparisonReturnsValueMismatchOnRealDisagreement() throws {
        let script = try writeScript("""
        #!/bin/sh
        printf '%s' '{"pools":[],"mostConstrainedRemaining":9,"resetAt":null,"planTier":null,"confident":true,"reason":"different pool"}'
        """, name: "fake-disagree.sh")
        let result = CapacityPaneReader.runShadowComparison(
            source: "cursor_agent", capture: "pane", executable: script,
            parsed: [parsedWindow(remaining: 52)], timeout: 5, now: now
        )
        let disagreement = try XCTUnwrap(result)
        XCTAssertEqual(disagreement.kind, .valueMismatch)
        XCTAssertEqual(disagreement.modelRemainingPercent, 9)
    }

    /// **The load-bearing regression.** This exact failure shape — a real
    /// process, a nonzero exit, nothing extractable — is what a mistyped
    /// argv looks like (cursor's flag is `--model`, not `-m`; landmine §6).
    /// Shadow mode's whole reason to exist is making this loggable instead of
    /// silently indistinguishable from "vendor logged out".
    func testRunShadowComparisonLogsModelSilentOnNonZeroExit() throws {
        let script = try writeScript("""
        #!/bin/sh
        exit 1
        """, name: "fake-fail.sh")
        let result = CapacityPaneReader.runShadowComparison(
            source: "cursor_agent", capture: "pane", executable: script,
            parsed: [parsedWindow(remaining: 52)], timeout: 5, now: now
        )
        let disagreement = try XCTUnwrap(result)
        XCTAssertEqual(disagreement.kind, .modelSilent)
    }

    /// Missing binary — the ordinary "vendor CLI not installed" shape — must
    /// still fail closed to a logged `modelSilent`, never a crash or hang.
    func testRunShadowComparisonHandlesMissingBinary() throws {
        let result = CapacityPaneReader.runShadowComparison(
            source: "cursor_agent", capture: "pane",
            executable: "/tmp/alln-shadow-missing-\(UUID().uuidString)",
            parsed: [parsedWindow(remaining: 52)], timeout: 5, now: now
        )
        let disagreement = try XCTUnwrap(result)
        XCTAssertEqual(disagreement.kind, .modelSilent)
    }

    // MARK: - Shadow diagnostic (stdout)

    func testStdoutWritesDecodableJSONLinesInOrder() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("alln-shadow-stdout-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent("stdout.txt")
        FileManager.default.createFile(atPath: url.path, contents: nil)
        let handle = try FileHandle(forWritingTo: url)
        defer { try? handle.close() }

        let first = CapacityPaneReader.Disagreement(
            source: "cursor_agent", observedAt: now, kind: .valueMismatch,
            parserRemainingPercent: 52, parserResetAt: nil, modelRemainingPercent: 9,
            modelConfident: true, modelReason: "r1", captureExcerpt: "one"
        )
        let second = CapacityPaneReader.Disagreement(
            source: "kimi", observedAt: now.addingTimeInterval(60), kind: .modelSilent,
            parserRemainingPercent: 30, parserResetAt: nil, modelRemainingPercent: nil,
            modelConfident: nil, modelReason: nil, captureExcerpt: "two"
        )
        CapacityPaneReader.writeDisagreementToStdout(first, handle: handle)
        CapacityPaneReader.writeDisagreementToStdout(second, handle: handle)
        try handle.synchronize()

        let contents = try String(contentsOf: url, encoding: .utf8)
        let lines = contents.split(separator: "\n", omittingEmptySubsequences: true)
        XCTAssertEqual(lines.count, 2)

        let prefix = "capacity: shadow-pane-reader disagreement "
        XCTAssertTrue(lines[0].hasPrefix(prefix))
        XCTAssertTrue(lines[1].hasPrefix(prefix))

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decodedFirst = try decoder.decode(
            CapacityPaneReader.Disagreement.self,
            from: Data(lines[0].dropFirst(prefix.count).utf8)
        )
        let decodedSecond = try decoder.decode(
            CapacityPaneReader.Disagreement.self,
            from: Data(lines[1].dropFirst(prefix.count).utf8)
        )
        XCTAssertEqual(decodedFirst, first)
        XCTAssertEqual(decodedSecond, second)
    }

    /// Production diagnostic must not create a persisted ledger. The unread
    /// Application Support JSONL sink is gone; stdout is the only output.
    func testStdoutSinkDoesNotWritePersistedLedger() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("alln-shadow-sink-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let ledger = dir.appendingPathComponent("disagreements.jsonl")
        let stdoutURL = dir.appendingPathComponent("stdout.txt")
        FileManager.default.createFile(atPath: stdoutURL.path, contents: nil)
        let handle = try FileHandle(forWritingTo: stdoutURL)
        defer { try? handle.close() }

        CapacityPaneReader.writeDisagreementToStdout(
            CapacityPaneReader.Disagreement(
                source: "cursor_agent", observedAt: now, kind: .modelSilent,
                parserRemainingPercent: 52, parserResetAt: nil, modelRemainingPercent: nil,
                modelConfident: nil, modelReason: nil, captureExcerpt: "x"
            ),
            handle: handle
        )

        XCTAssertFalse(
            FileManager.default.fileExists(atPath: ledger.path),
            "shadow diagnostic must not write a disagreements.jsonl ledger"
        )
        let text = try String(contentsOf: stdoutURL, encoding: .utf8)
        XCTAssertTrue(text.contains("shadow-pane-reader disagreement"))
        XCTAssertTrue(text.contains("cursor_agent"))
    }

    #endif
}
