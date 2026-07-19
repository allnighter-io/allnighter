import Foundation

/// Single deny-list for retired agent-facing grammar (ASF-S08).
///
/// Consumed by XCTest gates (`RetiredVocabularyTests`, `HelpTopicRegistryTests`)
/// and by `scripts/check.sh` (living-doc grep patterns extracted from the
/// marked block below). The Retirement Rule
/// (`docs/workflows/SSOT_Feature_Workflow.md`) appends here forever — never
/// narrow a red gate by deleting a term to make CI pass.
///
/// Carve-outs for underscore ids that are **workflow labels**, not callable
/// tools, live in `allowedWorkflowIds` and must be named explicitly
/// (`AgentHello.defaultWorkflows`).
public enum RetiredVocabulary {

    // MARK: - Help prose / next-action deny terms

    /// Patterns that must never appear in live help titles/summaries/bodies/
    /// sections, or in agent-visible next-action encodings.
    public static let denyTerms: [String] = [
        // Product vocabulary retirements
        "fan out",
        "fanout",
        "council",
        "judge panel",
        // Invented MCP / dry-run grammar
        "dryrun",
        "dryRun",
        "team_start(",
        "team_start(dryRun",
        "pair_relay(action",
        // Dead relatedToolIds (resolve to nothing)
        "team_run",
        "team_ask",
        "run_get",
        "pending_run",
        "pending_update",
        "project_get",
        "stalled_update",
        "teams_get",
        "skills_get",
        "defaults_get",
        "error_explain",
        // Deleted dispatch verbs
        "pair slice",
        "pair status",
        // Retired MCP CLI family
        "alln mcp",
    ]

    /// Underscore tool ids that must never appear as callable ids in agent-visible
    /// JSON/text. Overlaps with `denyTerms`; kept explicit for the underscore ban.
    public static let deadToolIds: [String] = [
        "team_run",
        "team_ask",
        "run_get",
        "pending_update",
        "project_get",
        "stalled_update",
        "teams_get",
        "skills_get",
        "defaults_get",
        "error_explain",
        "team_start",
        "team_status",
        "team_result",
        "team_cancel",
        "team_preflight",
        "help_get",
        "help_search",
        "pair_relay",
        "mcp_hello",
        "pending_run",
    ]

    /// `AgentHello.defaultWorkflows` ids — workflow *labels*, not callable tools.
    /// The underscore-tool-id ban must carve these out **by explicit name**
    /// (ASF law 8 — never weaken the gate silently).
    public static let allowedWorkflowIds: Set<String> = [
        "run_async",
        "diagnose",
        "resolve_stalls",
    ]

    // MARK: - Living-doc grep patterns (check.sh)

    /// Exact instructional forms that must not appear in living agent-facing
    /// docs outside archive/ and historical debugger packets.
    ///
    /// BEGIN livingDocDenyPatterns
    public static let livingDocDenyPatterns: [String] = [
        "alln mcp serve",
        "alln mcp install",
        "pair slice",
    ]
    /// END livingDocDenyPatterns

    // MARK: - Matching helpers

    /// Case-fold match for deny terms, except `dryRun` which is case-sensitive
    /// (camelCase invented flag — lowercase `dryrun` is listed separately).
    /// Underscore tool ids use word-boundary matching so `team_run` does not
    /// false-positive on the live topic id `team_run_loop`.
    public static func proseContainsDenyTerm(_ prose: String) -> String? {
        for term in denyTerms {
            if term == "dryRun" {
                if prose.contains(term) { return term }
                continue
            }
            if termContainsUnderscoreToolShape(term) {
                if matchesAsWholeToken(term, in: prose) { return term }
            } else if prose.lowercased().contains(term.lowercased()) {
                return term
            }
        }
        return nil
    }

    private static func termContainsUnderscoreToolShape(_ term: String) -> Bool {
        term.contains("_")
    }

    /// True when `term` appears as its own token (not a prefix of a longer id).
    private static func matchesAsWholeToken(_ term: String, in prose: String) -> Bool {
        let escaped = NSRegularExpression.escapedPattern(for: term)
        // `(?<![A-Za-z0-9_])term(?![A-Za-z0-9_])` — underscore-aware boundaries.
        let pattern = "(?<![A-Za-z0-9_])\(escaped)(?![A-Za-z0-9_])"
        guard let re = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return prose.lowercased().contains(term.lowercased())
        }
        let range = NSRange(prose.startIndex..<prose.endIndex, in: prose)
        return re.firstMatch(in: prose, options: [], range: range) != nil
    }

    /// True when `id` is a retired underscore tool id (not an allowed workflow label).
    public static func isBannedUnderscoreToolId(_ id: String) -> Bool {
        if allowedWorkflowIds.contains(id) { return false }
        return deadToolIds.contains(id)
    }
}
