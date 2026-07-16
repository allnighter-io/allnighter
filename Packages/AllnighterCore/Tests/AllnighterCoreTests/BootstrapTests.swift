import XCTest
@testable import AllnighterCore

/// `alln bootstrap` — the activation surface that replaced `alln mcp install`
/// (docs/phases/MCP_Retirement.md §Activation). Assertions target the
/// load-bearing lines (paste target per host, the five taught behaviors, the
/// JSON envelope shape) rather than pinning the full snippet byte-for-byte, so
/// prose tightening doesn't make this brittle.
final class BootstrapTests: XCTestCase {
    // MARK: - Host resolution

    func testHostArgumentParsingIsCaseInsensitive() {
        XCTAssertEqual(Bootstrap.Host(argument: "claude"), .claude)
        XCTAssertEqual(Bootstrap.Host(argument: "Claude"), .claude)
        XCTAssertEqual(Bootstrap.Host(argument: "CURSOR"), .cursor)
        XCTAssertEqual(Bootstrap.Host(argument: "codex"), .codex)
        XCTAssertEqual(Bootstrap.Host(argument: "generic"), .generic)
        XCTAssertNil(Bootstrap.Host(argument: "bogus"))
    }

    // MARK: - Paste target per host

    func testPasteTargetNamesTheRightFilePerHost() {
        XCTAssertTrue(Bootstrap.Host.claude.pasteTarget.contains("CLAUDE.md"))
        XCTAssertTrue(Bootstrap.Host.cursor.pasteTarget.contains(".cursor/rules"))
        XCTAssertTrue(Bootstrap.Host.codex.pasteTarget.contains("AGENTS.md"))
        // The host-neutral target names all three common locations.
        let generic = Bootstrap.Host.generic.pasteTarget
        for needle in ["CLAUDE.md", ".cursor/rules", "AGENTS.md"] {
            XCTAssertTrue(generic.contains(needle), "generic paste target missing \(needle)")
        }
    }

    // MARK: - The snippet teaches the trusted workflow (founder mandate, one per line)

    func testSnippetTeachesTheTrustedWorkflow() {
        let s = Bootstrap.snippet
        XCTAssertTrue(s.contains("`alln` CLI"), "must name the CLI surface")
        XCTAssertTrue(s.contains("alln team hello --json"), "must teach quota-free discovery")
        XCTAssertTrue(s.contains("alln help search"), "must teach help search")
        XCTAssertTrue(s.contains("alln help get"), "must teach help get")
        XCTAssertTrue(s.contains("--json"), "must steer toward structured envelopes")
        XCTAssertTrue(s.contains("alln doctor --json"), "must route environment failures to doctor")
        XCTAssertTrue(s.lowercased().contains("never guess flags"), "must forbid guessing flags")
    }

    /// Budget-consciousness is the whole point vs. MCP's always-loaded tool
    /// schemas — keep the snippet in the ~6-8 line range the founder specified.
    func testSnippetStaysWithinLineBudget() {
        let lines = Bootstrap.snippet.split(separator: "\n", omittingEmptySubsequences: false)
        XCTAssertGreaterThanOrEqual(lines.count, 4)
        XCTAssertLessThanOrEqual(lines.count, 8, "snippet grew past the paste-ready budget")
    }

    func testSnippetIsSharedSSOTWithHelpService() {
        XCTAssertEqual(Bootstrap.snippet, HelpService.hostInstructionBlock)
    }

    // MARK: - Render (non-JSON path)

    func testRenderIncludesPasteTargetAndSnippetVerbatim() {
        let out = Bootstrap.render(host: .claude)
        XCTAssertTrue(out.contains(Bootstrap.Host.claude.pasteTarget))
        XCTAssertTrue(out.contains(Bootstrap.snippet))
    }

    // MARK: - JSON envelope shape (agent-first: an agent can install itself)

    func testJSONEnvelopeShape() {
        let j = Bootstrap.json(host: .cursor)
        XCTAssertEqual(j.schemaVersion, 1)
        XCTAssertEqual(j.host, "cursor")
        XCTAssertEqual(j.pasteTarget, Bootstrap.Host.cursor.pasteTarget)
        XCTAssertEqual(j.snippet, Bootstrap.snippet)
    }

    func testJSONStringRoundTrips() throws {
        let json = Bootstrap.jsonString(host: .codex)
        let decoded = try CoreJSON.decode(Bootstrap.JSON.self, from: Data(json.utf8))
        XCTAssertEqual(decoded, Bootstrap.json(host: .codex))
    }

    func testEveryHostProducesDistinctJSON() {
        let all = Bootstrap.Host.allCases.map(Bootstrap.json(host:))
        XCTAssertEqual(Set(all.map(\.host)).count, Bootstrap.Host.allCases.count)
        // Every host shares the identical snippet — it's the paste target that differs.
        XCTAssertEqual(Set(all.map(\.snippet)).count, 1)
    }

    // MARK: - Never edits files (consent posture parity with the retired MCP install)

    func testBootstrapNeverTouchesTheFilesystem() {
        // Pure string builders — no FileManager import in this file is the
        // structural guarantee; this test pins the observable behavior:
        // repeated calls are side-effect free and deterministic.
        let a = Bootstrap.render(host: .generic)
        let b = Bootstrap.render(host: .generic)
        XCTAssertEqual(a, b)
    }
}
