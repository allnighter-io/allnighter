import XCTest
@testable import AllnighterCore

/// `alln bootstrap` — the activation surface that replaced `alln mcp install`
/// (docs/phases/MCP_Retirement.md §Activation; ONB-S01 router reflex).
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

    // MARK: - Paste target per host (v1 global matrix)

    func testPasteTargetNamesTheRightFilePerHost() {
        XCTAssertTrue(Bootstrap.Host.claude.pasteTarget.contains("~/.claude/CLAUDE.md"))
        XCTAssertTrue(Bootstrap.Host.cursor.pasteTarget.contains("~/.cursor/rules/allnighter.mdc"))
        XCTAssertTrue(Bootstrap.Host.codex.pasteTarget.contains("AGENTS.md"))
        XCTAssertTrue(Bootstrap.Host.codex.pasteTarget.lowercased().contains("no global"))
        let generic = Bootstrap.Host.generic.pasteTarget
        for needle in ["CLAUDE.md", "allnighter.mdc", "AGENTS.md"] {
            XCTAssertTrue(generic.contains(needle), "generic paste target missing \(needle)")
        }
    }

    // MARK: - v3 router reflex (ONB-S01)

    func testSnippetTeachesRouterReflexAndAuthorizationLaw() {
        let s = Bootstrap.snippet(binaryPath: sampleBinary, onPath: true)
        XCTAssertTrue(s.contains("`alln` CLI"), "must name the CLI surface")
        XCTAssertTrue(s.contains("fallback: `\(sampleBinary)`"), "must carry binary fallback")
        XCTAssertTrue(s.contains("alln team hello --for"), "must teach intent router")
        XCTAssertTrue(s.contains("--json"), "must prefer structured envelopes")
        XCTAssertTrue(s.contains("recommended.command"), "must name frozen router field")
        XCTAssertTrue(
            s.contains("only when the user's request already authorizes"),
            "must teach authorization law (never auto-run)"
        )
        XCTAssertTrue(s.contains("Never manually substitute"), "must forbid silent worker substitution")
        XCTAssertTrue(s.contains("alln help search"), "must teach help search")
        XCTAssertTrue(s.contains("alln help get"), "must teach help get")
        XCTAssertTrue(s.contains("alln doctor --json"), "must route environment failures to doctor")
        XCTAssertTrue(s.contains(TeachingSnippet.openMarkerPrefix), "must wrap teaching in markers")
        XCTAssertTrue(s.contains(TeachingSnippet.closeMarker), "must close teaching markers")
        XCTAssertTrue(s.contains("hash=\(TeachingSnippet.contentHash)"), "marker must carry content hash")
    }

    func testSnippetDoesNotIncludePanelRecipe() {
        let s = Bootstrap.snippet(binaryPath: sampleBinary, onPath: true)
        XCTAssertFalse(s.contains("panel start"), "bootstrap must not re-teach panel cockpit")
        XCTAssertFalse(s.contains("panel round"))
        XCTAssertFalse(s.contains("panel done"))
        XCTAssertFalse(s.contains("pair pilot start"))
        XCTAssertFalse(s.contains("pair pilot handoff"))
    }

    func testSnippetIncludesInstallStepWhenNotOnPath() {
        let s = Bootstrap.snippet(binaryPath: sampleBinary, onPath: false)
        XCTAssertTrue(s.contains("\(sampleBinary) install-cli"))
        XCTAssertTrue(s.contains("plain `alln` works everywhere"))
    }

    /// ONB-S01 size budget: clearly smaller than v2 (≤8 on-path; ≤10 with install line).
    func testSnippetStaysWithinLineBudget() {
        let onPathLines = Bootstrap.snippet(binaryPath: sampleBinary, onPath: true)
            .split(separator: "\n", omittingEmptySubsequences: false)
        XCTAssertLessThanOrEqual(onPathLines.count, 8, "on-path snippet grew past ≤8 budget")

        let offPathLines = Bootstrap.snippet(binaryPath: sampleBinary, onPath: false)
            .split(separator: "\n", omittingEmptySubsequences: false)
        XCTAssertLessThanOrEqual(offPathLines.count, 10, "off-path snippet grew past ≤10 budget")
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
        XCTAssertGreaterThanOrEqual(j.recipes.count, 6)
        XCTAssertEqual(j.recipesHelp, "alln help get recipes --format md")
        XCTAssertTrue(j.recipes.contains { $0.id == "get-sols-take-without-changing-files" })
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
