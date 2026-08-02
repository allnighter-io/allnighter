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
        XCTAssertEqual(Bootstrap.Host(argument: "hermes"), .hermes)
        XCTAssertEqual(Bootstrap.Host(argument: "Hermes"), .hermes)
        XCTAssertEqual(Bootstrap.Host(argument: "OPENCLAW"), .openclaw)
        XCTAssertEqual(Bootstrap.Host(argument: "openclaw"), .openclaw)
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
        // OPC-S02: cold hosts — honest print-only, never invent a path.
        let printOnly = "host system prompt / tools instructions (print-only)"
        XCTAssertEqual(Bootstrap.Host.hermes.pasteTarget, printOnly)
        XCTAssertEqual(Bootstrap.Host.openclaw.pasteTarget, printOnly)
    }

    // MARK: - Checkout rebuild gate (OPC-S02)

    func testCheckoutRebuildLineOnlyForCheckoutHosts() {
        let rebuildNeedle = "bash scripts/rebuild_cli.sh"
        for host in [Bootstrap.Host.claude, .cursor, .codex, .generic] {
            let s = Bootstrap.snippet(binaryPath: sampleBinary, onPath: true, host: host)
            XCTAssertTrue(s.contains(rebuildNeedle), "\(host.rawValue) must teach checkout rebuild")
        }
        for host in [Bootstrap.Host.hermes, .openclaw] {
            let s = Bootstrap.snippet(binaryPath: sampleBinary, onPath: true, host: host)
            XCTAssertFalse(s.contains(rebuildNeedle), "\(host.rawValue) must not teach checkout rebuild")
            XCTAssertFalse(s.contains("rebuild_cli"), "\(host.rawValue) must not mention rebuild_cli at all")
        }
    }

    func testColdHostRenderCarriesPreambleWithoutCheckoutPoison() {
        for host in [Bootstrap.Host.hermes, .openclaw] {
            let out = Bootstrap.render(host: host, binaryPath: sampleBinary, onPath: true)
            XCTAssertTrue(out.contains("subscription CLIs"), "\(host.rawValue) preamble must name subscription CLIs")
            XCTAssertTrue(out.contains("alln menu --json"), "\(host.rawValue) preamble must start with menu")
            XCTAssertTrue(out.contains("Authorize before"), "\(host.rawValue) preamble must teach authorize-before-spend")
            XCTAssertTrue(out.contains("Upgrade between rounds"), "\(host.rawValue) preamble must teach upgrade timing")
            XCTAssertTrue(out.contains(host.pasteTarget))
            XCTAssertFalse(out.contains("rebuild_cli"), "\(host.rawValue) render must not poison with checkout rebuild")
            // "not API keys" is fine; obtaining/setting an API key is not.
            XCTAssertFalse(out.lowercased().contains("api_key"), "\(host.rawValue) must not advise API keys")
            XCTAssertFalse(out.lowercased().contains("set your api"), "\(host.rawValue) must not advise API keys")
            XCTAssertFalse(out.lowercased().contains("mcp"), "\(host.rawValue) must not revive MCP")
        }
        // Checkout hosts keep the compact render (no cold preamble).
        let claude = Bootstrap.render(host: .claude, binaryPath: sampleBinary, onPath: true)
        XCTAssertFalse(claude.contains("subscription CLIs"), "claude must not get cold-host preamble")
        XCTAssertTrue(claude.hasPrefix("Paste into"), "claude render starts at paste target")
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
        XCTAssertTrue(s.contains("nextAction.command"), "must teach detached nextAction delivery")
        XCTAssertTrue(s.contains("alln show <id> --stream"), "must teach show --stream reattach")
        XCTAssertFalse(s.contains("team hello"))
        XCTAssertFalse(s.contains("route --for"))
        XCTAssertFalse(s.contains("resolve --for"))
        XCTAssertFalse(s.contains("model_sonnet"), "must not embed catalog rows")
        XCTAssertTrue(s.contains(TeachingSnippet.openMarkerPrefix), "must wrap teaching in markers")
        XCTAssertTrue(s.contains(TeachingSnippet.closeMarker), "must close teaching markers")
        XCTAssertTrue(s.contains("hash=\(TeachingSnippet.contentHash)"), "marker must carry content hash")
        XCTAssertTrue(
            s.contains("COMPLETE human-readable stdout table verbatim"),
            "bootstrap must teach capacity verbatim print contract"
        )
        XCTAssertTrue(
            s.contains("Use `--json` only when the user explicitly requests"),
            "bootstrap must teach JSON only on explicit request"
        )
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

    /// Ten-rule body + markers stays compact (AVQ-S03 mutator/progress law).
    /// `TeachingSnippet.reflexLines` grew from 8 to 10 rules (pmTurn.report,
    /// artifact.path disclosure) without a matching budget bump; the 2-line
    /// growth is real content, not budget rot, so the ceiling moves with it
    /// (12→14 on-path, 14→16 off-path — same zero/one-line slack as before).
    func testSnippetStaysWithinLineBudget() {
        let onPathLines = Bootstrap.snippet(binaryPath: sampleBinary, onPath: true)
            .split(separator: "\n", omittingEmptySubsequences: false)
        XCTAssertLessThanOrEqual(onPathLines.count, 14, "on-path snippet grew past ≤14 budget")

        let offPathLines = Bootstrap.snippet(binaryPath: sampleBinary, onPath: false)
            .split(separator: "\n", omittingEmptySubsequences: false)
        XCTAssertLessThanOrEqual(offPathLines.count, 16, "off-path snippet grew past ≤16 budget")
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
        XCTAssertTrue(all.allSatisfy { $0.binaryPath == sampleBinary })
        // Checkout hosts share the rebuild-bearing snippet; cold hosts share the
        // rebuild-free variant — two families, not six unique bodies.
        let checkoutSnippets = Set(
            all.filter { Bootstrap.Host(rawValue: $0.host)?.includesCheckoutRebuild == true }.map(\.snippet)
        )
        let coldSnippets = Set(
            all.filter { Bootstrap.Host(rawValue: $0.host)?.includesCheckoutRebuild == false }.map(\.snippet)
        )
        XCTAssertEqual(checkoutSnippets.count, 1)
        XCTAssertEqual(coldSnippets.count, 1)
        XCTAssertNotEqual(checkoutSnippets.first, coldSnippets.first)
        XCTAssertTrue(all.contains { $0.host == "hermes" })
        XCTAssertTrue(all.contains { $0.host == "openclaw" })
    }

    // MARK: - Never edits files (consent posture parity with the retired MCP install)

    func testBootstrapNeverTouchesTheFilesystem() {
        let a = Bootstrap.render(host: .generic, binaryPath: sampleBinary, onPath: true)
        let b = Bootstrap.render(host: .generic, binaryPath: sampleBinary, onPath: true)
        XCTAssertEqual(a, b)
        // Cold hosts are pure too — render twice, same bytes, no FS side effects.
        let h1 = Bootstrap.render(host: .hermes, binaryPath: sampleBinary, onPath: true)
        let h2 = Bootstrap.render(host: .hermes, binaryPath: sampleBinary, onPath: true)
        XCTAssertEqual(h1, h2)
        let o1 = Bootstrap.render(host: .openclaw, binaryPath: sampleBinary, onPath: false)
        let o2 = Bootstrap.render(host: .openclaw, binaryPath: sampleBinary, onPath: false)
        XCTAssertEqual(o1, o2)
        // And JSON projection is pure.
        let j1 = Bootstrap.jsonString(host: .hermes, binaryPath: sampleBinary, onPath: true)
        let j2 = Bootstrap.jsonString(host: .openclaw, binaryPath: sampleBinary, onPath: true)
        XCTAssertFalse(j1.isEmpty)
        XCTAssertFalse(j2.isEmpty)
        XCTAssertNotEqual(j1, j2) // host field differs
    }
}
