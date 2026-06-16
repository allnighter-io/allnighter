import XCTest
@testable import AllnighterCore

final class ToolCensusTests: XCTestCase {

    /// The real corrected census from a healthy Grok agent (stable `~/.grok/bin`
    /// paths, not the `~/.grok/downloads` blobs the first attempt returned).
    private let realCensus = """
    {
      "agent": { "absolute_path": "/Users/mike/.grok/bin/agent", "version": "grok 0.1.219 (c9b7cdec23a)" },
      "agy": { "absolute_path": "/Users/mike/.local/bin/agy", "version": "1.0.8" },
      "aider": { "absolute_path": "/Users/mike/.local/share/uv/tools/aider-chat/bin/aider", "version": "aider 0.86.2" },
      "claude": { "absolute_path": "/Users/mike/.local/share/claude/versions/2.1.178", "version": "2.1.178 (Claude Code)" },
      "codex": { "absolute_path": "/opt/homebrew/Caskroom/codex/0.130.0/codex-aarch64-apple-darwin", "version": "codex-cli 0.130.0" },
      "goose": { "absolute_path": "/Users/mike/.local/bin/goose", "version": "1.29.1" },
      "grok": { "absolute_path": "/Users/mike/.grok/bin/grok", "version": "grok 0.2.54 (fee15ff8ea0) [stable]" }
    }
    """

    private func driver(_ id: String, bins: [String]) -> DriverManifest {
        DriverManifest(id: id, displayName: id, kind: .headlessCLI,
                       detectCommand: "\(bins[0]) --version",
                       invoke: .init(command: bins[0], args: []),
                       setup: SetupBlock(bins: bins))
    }

    private var registry: [DriverManifest] {
        [driver("claude_code", bins: ["claude"]),
         driver("codex", bins: ["codex"]),
         driver("grok", bins: ["grok"]),
         driver("antigravity", bins: ["agy"]),
         DriverManifest(id: "manual_paste", displayName: "Manual", kind: .manualPaste)]
    }

    func testParsesRealCensus() throws {
        let census = try ToolCensus.parse(realCensus)
        XCTAssertEqual(census.entries.count, 7)
        XCTAssertEqual(census.entries["grok"]?.absolutePath, "/Users/mike/.grok/bin/grok")
        XCTAssertEqual(census.entries["agy"]?.version, "1.0.8")
    }

    func testMatchesOnlySupportedDriversViaBins() throws {
        let census = try ToolCensus.parse(realCensus)
        let candidates = census.candidates(for: registry)
        let byDriver = Dictionary(uniqueKeysWithValues: candidates.map { ($0.driverId, $0) })

        // Supported: claude, codex, grok, antigravity. Dropped: aider, goose, agent, manual_paste.
        XCTAssertEqual(Set(byDriver.keys), ["claude_code", "codex", "grok", "antigravity"])
        XCTAssertEqual(byDriver["grok"]?.path, "/Users/mike/.grok/bin/grok")
        XCTAssertEqual(byDriver["antigravity"]?.path, "/Users/mike/.local/bin/agy")
        XCTAssertEqual(byDriver["antigravity"]?.bin, "agy")
    }

    func testFlagsEphemeralPaths() throws {
        let census = try ToolCensus.parse(realCensus)
        let byDriver = Dictionary(uniqueKeysWithValues: census.candidates(for: registry).map { ($0.driverId, $0) })

        // Stable launchers the manager maintains.
        XCTAssertFalse(byDriver["grok"]?.looksEphemeral ?? true, "~/.grok/bin/grok is a stable launcher")
        XCTAssertFalse(byDriver["antigravity"]?.looksEphemeral ?? true, "~/.local/bin/agy is stable")
        // Version-pinned blobs that break on upgrade.
        XCTAssertTrue(byDriver["claude_code"]?.looksEphemeral ?? false, "/versions/2.1.178 is upgrade-fragile")
        XCTAssertTrue(byDriver["codex"]?.looksEphemeral ?? false, "/Caskroom/codex/0.130.0 is upgrade-fragile")
    }

    func testEphemeralHeuristicDirectly() {
        XCTAssertTrue(CensusPath.looksEphemeral("/Users/mike/.grok/downloads/grok-0.2.54-macos-aarch64"))
        XCTAssertTrue(CensusPath.looksEphemeral("/opt/homebrew/Cellar/foo/1.2.3/bin/foo"))
        XCTAssertFalse(CensusPath.looksEphemeral("/opt/homebrew/bin/codex"))
        XCTAssertFalse(CensusPath.looksEphemeral("/Users/mike/.local/bin/agy"))
        XCTAssertFalse(CensusPath.looksEphemeral("/Users/mike/.grok/bin/grok"))
    }

    func testParsesJSONWrappedInProse() throws {
        let chatty = """
        Sure! Here is what I found on your machine:
        { "claude": { "absolute_path": "/Users/mike/.local/bin/claude", "version": "2.1.178" } }
        Let me know if you need anything else.
        """
        let census = try ToolCensus.parse(chatty)
        XCTAssertEqual(census.entries["claude"]?.absolutePath, "/Users/mike/.local/bin/claude")
    }

    func testRejectsNonJSON() {
        XCTAssertThrowsError(try ToolCensus.parse("no json here at all"))
    }
}
