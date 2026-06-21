import XCTest
@testable import AllnighterCore

/// CONT-S1b: extracting a worker CLI's session id from its first-run output.
final class WorkerSessionCaptureTests: XCTestCase {

    func testStreamJsonTopLevelField() {
        let jsonl = """
        {"type":"system","subtype":"init","session_id":"sess-abc-123","model":"opus"}
        {"type":"assistant","message":"hi"}
        """
        let cap = DriverManifest.Session.Capture(from: .streamJson, field: "session_id")
        XCTAssertEqual(WorkerSessionCapture.extract(capture: cap, stdout: jsonl), "sess-abc-123")
    }

    func testStreamJsonNestedField() {
        let jsonl = #"{"type":"start","session":{"id":"nested-9"}}"#
        let cap = DriverManifest.Session.Capture(from: .streamJson, field: "id")
        XCTAssertEqual(WorkerSessionCapture.extract(capture: cap, stdout: jsonl), "nested-9")
    }

    func testStreamJsonTakesFirstOccurrence() {
        let jsonl = """
        {"session_id":"first"}
        {"session_id":"second"}
        """
        let cap = DriverManifest.Session.Capture(from: .streamJson, field: "session_id")
        XCTAssertEqual(WorkerSessionCapture.extract(capture: cap, stdout: jsonl), "first")
    }

    func testStdoutRegexGroup() {
        let stdout = "Created chat\nsession id: 7f3a-bc01\nready"
        let cap = DriverManifest.Session.Capture(from: .stdout, field: #"session id: ([0-9a-f-]+)"#)
        XCTAssertEqual(WorkerSessionCapture.extract(capture: cap, stdout: stdout), "7f3a-bc01")
    }

    func testOutputFileJsonField() {
        let cap = DriverManifest.Session.Capture(from: .outputFile, field: "conversation_id")
        XCTAssertEqual(
            WorkerSessionCapture.extract(capture: cap, stdout: "", outputFileContents: #"{"conversation_id":"cx-42"}"#),
            "cx-42")
    }

    func testNoMatchReturnsNil() {
        let cap = DriverManifest.Session.Capture(from: .streamJson, field: "session_id")
        XCTAssertNil(WorkerSessionCapture.extract(capture: cap, stdout: #"{"type":"assistant"}"#))
        XCTAssertNil(WorkerSessionCapture.extract(capture: cap, stdout: "not json at all"))
    }

    func testEmptyValueIsNotAccepted() {
        let cap = DriverManifest.Session.Capture(from: .streamJson, field: "session_id")
        XCTAssertNil(WorkerSessionCapture.extract(capture: cap, stdout: #"{"session_id":""}"#))
    }

    func testSessionDirHasNoStringField() {
        // agy mints a folder, not an output field — string extraction yields nothing.
        let cap = DriverManifest.Session.Capture(from: .sessionDir, dir: "~/.gemini/antigravity-cli/brain")
        XCTAssertNil(WorkerSessionCapture.extract(capture: cap, stdout: "OK"))
    }

    // CONT-S6: `session_dir` capture identifies the ONE conversation folder agy minted this turn.
    func testCapturedDirEntryReturnsTheSingleNewFolder() {
        let before: Set<String> = ["a", "b", "c"]
        let after: Set<String> = ["a", "b", "c", "359ae744"]
        XCTAssertEqual(WorkerSessionCapture.capturedDirEntry(before: before, after: after), "359ae744")
    }

    func testCapturedDirEntryNilWhenNothingMinted() {
        let s: Set<String> = ["a", "b"]
        XCTAssertNil(WorkerSessionCapture.capturedDirEntry(before: s, after: s))
    }

    func testCapturedDirEntryNilWhenAmbiguous() {
        // Two folders appeared (a concurrent agy run) — refuse to guess; degrade to context-only.
        let before: Set<String> = ["a"]
        let after: Set<String> = ["a", "x", "y"]
        XCTAssertNil(WorkerSessionCapture.capturedDirEntry(before: before, after: after))
    }
}
