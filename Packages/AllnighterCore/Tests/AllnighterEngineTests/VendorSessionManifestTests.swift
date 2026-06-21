import XCTest
@testable import AllnighterCore
@testable import AllnighterEngine

/// CONT-S3+: every shipped driver that declares `vendor_session` continuity must resume by
/// the STORED id and never the global `--continue`. Auto-covers each CLI as it's added.
final class VendorSessionManifestTests: XCTestCase {

    private var vendorManifests: [DriverManifest] {
        DefaultConfig.manifests.filter { $0.session?.continuity == .vendorSession }
    }

    func testThereAreVendorSessionDrivers() {
        let ids = Set(vendorManifests.map(\.id))
        XCTAssertTrue(ids.isSuperset(of: ["claude_code", "cursor_agent", "codex", "grok"]),
                      "all four resume-capable CLIs declare vendor_session; got \(ids)")
    }

    func testPerCliCaptureFieldsMatchLiveProof() throws {
        func capture(_ id: String) throws -> String {
            try XCTUnwrap(vendorManifests.first { $0.id == id }?.session?.capture?.field)
        }
        XCTAssertEqual(try capture("cursor_agent"), "session_id")
        XCTAssertEqual(try capture("codex"), "thread_id")
        XCTAssertEqual(try capture("grok"), "sessionId")
    }

    func testCodexResumeReshapesToExecResume() throws {
        let codex = try XCTUnwrap(vendorManifests.first { $0.id == "codex" })
        let ctx = DriverManifest.ResolveContext(prompt: "p2", model: "gpt", outputFile: "/tmp/o.txt", resumeSessionId: "th-1")
        let args = try XCTUnwrap(codex.resolvedSessionArgs(ctx, resuming: true))
        XCTAssertEqual(Array(args.prefix(3)), ["exec", "resume", "th-1"], "codex reshapes to `exec resume <id>`")
        XCTAssertFalse(args.contains("--color"), "codex resume must not pass --color (it rejects it)")
    }

    func testAntigravityIsPromptContextOnly() throws {
        let agy = try XCTUnwrap(DefaultConfig.manifests.first { $0.id == "antigravity" })
        XCTAssertEqual(agy.session?.continuity, .promptContextOnly, "no headless id → honest context fallback")
    }

    func testEveryVendorSessionResumesByStoredIdNeverContinue() {
        for m in vendorManifests {
            let ctx = DriverManifest.ResolveContext(prompt: "the prompt", model: "mdl", resumeSessionId: "stored-xyz")
            let args = m.resolvedSessionArgs(ctx, resuming: true)
            XCTAssertNotNil(args, "\(m.id): vendor_session but no resolvable resumeArgs")
            XCTAssertTrue(args!.contains("stored-xyz"), "\(m.id): resume must carry the stored id")
            XCTAssertFalse(args!.contains("--continue"), "\(m.id): must NEVER use global --continue")
            XCTAssertTrue(args!.contains("the prompt"), "\(m.id): prompt stays one argv element")
        }
    }

    func testCaptureDriversDeclareAField() {
        for m in vendorManifests where m.session?.acquire == .capture {
            XCTAssertNotNil(m.session?.capture?.field, "\(m.id): acquire=capture needs a capture field")
        }
    }

    func testCursorIsCaptureOnSessionId() throws {
        let cursor = try XCTUnwrap(vendorManifests.first { $0.id == "cursor_agent" })
        XCTAssertEqual(cursor.session?.acquire, .capture)
        XCTAssertEqual(cursor.session?.capture?.field, "session_id")
    }
}
