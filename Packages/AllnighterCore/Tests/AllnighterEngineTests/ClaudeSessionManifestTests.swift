import XCTest
@testable import AllnighterCore
@testable import AllnighterEngine

/// CONT-S2: the shipped claude_code manifest declares vendor-session continuity, and its
/// resume/first-turn args resolve to the form proven to recall live
/// (`--session-id <uuid>` turn 1 → `--resume <uuid>` later, never `--continue`).
final class ClaudeSessionManifestTests: XCTestCase {

    private func claudeManifest() throws -> DriverManifest {
        try XCTUnwrap(DefaultConfig.manifests.first { $0.id == "claude_code" })
    }

    func testClaudeDeclaresVendorSessionSet() throws {
        let s = try XCTUnwrap(try claudeManifest().session)
        XCTAssertEqual(s.continuity, .vendorSession)
        XCTAssertEqual(s.acquire, .set, "we mint the session id and assign it via --session-id")
    }

    func testClaudeResumeArgsCarryStoredIdNotContinue() throws {
        let ctx = DriverManifest.ResolveContext(prompt: "turn 2", model: "claude-sonnet-4-6", resumeSessionId: "sess-7")
        let args = try XCTUnwrap(claudeManifest().resolvedSessionArgs(ctx, resuming: true))
        XCTAssertTrue(args.contains("--resume"))
        XCTAssertTrue(args.contains("sess-7"))
        XCTAssertFalse(args.contains("--continue"))
        XCTAssertTrue(args.contains("turn 2"), "prompt stays one argv element")
    }

    func testClaudeFirstTurnMintsSessionId() throws {
        let ctx = DriverManifest.ResolveContext(prompt: "turn 1", model: "claude-sonnet-4-6", resumeSessionId: "mint-9")
        let args = try XCTUnwrap(claudeManifest().resolvedSessionArgs(ctx, resuming: false))
        XCTAssertTrue(args.contains("--session-id"))
        XCTAssertTrue(args.contains("mint-9"))
        XCTAssertFalse(args.contains("--resume"))
    }
}
