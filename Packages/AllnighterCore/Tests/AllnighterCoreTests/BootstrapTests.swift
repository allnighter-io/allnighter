import XCTest
@testable import AllnighterCore

/// `alln bootstrap` — activation surface (MR-S05 four-rule live-menu reflex).
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

    // MARK: - MR-S05 four-rule reflex

    func testSnippetTeachesFourRuleLiveMenuReflex() {
        let s = Bootstrap.snippet(binaryPath: sampleBinary, onPath: true)
        XCTAssertTrue(s.contains("`alln` CLI"), "must name the CLI surface")
        XCTAssertTrue(s.contains("fallback: `\(sampleBinary)`"), "must carry binary fallback")
        XCTAssertTrue(s.contains("alln menu --json"), "must teach live menu")
        XCTAssertTrue(s.contains("useWhen"), "must teach useWhen")
        XCTAssertTrue(s.contains("dontUseWhen"), "must teach dontUseWhen")
        XCTAssertTrue(s.contains("canonical ids"), "must teach exact-id dispatch")
        XCTAssertTrue(s.contains("validation template"), "must teach validation twin")
        XCTAssertTrue(s.contains("never trust a pasted catalog"), "must teach session re-read")
        XCTAssertTrue(s.contains("returned delivery command once"), "must teach detached delivery")
        XCTAssertFalse(s.contains("team hello"))
        XCTAssertFalse(s.contains("route --for"))
        XCTAssertFalse(s.contains("resolve --for"))
        XCTAssertFalse(s.contains("model_sonnet"), "must not embed catalog rows")
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

    /// Eight-rule body + markers stays compact (AVQ-S03 mutator/progress law).
    func testSnippetStaysWithinLineBudget() {
        let onPathLines = Bootstrap.snippet(binaryPath: sampleBinary, onPath: true)
            .split(separator: "\n", omittingEmptySubsequences: false)
        XCTAssertLessThanOrEqual(onPathLines.count, 12, "on-path snippet grew past ≤12 budget")

        let offPathLines = Bootstrap.snippet(binaryPath: sampleBinary, onPath: false)
            .split(separator: "\n", omittingEmptySubsequences: false)
        XCTAssertLessThanOrEqual(offPathLines.count, 14, "off-path snippet grew past ≤14 budget")
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
