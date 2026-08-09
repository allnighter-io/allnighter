import XCTest
@testable import AllnighterCore

final class HelpTopicRegistryTests: XCTestCase {
    private let reg = ContractRegistry.milestone1

    private var m1Commands: Set<String> { Set(reg.commands.filter { $0.milestone == .m1 }.map(\.name)) }
    private var errorCodes: Set<String> { Set(reg.errors.map(\.code)) }
    private var schemaNames: Set<String> { Set(ContractRegistry.OutputSchema.allCases.map(\.rawValue)) }


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
        // titles/summaries/bodies/sections. Deny-list SSOT: RetiredVocabulary.
        for t in HelpTopicRegistry.topics {
            let prose = (t.title + " " + t.summary + " " + t.bodyMarkdown + " "
                         + t.sections.map { $0.title + " " + $0.bodyMarkdown }.joined(separator: " "))
            if let hit = RetiredVocabulary.proseContainsDenyTerm(prose) {
                XCTFail("topic \(t.id) uses retired vocabulary '\(hit)' in public prose")
            }
        }
    }

    /// ASF-S05: first-contact decision tree covers run / thread / pending / menu.
    /// `--detach` was demoted from a taught verb to a temporarily-unsupported
    /// surface in 1c04876e (code-red: restore direct run and delete mirrors), then
    /// permanently deny-listed as phantom grammar (RSC-S05) — the real detached-
    /// dispatch flag is `--no-wait` (RSC-S04), so the topic must teach that, not the
    /// never-shipped `--detach` name.
    func testToolSelectionDecisionTreeMentionsCoreVerbs() throws {
        let topic = try XCTUnwrap(HelpTopicRegistry.topic(id: "tool_selection"))
        let prose = ([topic.summary, topic.bodyMarkdown]
                     + topic.sections.map(\.bodyMarkdown)).joined(separator: "\n")
        for needle in [
            "alln run",
            "alln thread send",
            "alln pending add",
            "alln menu --json",
        ] {
            XCTAssertTrue(prose.contains(needle), "tool_selection must mention '\(needle)'")
        }
        // RSC-S05: `--detach` never shipped as a real flag; help must not advertise
        // it, and must instead teach the real detached-dispatch flag by name.
        XCTAssertFalse(prose.contains("--detach"),
                       "tool_selection must not mention --detach — it never shipped as a CLI flag")
        XCTAssertTrue(prose.contains("--no-wait"),
                      "tool_selection must teach --no-wait as the real detached-dispatch flag")
        XCTAssertTrue(prose.contains("foreground"),
                      "tool_selection must state that runs are foreground by default")
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
        XCTAssertTrue(prose.contains(ReleaseChannel.installCommand),
                      "bootstrap must teach cold install one-liner, not install-cli alone")
        XCTAssertTrue(prose.contains("PATH repair") || prose.contains("repair"),
                      "bootstrap must frame install-cli as PATH repair, not cold start")
        XCTAssertTrue(prose.contains("version --json") || prose.contains("alln version"))
        XCTAssertTrue(prose.contains("tool_selection") || prose.contains("menu --json"))
    }

    /// OPC-S03: cold recovery is the one-liner; install-cli is PATH repair only.
    func testQuickstartTeachesColdInstallNotInstallCliAlone() throws {
        let topic = try XCTUnwrap(HelpTopicRegistry.topic(id: "quickstart"))
        let prose = topic.summary + " " + topic.bodyMarkdown
        XCTAssertTrue(prose.contains(ReleaseChannel.installCommand),
                      "quickstart must cite ReleaseChannel.installCommand for cold install")
        XCTAssertTrue(prose.contains("alln install-cli"),
                      "quickstart still mentions install-cli for PATH repair")
        XCTAssertTrue(prose.contains("PATH repair") || prose.contains("repair"),
                      "quickstart must frame install-cli as PATH repair")
    }

    /// OPC-S03: search aliases surface cold-install and host recovery terms.
    func testSearchRoutesColdInstallAndHostAliases() {
        func top(_ q: String) -> String? { HelpService.search(q).results.first?.topicId }
        XCTAssertEqual(top("install"), "bootstrap")
        XCTAssertEqual(top("curl"), "quickstart")
        XCTAssertEqual(top("hermes"), "bootstrap")
        XCTAssertEqual(top("openclaw"), "bootstrap")
        XCTAssertEqual(top("get alln"), "quickstart")
        XCTAssertEqual(top("no alln"), "quickstart")
        XCTAssertEqual(top("PATH"), "quickstart")
        XCTAssertEqual(top("update"), "quickstart")
        XCTAssertEqual(top("upgrade"), "quickstart")
    }

    /// OPC-S03: help prose + README both cite the one install one-liner SSOT.
    func testInstallCommandIsSharedSSOTAcrossHelpAndREADME() throws {
        let command = ReleaseChannel.installCommand
        let quickstart = try XCTUnwrap(HelpTopicRegistry.topic(id: "quickstart"))
        let bootstrap = try XCTUnwrap(HelpTopicRegistry.topic(id: "bootstrap"))
        XCTAssertTrue(quickstart.bodyMarkdown.contains(command),
                      "quickstart body must contain ReleaseChannel.installCommand")
        XCTAssertTrue(bootstrap.bodyMarkdown.contains(command),
                      "bootstrap body must contain ReleaseChannel.installCommand")

        // …/Packages/AllnighterCore/Tests/AllnighterCoreTests/<this>.swift → up 5.
        let repoRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // AllnighterCoreTests
            .deletingLastPathComponent()   // Tests
            .deletingLastPathComponent()   // AllnighterCore
            .deletingLastPathComponent()   // Packages
            .deletingLastPathComponent()   // repo root
        let readmeURL = repoRoot.appendingPathComponent("README.md")
        let readme = try String(contentsOf: readmeURL, encoding: .utf8)
        XCTAssertTrue(readme.contains(command),
                      "README.md must contain ReleaseChannel.installCommand verbatim")
    }

    /// Agent print contract: capacity help must teach verbatim table delivery.
    func testCapacityHelpTeachesVerbatimTablePrintContract() throws {
        let topic = try XCTUnwrap(HelpTopicRegistry.topic(id: "capacity"))
        let md = HelpService.topicMarkdown(topic)
        let docs = try XCTUnwrap(HelpService.docsMarkdown(topic: "capacity"))
        let envelope = HelpProjector.get(topic: "capacity", contractVersion: reg.contractVersion)
        let body = try XCTUnwrap(envelope.topic?.bodyMarkdown)

        for surface in [
            ("summary", topic.summary),
            ("topicMarkdown", md),
            ("docsMarkdown", docs),
            ("helpGet.topic.bodyMarkdown", body),
        ] {
            let (label, text) = surface
            XCTAssertTrue(
                text.contains("verbatim") || text.localizedCaseInsensitiveContains("COMPLETE"),
                "\(label) must teach verbatim/complete table delivery"
            )
            XCTAssertTrue(
                text.contains("shown above") || text.contains("--json"),
                "\(label) must distinguish human table vs summary/JSON abuse"
            )
        }

        // Body is the durable agent contract surface.
        XCTAssertTrue(body.contains("COMPLETE"), "help get body must require the complete table")
        XCTAssertTrue(body.contains("verbatim"), "help get body must say verbatim")
        XCTAssertTrue(body.contains("shown above"), "help get body must ban 'shown above'")
        XCTAssertTrue(
            body.contains("explicitly requests") || body.contains("explicitly request"),
            "help get body must restrict --json to explicit JSON/machine requests"
        )
        XCTAssertFalse(
            body.contains("Use `alln capacity --json` for the agent contract"),
            "old wording that pushed --json as the agent default must not return"
        )
        XCTAssertTrue(
            topic.summary.contains("verbatim") || topic.summary.contains("--json"),
            "capacity summary must surface the print contract, not only sampling semantics"
        )
    }

    /// Golden: team_run_loop teaches CLI verbs in both markdown projections.
    func testTeamRunLoopGoldenCLIVerbsInTopicAndDocsMarkdown() throws {
        let topic = try XCTUnwrap(HelpTopicRegistry.topic(id: "team_run_loop"))
        let md = HelpService.topicMarkdown(topic)
        let docs = try XCTUnwrap(HelpService.docsMarkdown(topic: "team_run_loop"))

        // `--detach` was demoted to a temporarily-unsupported surface in 1c04876e
        // (code-red: restore direct run and delete mirrors), so the supported loop
        // this topic teaches is dry-run → foreground run — no `alln run --detach`.
        for surface in [("topicMarkdown", md), ("docsMarkdown", docs)] {
            let (label, text) = surface
            XCTAssertTrue(text.contains("alln run --dry-run"), "\(label) must teach alln run --dry-run")
            XCTAssertTrue(text.contains("foreground run"), "\(label) must teach the foreground run loop")
            XCTAssertFalse(text.contains("alln run --detach"),
                           "\(label) must not teach --detach as a usable verb (Code Red: unsupported)")
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

    func testSearchRoutesArtifactQueries() {
        func top(_ q: String) -> String? { HelpService.search(q).results.first?.topicId }
        XCTAssertEqual(top("team artifact"), "artifact")
        XCTAssertEqual(top("receipt"), "artifact")
        XCTAssertEqual(top("report"), "artifact")
    }

    /// ADP-S04: task-verb team-authoring queries must resolve to the
    /// `teams_agents_and_skills` topic (which teaches `teams duplicate` / `teams new`)
    /// rather than losing the ranking tie to `team_run_loop` (running a team) —
    /// every one of these phrases contains the bare word "team", which
    /// `team_run_loop` also scores heavily on via its title/summary/related
    /// commands. Before ADP-S04 every query below topped out at `team_run_loop`.
    func testSearchRoutesExplicitSeatQueries() {
        func top(_ q: String) -> String? { HelpService.search(q).results.first?.topicId }
        XCTAssertEqual(top("staff models once"), "team_run_loop")
        XCTAssertEqual(top("custom seats"), "team_run_loop")
        XCTAssertEqual(top("one-off team"), "team_run_loop")
        XCTAssertEqual(top("temporary team"), "team_run_loop")
    }

    /// CHS-S02 — same-CLI crew seats on a spawn-gated driver (cursor_agent /
    /// opencode / agy) serialize instead of dropping; dry-run names it with a
    /// `seat_driver_serialized` warning. These terms must land on the topic
    /// that documents it (`team_run_loop`, alongside the `--seat` teaching above).
    func testSearchRoutesSpawnGateQueries() {
        func top(_ q: String) -> String? { HelpService.search(q).results.first?.topicId }
        XCTAssertEqual(top("spawn gate"), "team_run_loop")
        XCTAssertEqual(top("same CLI"), "team_run_loop")
        XCTAssertEqual(top("serialize seats"), "team_run_loop")
        XCTAssertEqual(top("concurrent seats"), "team_run_loop")
    }

    func testSearchRoutesTeamAuthoringQueries() {
        func top(_ q: String) -> String? { HelpService.search(q).results.first?.topicId }
        XCTAssertEqual(top("create a team"), "teams_agents_and_skills")
        XCTAssertEqual(top("make a custom team"), "teams_agents_and_skills")
        XCTAssertEqual(top("new team"), "teams_agents_and_skills")
        XCTAssertEqual(top("customize a team"), "teams_agents_and_skills")
        XCTAssertEqual(top("build a team"), "teams_agents_and_skills")
        XCTAssertEqual(top("edit skill"), "teams_agents_and_skills")
        XCTAssertEqual(top("shared skill"), "teams_agents_and_skills")
        XCTAssertEqual(top("restore skill"), "teams_agents_and_skills")
    }

    /// RSC-S05: a caller who was looking for the never-shipped `--detach` flag, or
    /// who just watched their own session die, must land on the topic that teaches
    /// the real survival mechanics — not just find the alias string somewhere in an
    /// array. `alln help search` is the actual discovery entry point (`HelpService.
    /// search`, projected by `alln help search` / `HelpProjector.search`), so proving
    /// it here proves discoverability, not merely that the alias was typed in.
    func testSearchRoutesDetachedDispatchSurvivalQueries() {
        func top(_ q: String) -> String? { HelpService.search(q).results.first?.topicId }
        XCTAssertEqual(top("no-wait"), "loop")
        XCTAssertEqual(top("survive"), "loop")
        XCTAssertEqual(top("my session died"), "loop")
        XCTAssertEqual(top("idempotency"), "team_run_loop")
        XCTAssertEqual(top("detach"), "team_run_loop")
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
        // Retargeted from opencode/glm to surviving catalog terms (founder ruling
        // 2026-07-24 removed the two opencode built-in models).
        let kimi = HelpService.search("kimi")
        XCTAssertFalse(kimi.isMiss)
        XCTAssertEqual(kimi.results.first?.topicId, "teams_agents_and_skills")
        XCTAssertFalse(kimi.discoveryModelIds.isEmpty)

        let grok = HelpService.search("grok")
        XCTAssertFalse(grok.isMiss)
        XCTAssertEqual(grok.results.first?.topicId, "teams_agents_and_skills")
        XCTAssertTrue(grok.discoveryModelIds.contains("model_grok"))

        XCTAssertEqual(HelpTopicRegistry.canonicalTopicId(for: "kimi"), "teams_agents_and_skills")
        XCTAssertEqual(HelpTopicRegistry.canonicalTopicId(for: "grok"), "teams_agents_and_skills")
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
