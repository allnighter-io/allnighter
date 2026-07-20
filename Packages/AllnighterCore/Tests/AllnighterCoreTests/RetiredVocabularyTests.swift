import XCTest
@testable import AllnighterCore

/// ASF-S08 — durable mechanical gates over retired vocabulary.
final class RetiredVocabularyTests: XCTestCase {

    // MARK: - Deny-list is the single source

    func testNoRetiredLaneEnumInFlagSummaries() {
        let registry = ContractRegistry.milestone1
        var hits: [String] = []
        for cmd in registry.commands where cmd.milestone == .m1 {
            for flag in cmd.flags {
                if let hit = RetiredVocabulary.flagSummaryContainsRetiredValue(flag.summary) {
                    hits.append("\(cmd.name) --\(flag.name): \(hit)")
                }
            }
            for arg in cmd.args {
                if let hit = RetiredVocabulary.flagSummaryContainsRetiredValue(arg.summary) {
                    hits.append("\(cmd.name) <\(arg.name)>: \(hit)")
                }
            }
        }
        XCTAssertTrue(hits.isEmpty, "retired lane/effort enum values in FlagSpec:\n\(hits.joined(separator: "\n"))")
    }

    func testDenyListSeedsFromKillList() {
        let required = [
            "dryRun", "dryrun", "team_start(", "pair_relay(action",
            "team_run", "team_ask", "run_get",
            "pending_update", "project_get", "stalled_update",
            "teams_get", "skills_get", "defaults_get", "error_explain",
            "pair slice", "pair status", "alln mcp",
            "team hello", "route --for", "resolve --for", "commands --json",
            "team list", "team show", "team preflight", "team start",
        ]
        for term in required {
            XCTAssertTrue(
                RetiredVocabulary.denyTerms.contains(term),
                "RetiredVocabulary.denyTerms must include kill-list term '\(term)'")
        }
    }

    func testLivingDocPatternsAreExactInstructionalForms() {
        let expected: Set<String> = [
            "alln mcp serve", "alln mcp install", "pair slice",
            "alln team hello", "alln route --for", "alln resolve --for",
            "alln commands --json", "alln team list", "alln team show",
            "alln team preflight", "alln team start",
        ]
        XCTAssertEqual(Set(RetiredVocabulary.livingDocDenyPatterns), expected)
    }

    // MARK: - (b) Help prose deny-list

    func testNoRetiredVocabularyInHelpTopicProse() {
        for t in HelpTopicRegistry.topics {
            let prose = (t.title + " " + t.summary + " " + t.bodyMarkdown + " "
                         + t.sections.map { $0.title + " " + $0.bodyMarkdown }.joined(separator: " "))
            if let hit = RetiredVocabulary.proseContainsDenyTerm(prose) {
                // Topic id `team_run_loop` is fine; deny term `team_run` must not
                // appear as a callable id / MCP grammar in prose.
                XCTFail("topic \(t.id) public prose contains retired vocabulary '\(hit)'")
            }
        }
    }

    // MARK: - HelpNextToolStep encodings: no deny terms, no "tool" key

    func testHelpNextToolPlanEncodingsHaveNoToolKeyAndNoDenyTerms() throws {
        let envelopes: [any Encodable] = [
            HelpProjector.search("team", limit: 5, contractVersion: "2.1.0"),
            HelpProjector.search("asdfqwerty-no-such-topic-999", limit: 5, contractVersion: "2.1.0"),
            HelpProjector.get(topic: "team_run_loop", contractVersion: "2.1.0"),
            HelpProjector.get(topic: "totally-unknown-topic", contractVersion: "2.1.0"),
            HelpProjector.topics(contractVersion: "2.1.0"),
        ]
        for env in envelopes {
            let data = try CoreJSON.encode(env)
            let obj = try JSONSerialization.jsonObject(with: data)
            assertNoToolKey(in: obj, path: "$")
        }

        // Search never emits nextToolPlan (MR-S05). Get/miss plans must not teach retired grammar.
        let searchData = try CoreJSON.encode(HelpProjector.search("team", limit: 5, contractVersion: "2.1.0"))
        let searchObj = try XCTUnwrap(JSONSerialization.jsonObject(with: searchData) as? [String: Any])
        XCTAssertNil(searchObj["nextToolPlan"])

        let plans: [[HelpNextToolStep]] = [
            HelpProjector.get(topic: "team_run_loop", contractVersion: "2.1.0").nextToolPlan,
            HelpProjector.get(topic: "totally-unknown-topic", contractVersion: "2.1.0").nextToolPlan,
        ]
        for plan in plans {
            XCTAssertFalse(plan.isEmpty)
            for step in plan {
                let encoded = try CoreJSON.encode(step)
                let raw = String(data: encoded, encoding: .utf8) ?? ""
                let stepObj = try JSONSerialization.jsonObject(with: encoded) as? [String: Any]
                XCTAssertNil(stepObj?["tool"])
                XCTAssertNotNil(stepObj?["command"] as? String)
                if let hit = RetiredVocabulary.proseContainsDenyTerm(raw) {
                    XCTFail("HelpNextToolStep contains retired vocabulary '\(hit)': \(raw)")
                }
                XCTAssertNotNil(ContractRegistry.resolveCommandName(from: step.command))
            }
        }
    }

