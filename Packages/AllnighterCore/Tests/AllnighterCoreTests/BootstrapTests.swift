import XCTest
@testable import AllnighterCore

/// `alln bootstrap` — the activation surface that replaced `alln mcp install`
/// (docs/phases/MCP_Retirement.md §Activation). Assertions target the
/// load-bearing lines (paste target per host, the five taught behaviors, the
/// JSON envelope shape) rather than pinning the full snippet byte-for-byte, so
/// prose tightening doesn't make this brittle.
final class BootstrapTests: XCTestCase {
    private let sampleBinary = "/tmp/allnighter-build/alln"

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
        let generic = Bootstrap.Host.generic.pasteTarget
        for needle in ["CLAUDE.md", ".cursor/rules", "AGENTS.md"] {
            XCTAssertTrue(generic.contains(needle), "generic paste target missing \(needle)")
        }
    }

    // MARK: - The snippet teaches the trusted workflow (founder mandate, one per line)

    func testSnippetTeachesTheTrustedWorkflowOnPath() {
        let s = Bootstrap.snippet(binaryPath: sampleBinary, onPath: true)
        XCTAssertTrue(s.contains("`alln` CLI"), "must name the CLI surface")
        XCTAssertTrue(s.contains("fallback: `\(sampleBinary)`"), "must carry binary fallback")
        XCTAssertTrue(s.contains("alln team hello --json"), "must teach quota-free discovery")
        XCTAssertTrue(s.contains("alln help search"), "must teach help search")
        XCTAssertTrue(s.contains("alln help get"), "must teach help get")
        XCTAssertTrue(s.contains("--json"), "must steer toward structured envelopes")
        XCTAssertTrue(s.contains("alln doctor --json"), "must route environment failures to doctor")
        XCTAssertTrue(s.lowercased().contains("never guess flags"), "must forbid guessing flags")
    }

    func testSnippetIncludesInstallStepWhenNotOnPath() {
        let s = Bootstrap.snippet(binaryPath: sampleBinary, onPath: false)
        XCTAssertTrue(s.contains("\(sampleBinary) install-cli"))
        XCTAssertTrue(s.contains("plain `alln` works everywhere"))
    }

    /// Budget-consciousness is the whole point vs. MCP's always-loaded tool
    /// schemas — keep the snippet within the founder ≤15-line budget.
    func testSnippetStaysWithinLineBudget() {
        let onPathLines = Bootstrap.snippet(binaryPath: sampleBinary, onPath: true)
            .split(separator: "\n", omittingEmptySubsequences: false)
        XCTAssertGreaterThanOrEqual(onPathLines.count, 10)
        XCTAssertLessThanOrEqual(onPathLines.count, 15, "on-path snippet grew past budget")

        let offPathLines = Bootstrap.snippet(binaryPath: sampleBinary, onPath: false)
            .split(separator: "\n", omittingEmptySubsequences: false)
        XCTAssertLessThanOrEqual(offPathLines.count, 15, "off-path snippet grew past budget")
    }

    func testSnippetIncludesPanelRecipeEndingWithPilotChain() {
        let s = Bootstrap.snippet(binaryPath: sampleBinary, onPath: true)
        XCTAssertTrue(s.contains("panel start"))
        XCTAssertTrue(s.contains("panel round"))
        XCTAssertTrue(s.contains("panel done"))
        XCTAssertTrue(s.contains("pair pilot start --doc <same>"), "panel recipe must end with pilot chain")
        XCTAssertTrue(s.contains("pair pilot handoff"))
        XCTAssertTrue(s.contains("help get panel") || s.contains("pm_relay"))
    }

    func testSnippetIsSharedSSOTWithHelpService() {
        XCTAssertEqual(Bootstrap.snippet(binaryPath: "alln", onPath: true), HelpService.hostInstructionBlock)
    }

    // MARK: - Render (non-JSON path)

    func testRenderIncludesPasteTargetAndSnippetVerbatim() {
        let out = Bootstrap.render(host: .claude, binaryPath: sampleBinary, onPath: true)
        XCTAssertTrue(out.contains(Bootstrap.Host.claude.pasteTarget))
        XCTAssertTrue(out.contains(Bootstrap.snippet(binaryPath: sampleBinary, onPath: true)))
    }

    // MARK: - JSON envelope shape (agent-first: an agent can install itself)

    func testJSONEnvelopeShape() {
        let j = Bootstrap.json(host: .cursor, binaryPath: sampleBinary, onPath: false)
        XCTAssertEqual(j.schemaVersion, 1)
        XCTAssertEqual(j.host, "cursor")
        XCTAssertEqual(j.pasteTarget, Bootstrap.Host.cursor.pasteTarget)
        XCTAssertEqual(j.binaryPath, sampleBinary)
        XCTAssertFalse(j.onPath)
        XCTAssertTrue(j.snippet.contains(sampleBinary))
    }

    func testJSONStringRoundTrips() throws {
        let json = Bootstrap.jsonString(host: .codex, binaryPath: sampleBinary, onPath: true)
        let decoded = try CoreJSON.decode(Bootstrap.JSON.self, from: Data(json.utf8))
        XCTAssertEqual(decoded, Bootstrap.json(host: .codex, binaryPath: sampleBinary, onPath: true))
    }

    func testEveryHostProducesDistinctJSON() {
        let all = Bootstrap.Host.allCases.map { Bootstrap.json(host: $0, binaryPath: sampleBinary, onPath: true) }
        XCTAssertEqual(Set(all.map(\.host)).count, Bootstrap.Host.allCases.count)
        XCTAssertEqual(Set(all.map(\.snippet)).count, 1)
        XCTAssertTrue(all.allSatisfy { $0.binaryPath == sampleBinary })
    }

    // MARK: - Never edits files (consent posture parity with the retired MCP install)

    func testBootstrapNeverTouchesTheFilesystem() {
        let a = Bootstrap.render(host: .generic, binaryPath: sampleBinary, onPath: true)
        let b = Bootstrap.render(host: .generic, binaryPath: sampleBinary, onPath: true)
        XCTAssertEqual(a, b)
    }
}
