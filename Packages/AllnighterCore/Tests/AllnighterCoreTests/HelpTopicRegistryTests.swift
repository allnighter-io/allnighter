import XCTest
@testable import AllnighterCore

final class HelpTopicRegistryTests: XCTestCase {
    private let reg = ContractRegistry.milestone1

    private var toolNames: Set<String> { Set(reg.mcpTools.map(\.name)) }
    private var m1Commands: Set<String> { Set(reg.commands.filter { $0.milestone == .m1 }.map(\.name)) }
    private var errorCodes: Set<String> { Set(reg.errors.map(\.code)) }
    private var schemaNames: Set<String> { Set(ContractRegistry.OutputSchema.allCases.map(\.rawValue)) }

    // MARK: - Reference resolution (Guide truth must point at real Contract truth)

    func testEveryTopicReferenceResolvesToTheRegistry() {
        for t in HelpTopicRegistry.topics {
            for tool in t.relatedToolIds {
                XCTAssertTrue(toolNames.contains(tool), "topic \(t.id) names unknown MCP tool \(tool)")
            }
            for cmd in t.relatedCommandNames {
                XCTAssertTrue(m1Commands.contains(cmd), "topic \(t.id) names unknown command '\(cmd)'")
            }
            for code in t.errorRefs {
                XCTAssertTrue(errorCodes.contains(code), "topic \(t.id) names unknown error \(code)")
            }
            for schema in t.schemaRefs {
                XCTAssertTrue(schemaNames.contains(schema), "topic \(t.id) names unknown schema \(schema)")
            }
        }
    }

    func testEveryAdvertisedMCPToolIsReachableFromATopic() {
        let covered = Set(HelpTopicRegistry.topics.flatMap(\.relatedToolIds))
        let uncovered = toolNames.subtracting(covered)
        XCTAssertTrue(uncovered.isEmpty, "MCP tools with no help topic route: \(uncovered.sorted())")
    }

    func testTopicIdsAndAliasRedirectsAreUnique() {
        let ids = HelpTopicRegistry.topics.map(\.id)
        XCTAssertEqual(ids.count, Set(ids).count, "duplicate topic id")
        // An alias must not collide with a different topic's id.
        for (alias, target) in HelpTopicRegistry.aliasRedirects {
            if let owner = HelpTopicRegistry.topics.first(where: { $0.id == alias }) {
                XCTAssertEqual(owner.id, target, "alias '\(alias)' shadows a different topic id")
            }
        }
    }

    // MARK: - No repo dependency / banned vocabulary in PUBLIC prose

    func testNoTopicProseLeaksRepoOnlyPaths() {
        let banned = ["docs/phases", "Packages/", "Sources/", "AllnighterCore/", ".swift"]
        for t in HelpTopicRegistry.topics {
            let prose = (t.title + " " + t.summary + " " + t.bodyMarkdown + " " + t.sections.map(\.bodyMarkdown).joined(separator: " "))
            for b in banned {
                XCTAssertFalse(prose.contains(b), "topic \(t.id) public prose leaks repo path '\(b)'")
            }
        }
    }

    func testNoRetiredVocabularyInPublicProse() {
        // Retired words may live in `aliases` (so search still finds them) but never in
        // titles/summaries/bodies.
        let retired = ["fan out", "fanout", "council", "judge panel"]
        for t in HelpTopicRegistry.topics {
            let prose = (t.title + " " + t.summary + " " + t.bodyMarkdown + " "
                         + t.sections.map { $0.title + " " + $0.bodyMarkdown }.joined(separator: " ")).lowercased()
            for term in retired {
                XCTAssertFalse(prose.contains(term), "topic \(t.id) uses retired vocabulary '\(term)' in public prose")
            }
        }
    }

    // MARK: - Search

    func testSearchRoutesCanonicalQueries() {
        func top(_ q: String) -> String? { HelpService.search(q).results.first?.topicId }
        XCTAssertEqual(top("How do I send this to a team?"), "team_run_loop")
        XCTAssertEqual(top("put this on Codex's desk later"), "pending")
        XCTAssertEqual(top("auto substitution tier"), "default_model")
        XCTAssertEqual(top("why can't allnighter run codex"), "setup_and_auth")
    }

    func testSearchScoresAreNormalizedAndOrdered() throws {
        let r = HelpService.search("team run preflight start")
        let first = try XCTUnwrap(r.results.first)
        XCTAssertEqual(first.score, 1.0, accuracy: 0.0001)
        XCTAssertEqual(r.results.map(\.score), r.results.map(\.score).sorted(by: >))
        XCTAssertNotNil(r.suggestedAnswerMarkdown)
    }

    func testSearchFindsRetiredVocabularyViaAlias() {
        XCTAssertEqual(HelpService.search("fan out").results.first?.topicId, "team_run_loop")
        XCTAssertEqual(HelpTopicRegistry.canonicalTopicId(for: "later"), "pending")
    }

    // MARK: - Get + selectors

    func testGetByTopicSectionToolSchemaError() {
        XCTAssertEqual(HelpService.get(topic: "pending").topic?.id, "pending")

        let sectioned = HelpService.get(ref: "alln://help/pending#when-to-use-pending")
        XCTAssertEqual(sectioned.topic?.id, "pending")
        XCTAssertEqual(sectioned.selectedSectionId, "when-to-use-pending")

        XCTAssertTrue(HelpService.get(tool: "team_start").found)
        XCTAssertEqual(HelpService.get(ref: "alln://schema/defaultSettingsJSON").topic?.id, "default_model")
        XCTAssertEqual(HelpService.get(error: "SOURCE_AUTH_EXPIRED").topic?.id, "setup_and_auth")
    }

    func testUnknownTopicReturnsCloseMatchesAndSitemapNotADeadEnd() {
        let r = HelpService.get(topic: "substitutions")  // alias → default_model (resolves)
        XCTAssertEqual(r.topic?.id, "default_model")

        let miss = HelpService.get(topic: "how-do-tiers-work-exactly")
        XCTAssertFalse(miss.found)
        XCTAssertFalse(miss.closeMatches.isEmpty, "a miss must offer close matches")
        XCTAssertFalse(miss.sitemap.isEmpty, "a miss must offer the sitemap")
    }

    func testUnknownSectionFallsBackToTopicNotError() {
        let r = HelpService.get(ref: "alln://help/pending#no-such-section")
        XCTAssertEqual(r.topic?.id, "pending")
        XCTAssertNil(r.selectedSectionId, "unknown section is dropped, topic still returned")
    }

    // MARK: - Ref round-trip

    func testHelpRefBuildAndParseRoundTrip() {
        XCTAssertEqual(HelpRef.parse(HelpRef.help("pending", "x")), .topic("pending", section: "x"))
        XCTAssertEqual(HelpRef.parse(HelpRef.help("pending")), .topic("pending", section: nil))
        XCTAssertEqual(HelpRef.parse(HelpRef.tool("team_start")), .tool("team_start"))
        XCTAssertEqual(HelpRef.parse(HelpRef.schema("teamStartResponse")), .schema("teamStartResponse"))
        XCTAssertEqual(HelpRef.parse(HelpRef.error("CLI_USAGE_ERROR")), .error("CLI_USAGE_ERROR"))
        XCTAssertNil(HelpRef.parse("https://example.com"))
        XCTAssertNil(HelpRef.parse("alln://bogus/x"))
    }
}
