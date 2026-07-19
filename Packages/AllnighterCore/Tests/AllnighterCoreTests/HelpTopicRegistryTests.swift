import XCTest
@testable import AllnighterCore

final class HelpTopicRegistryTests: XCTestCase {
    private let reg = ContractRegistry.milestone1

    private var m1Commands: Set<String> { Set(reg.commands.filter { $0.milestone == .m1 }.map(\.name)) }
    private var errorCodes: Set<String> { Set(reg.errors.map(\.code)) }
    private var schemaNames: Set<String> { Set(ContractRegistry.OutputSchema.allCases.map(\.rawValue)) }

    /// Retired MCP / invented-flag grammar that must never reappear in live help prose.
    private let retiredVocabulary: [String] = [
        "fan out", "fanout", "council", "judge panel",
        "dryrun", "dryRun",
        "team_start(", "pair_relay(action",
        "team_run", "team_ask", "run_get",
        "pair slice", "pair status",
        "pending_run", "pending_update", "project_get", "stalled_update",
        "teams_get", "skills_get", "defaults_get", "error_explain",
        "team_start(dryRun",
    ]

    // MARK: - Reference resolution (Guide truth must point at real Contract truth)

    func testEveryTopicReferenceResolvesToTheRegistry() {
        for t in HelpTopicRegistry.topics {
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
        // titles/summaries/bodies/sections.
        for t in HelpTopicRegistry.topics {
            let prose = (t.title + " " + t.summary + " " + t.bodyMarkdown + " "
                         + t.sections.map { $0.title + " " + $0.bodyMarkdown }.joined(separator: " "))
            let proseLower = prose.lowercased()
            for term in retiredVocabulary {
                if term == "dryRun" {
                    XCTAssertFalse(prose.contains(term), "topic \(t.id) uses retired vocabulary '\(term)' in public prose")
                } else {
                    XCTAssertFalse(proseLower.contains(term.lowercased()),
                                   "topic \(t.id) uses retired vocabulary '\(term)' in public prose")
                }
            }
        }
    }

    /// ASF-S05: first-contact decision tree covers run / team / thread / pending / hello --for.
    func testToolSelectionDecisionTreeMentionsCoreVerbs() throws {
        let topic = try XCTUnwrap(HelpTopicRegistry.topic(id: "tool_selection"))
        let prose = ([topic.summary, topic.bodyMarkdown]
                     + topic.sections.map(\.bodyMarkdown)).joined(separator: "\n")
        for needle in [
            "alln run",
            "alln team start",
            "alln thread send",
            "alln pending",
            "hello --for",
        ] {
            XCTAssertTrue(prose.contains(needle), "tool_selection must mention '\(needle)'")
        }
        XCTAssertEqual(HelpTopicRegistry.canonicalTopicId(for: "which command"), "tool_selection")
        XCTAssertEqual(HelpTopicRegistry.canonicalTopicId(for: "run vs team"), "tool_selection")
        XCTAssertEqual(HelpTopicRegistry.canonicalTopicId(for: "thread send"), "tool_selection")
    }

    /// ASF-S06: bootstrap teaches rebuild + install-cli + version freshness.
    func testBootstrapTeachesSelfBuildOneLiner() throws {
        let topic = try XCTUnwrap(HelpTopicRegistry.topic(id: "bootstrap"))
        let prose = topic.summary + " " + topic.bodyMarkdown
        XCTAssertTrue(prose.contains("swift build -c release --product alln"))
        XCTAssertTrue(prose.contains("alln install-cli"))
        XCTAssertTrue(prose.contains("version --json") || prose.contains("alln version"))
        XCTAssertTrue(prose.contains("tool_selection") || prose.contains("hello --for"))
    }

    /// Golden: team_run_loop teaches CLI verbs in both markdown projections.
    func testTeamRunLoopGoldenCLIVerbsInTopicAndDocsMarkdown() throws {
        let topic = try XCTUnwrap(HelpTopicRegistry.topic(id: "team_run_loop"))
        let md = HelpService.topicMarkdown(topic)
        let docs = try XCTUnwrap(HelpService.docsMarkdown(topic: "team_run_loop"))

        for surface in [("topicMarkdown", md), ("docsMarkdown", docs)] {
            let (label, text) = surface
            XCTAssertTrue(text.contains("alln team preflight"), "\(label) must teach alln team preflight")
            XCTAssertTrue(text.contains("alln team start"), "\(label) must teach alln team start")
            for banned in ["dryRun", "team_start(", "team_run", "team_ask", "run_get"] {
                XCTAssertFalse(text.contains(banned), "\(label) must not contain '\(banned)'")
            }
        }
    }

    /// JSON envelope must not leak relatedToolIds (field removed from HelpTopic).
    func testHelpGetJSONDoesNotEmitRelatedToolIds() throws {
        let envelope = HelpProjector.get(topic: "team_run_loop", contractVersion: "1.0.0")
        let data = try CoreJSON.encode(envelope)
        let raw = String(data: data, encoding: .utf8) ?? ""
        XCTAssertFalse(raw.contains("relatedToolIds"), "help get --json must not emit relatedToolIds")
        XCTAssertTrue(raw.contains("relatedCommandNames"), "help get --json still carries relatedCommandNames")
    }

    // MARK: - Search

    func testSearchRoutesCanonicalQueries() {
        func top(_ q: String) -> String? { HelpService.search(q).results.first?.topicId }
        XCTAssertEqual(top("How do I send this to a team?"), "team_run_loop")
        XCTAssertEqual(top("put this on Codex's desk later"), "pending")
        XCTAssertEqual(top("auto substitution tier"), "default_model")
        XCTAssertEqual(top("why can't allnighter run codex"), "setup_and_auth")
    }

    func testSearchRoutesAutoFixQueries() {
        func top(_ q: String) -> String? { HelpService.search(q).results.first?.topicId }
        XCTAssertEqual(top("fix a bug in my repo"), "auto_fix")
        XCTAssertEqual(top("try fix"), "auto_fix")
        XCTAssertEqual(top("auto fix"), "auto_fix")
    }

    func testSearchScoresAreNormalizedAndOrdered() throws {
        let r = HelpService.search("team run preflight start")
        let first = try XCTUnwrap(r.results.first)
        XCTAssertEqual(first.score, 1.0, accuracy: 0.0001)
        XCTAssertEqual(r.results.map(\.score), r.results.map(\.score).sorted(by: >))
        XCTAssertNotNil(r.suggestedAnswerMarkdown)
    }

    func testSearchClampsDegenerateLimit() {
        let r = HelpService.search("team", limit: 0)
        XCTAssertFalse(r.results.isEmpty, "limit 0 is clamped to 1 — no answer without supporting hits")
        XCTAssertNotNil(r.suggestedAnswerMarkdown)
    }

    func testSearchFindsRetiredVocabularyViaAlias() {
        XCTAssertEqual(HelpService.search("fan out").results.first?.topicId, "team_run_loop")
        XCTAssertEqual(HelpTopicRegistry.canonicalTopicId(for: "later"), "pending")
    }

    func testSearchFindsCatalogTermsViaDiscoveryIndex() {
        let opencode = HelpService.search("opencode")
        XCTAssertFalse(opencode.isMiss)
        XCTAssertEqual(opencode.results.first?.topicId, "teams_and_workers")
        XCTAssertFalse(opencode.discoveryModelIds.isEmpty)

        let glm = HelpService.search("glm")
        XCTAssertFalse(glm.isMiss)
        XCTAssertEqual(glm.results.first?.topicId, "teams_and_workers")
        XCTAssertTrue(glm.discoveryModelIds.contains("model_opencode_glm_5_2"))

        XCTAssertEqual(HelpTopicRegistry.canonicalTopicId(for: "opencode"), "teams_and_workers")
        XCTAssertEqual(HelpTopicRegistry.canonicalTopicId(for: "glm"), "teams_and_workers")
    }

    func testSearchTreatsWeakFuzzyNoiseAsMiss() {
        let r = HelpService.search("asdfqwerty-no-such-topic-999")
        XCTAssertTrue(r.isMiss)
        XCTAssertTrue(r.results.isEmpty)
    }

    // MARK: - Get + selectors

    func testGetByTopicSectionSchemaError() {
        XCTAssertEqual(HelpService.get(topic: "pending").topic?.id, "pending")

        let sectioned = HelpService.get(ref: "alln://help/pending#when-to-use-pending")
        XCTAssertEqual(sectioned.topic?.id, "pending")
        XCTAssertEqual(sectioned.selectedSectionId, "when-to-use-pending")

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
        XCTAssertEqual(HelpRef.parse(HelpRef.schema("teamStartResponse")), .schema("teamStartResponse"))
        XCTAssertEqual(HelpRef.parse(HelpRef.error("CLI_USAGE_ERROR")), .error("CLI_USAGE_ERROR"))
        XCTAssertNil(HelpRef.parse(HelpRef.help("pending").replacingOccurrences(of: "help", with: "tool")))
        XCTAssertNil(HelpRef.parse("alln://tool/team_start"), "retired alln://tool/ refs no longer resolve")
        XCTAssertNil(HelpRef.parse("https://example.com"))
        XCTAssertNil(HelpRef.parse("alln://bogus/x"))
    }
}
