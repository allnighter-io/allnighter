import XCTest
@testable import AllnighterCore

/// CONT-S0: the manifest `session` block decodes (additive; absent ⇒ no continuity).
final class DriverManifestSessionTests: XCTestCase {

    func testSessionBlockDecodes_setAcquire() throws {
        let json = """
        {
          "id": "claude_code", "manifestVersion": 1, "displayName": "Claude Code", "kind": "headless_cli",
          "session": {
            "continuity": "vendor_session",
            "acquire": "set",
            "firstTurnArgs": ["-p","{{prompt}}","--session-id","{{sessionId}}"],
            "resumeArgs": ["-p","{{prompt}}","--resume","{{sessionId}}"]
          }
        }
        """.data(using: .utf8)!
        let m = try JSONDecoder().decode(DriverManifest.self, from: json)
        let s = try XCTUnwrap(m.session)
        XCTAssertEqual(s.continuity, .vendorSession)
        XCTAssertEqual(s.acquire, .set)
        XCTAssertEqual(s.resumeArgs, ["-p", "{{prompt}}", "--resume", "{{sessionId}}"])
    }

    func testSessionBlockDecodes_captureFromStreamJson() throws {
        let json = """
        {
          "id": "grok", "manifestVersion": 1, "displayName": "Grok", "kind": "headless_cli",
          "session": {
            "continuity": "vendor_session", "acquire": "capture",
            "resumeArgs": ["-p","{{prompt}}","--resume","{{sessionId}}"],
            "capture": { "from": "stream_json", "field": "session_id" }
          }
        }
        """.data(using: .utf8)!
        let s = try XCTUnwrap(try JSONDecoder().decode(DriverManifest.self, from: json).session)
        XCTAssertEqual(s.acquire, .capture)
        XCTAssertEqual(s.capture?.from, .streamJson)
        XCTAssertEqual(s.capture?.field, "session_id")
    }

    func testAbsentSessionBlockIsNil() throws {
        let json = """
        { "id": "x", "manifestVersion": 1, "displayName": "X", "kind": "headless_cli" }
        """.data(using: .utf8)!
        XCTAssertNil(try JSONDecoder().decode(DriverManifest.self, from: json).session,
                     "no session block ⇒ no vendor-session continuity")
    }

    func testPromptContextOnlyTier() throws {
        let json = """
        { "id": "agy", "manifestVersion": 1, "displayName": "Antigravity", "kind": "headless_cli",
          "session": { "continuity": "prompt_context_only" } }
        """.data(using: .utf8)!
        XCTAssertEqual(try JSONDecoder().decode(DriverManifest.self, from: json).session?.continuity,
                       .promptContextOnly)
    }
}