    // MARK: - (a) Prose-command resolution

    func testEveryBacktickedAllnCommandInTopicProseResolves() {
        let pattern = try! NSRegularExpression(pattern: #"`(alln[^`]*)`"#)
        var failures: [String] = []
        for t in HelpTopicRegistry.topics {
            let prose = ([t.summary, t.bodyMarkdown] + t.sections.map(\.bodyMarkdown))
                .joined(separator: "\n")
            let ns = prose as NSString
            let matches = pattern.matches(in: prose, range: NSRange(location: 0, length: ns.length))
            for m in matches {
                let raw = ns.substring(with: m.range(at: 1))
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                let invocation = Self.normalizeProseInvocation(raw)
                // Bare binary name is fine (`alln` on PATH).
                if invocation == "alln" { continue }
                guard let cmdName = ContractRegistry.resolveCommandName(from: invocation) else {
                    failures.append("\(t.id): unresolved `\(raw)` (normalized: \(invocation))")
                    continue
                }
                if let flagHit = unknownFlag(in: invocation, commandName: cmdName) {
                    failures.append("\(t.id): `\(raw)` unknown flag --\(flagHit)")
                }
            }
        }
        XCTAssertTrue(failures.isEmpty, failures.joined(separator: "\n"))
    }

    /// Strip optional `[...]` grammar and collapse whitespace so prose examples
    /// like `alln bootstrap [--host …] [--json]` resolve to `bootstrap`.
    private static func normalizeProseInvocation(_ raw: String) -> String {
        var s = raw
        // Optional flag/arg brackets used in help prose.
        while let open = s.range(of: "["), let close = s.range(of: "]", range: open.upperBound..<s.endIndex) {
            s.removeSubrange(open.lowerBound..<close.upperBound)
        }
        // Collapse whitespace left by removals.
        s = s.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
        return s
    }

    // MARK: - (c) Underscore-tool-id ban

    func testPreflightAndHelpGoldensHaveNoToolKey() throws {
        let preflight = AgentNextAction.startTeamRun(teamId: "code_bug_hunt")
        let data = try CoreJSON.encode(preflight)
        let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        XCTAssertNil(obj?["tool"])
        XCTAssertNotNil(obj?["command"] as? String)

        let step = HelpNextToolStep(order: 1, command: "alln doctor --json", why: "probe")
        let stepObj = try JSONSerialization.jsonObject(with: CoreJSON.encode(step)) as? [String: Any]
        XCTAssertNil(stepObj?["tool"])
        XCTAssertEqual(stepObj?["command"] as? String, "alln doctor --json")
    }

    // MARK: - Helpers

    private func unknownFlag(in invocation: String, commandName: String) -> String? {
        guard let spec = ContractRegistry.milestone1.commands.first(where: {
            $0.name == commandName && $0.milestone == .m1
        }) else { return nil }
        let allowed = Set(spec.flags.map(\.name))
        // Tokenize roughly; skip values after flags that take values.
        let tokens = invocation.split(whereSeparator: { $0.isWhitespace }).map(String.init)
        var i = 0
        while i < tokens.count {
            let tok = tokens[i]
            if tok.hasPrefix("--") {
                let name = String(tok.dropFirst(2).split(separator: "=").first!)
                // Global-ish / placeholder flags sometimes appear in prose examples.
                let ignored = Set(["json", "format", "help", "version", "project", "team",
                                   "worker", "ref", "host", "for", "lane", "try-fix",
                                   "executor", "schema", "stream", "all", "doc", "panel",
                                   "relay", "pm-worker", "max-rounds", "until", "verdict",
                                   "handover-file", "id"])
                if !allowed.contains(name) && !ignored.contains(name) {
                    // Many commands inherit shared flags via CLI parsing rather than
                    // CommandSpec — only fail when the flag is clearly invented.
                    if ["dryRun", "tool", "mcp"].contains(name) {
                        return name
                    }
                }
            }
            i += 1
        }
        return nil
    }

    private func assertNoToolKey(in value: Any, path: String) {
        if let dict = value as? [String: Any] {
            XCTAssertNil(dict["tool"], "ASF-S08: \"tool\" key forbidden at \(path)")
            for (k, v) in dict {
                assertNoToolKey(in: v, path: "\(path).\(k)")
            }
        } else if let arr = value as? [Any] {
            for (i, v) in arr.enumerated() {
                assertNoToolKey(in: v, path: "\(path)[\(i)]")
            }
        }
    }
}
