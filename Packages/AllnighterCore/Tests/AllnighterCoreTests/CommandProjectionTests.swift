import XCTest
@testable import AllnighterCore

/// SH-S10 — enum domains + flag constraints project from one registry owner onto
/// usage, docs, menu detail, and generated teaching surfaces.
final class CommandProjectionTests: XCTestCase {
    private let reg = ContractRegistry.milestone1

    func testEffortDomainOwnedByRegistryAndEffortLevel() throws {
        let domain = try XCTUnwrap(ContractRegistry.valueTypeDomains["effort"])
        XCTAssertEqual(domain, EffortLevel.allCases.map(\.rawValue))
        XCTAssertEqual(domain, ["low", "med", "high"])
    }

    func testEveryDomainValueTypeHasAtLeastOneFlag() {
        let valueTypes = Set(
            reg.commands
                .filter { $0.milestone == .m1 }
                .flatMap(\.flags)
                .compactMap(\.valueType)
        )
        for key in ContractRegistry.valueTypeDomains.keys {
            XCTAssertTrue(
                valueTypes.contains(key),
                "valueTypeDomains[\(key)] has no FlagSpec with that valueType"
            )
        }
    }

    func testFlagsWithDomainResolveAllowedValues() throws {
        guard let run = reg.commands.first(where: { $0.name == "run" }) else {
            return XCTFail("missing run")
        }
        let effort = try XCTUnwrap(run.flags.first(where: { $0.name == "effort" }))
        XCTAssertEqual(effort.allowedValues, ["low", "med", "high"])
        XCTAssertEqual(CommandProjection.valueToken(for: effort), "low|med|high")
    }

    func testUsageProjectsEnumDomainAndConstraints() throws {
        let text = try XCTUnwrap(CLIUsage.usageText(for: "run", registry: reg))
        XCTAssertTrue(text.contains("[--effort <low|med|high>]"), text)
        XCTAssertTrue(text.contains("Mutually exclusive: --json, --stream."), text)
        XCTAssertTrue(text.contains("Only with: --thread-id only with --detach."), text)
        XCTAssertTrue(text.contains("Requires: --accept-survivors requires --retry-of."), text)
    }

    func testDocsTopicProjectsConstraintsAndDomains() {
        guard let run = reg.commands.first(where: { $0.name == "run" }) else {
            return XCTFail("missing run")
        }
        let body = CommandProjection.markdownCommandBody(run)
        XCTAssertTrue(body.contains("`--effort <low|med|high>`"), body)
        XCTAssertTrue(body.contains("Mutually exclusive: `--json`, `--stream`."), body)
        XCTAssertTrue(body.contains("Only with: `--executor` only with `--try-fix`."), body)
    }

    func testFullDocsTeachStreamAndVendorBoundary() {
        let md = ContractDocs.markdown(reg)
        XCTAssertTrue(md.contains("## Run stream mode (`--stream`)"), md)
        XCTAssertTrue(md.contains("one JSON object per line"), md)
        XCTAssertTrue(md.contains("`teamRunCompleted`"), md)
        XCTAssertTrue(md.contains("## Model controls (vendor CLI boundary)"), md)
        XCTAssertTrue(md.contains("--temperature"), md)
        XCTAssertTrue(md.contains("--max-tokens"), md)
        XCTAssertFalse(md.lowercased().contains("estimated cost"))
    }

    func testMenuShowProjectsConstraintsAndAllowedValues() throws {
        let show = try MenuCatalog.show(ref: "command:run")
        let detail = try XCTUnwrap(show.command)
        XCTAssertFalse(detail.mutuallyExclusiveFlags.isEmpty)
        XCTAssertFalse(detail.flagConstraints.isEmpty)
        let effort = try XCTUnwrap(detail.flags.first(where: { $0.name == "effort" }))
        XCTAssertEqual(effort.allowedValues, ["low", "med", "high"])
        XCTAssertTrue(detail.mutuallyExclusiveFlags.contains(["json", "stream"]))
    }

    func testMenuActionsStayShortAndBudgetHolds() throws {
        let menu = MenuCatalog.project(teams: BuiltInTeams.all.filter { !$0.isLabTeam })
        XCTAssertLessThanOrEqual(menu.actions.count, 8, "do not expand actions for coverage ratio")
        let data = try MenuCatalog.encodeCompact(menu)
        XCTAssertLessThanOrEqual(data.count, 32768, "Tier-1 menu must stay ≤32 KiB")
    }

    func testHelpSearchResolvesStreamAndTemperature() {
        XCTAssertEqual(HelpTopicRegistry.canonicalTopicId(for: "stream"), "team_run_loop")
        XCTAssertEqual(HelpTopicRegistry.canonicalTopicId(for: "temperature"), "team_run_loop")
        XCTAssertEqual(HelpTopicRegistry.canonicalTopicId(for: "ndjson"), "team_run_loop")
        XCTAssertEqual(HelpTopicRegistry.canonicalTopicId(for: "answer field"), "team_run_loop")
        let hits = HelpService.search("stream", limit: 5)
        XCTAssertTrue(
            hits.results.contains(where: { $0.topicId == "team_run_loop" }),
            "HelpService.search(stream) should hit team_run_loop"
        )
    }
}
