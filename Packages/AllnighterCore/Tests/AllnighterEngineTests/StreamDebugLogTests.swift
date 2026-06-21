import XCTest
@testable import AllnighterEngine

/// RLS-S02: raw stream debug logging must be OFF by default — it used to do thousands of
/// synchronous file writes per run on the stream hot path while recording sensitive text.
/// Enabling is an explicit per-run opt-in.
final class StreamDebugLogTests: XCTestCase {

    func testDisabledByDefaultAndForAnythingButOptIn() {
        XCTAssertFalse(StreamDebugLog.enabled(envValue: nil), "unset → off (default)")
        XCTAssertFalse(StreamDebugLog.enabled(envValue: "0"), "0 → off")
        XCTAssertFalse(StreamDebugLog.enabled(envValue: "true"), "only the explicit \"1\" enables")
        XCTAssertFalse(StreamDebugLog.enabled(envValue: ""), "empty → off")
    }

    func testEnabledOnlyByExplicitOptIn() {
        XCTAssertTrue(StreamDebugLog.enabled(envValue: "1"))
    }

    func testClipTruncatesLongPayloadsWithCount() {
        XCTAssertEqual(StreamDebugLog.clip("short", 10), "short")
        let long = String(repeating: "x", count: 100)
        let clipped = StreamDebugLog.clip(long, 10)
        XCTAssertTrue(clipped.hasPrefix(String(repeating: "x", count: 10)))
        XCTAssertTrue(clipped.contains("+90 chars"))
    }

    func testDisabledLogDoesNotEvaluateItsMessage() throws {
        // The @autoclosure must NOT run when logging is off, so per-event work (decoding,
        // describe(), clip()) is never paid on the hot path in a default run.
        // (This test process does not opt in, so isEnabled is false.)
        guard !StreamDebugLog.isEnabled else {
            throw XCTSkip("ALLNIGHTER_STREAM_DEBUG=1 in this environment; skipping no-eval check")
        }
        var evaluated = false
        StreamDebugLog.log({ evaluated = true; return "expensive message" }())
        XCTAssertFalse(evaluated, "a disabled log must not build its message")
    }
}
