import Foundation

/// Single deny-list for retired agent-facing grammar (ASF-S08).
///
/// Consumed by XCTest gates (`RetiredVocabularyTests`, `HelpTopicRegistryTests`)
/// and by `scripts/check.sh` (living-doc grep patterns extracted from the
/// marked block below). The Retirement Rule
/// (`docs/workflows/SSOT_Feature_Workflow.md`) appends here forever — never
/// narrow a red gate by deleting a term to make CI pass.
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
        "--worker",
        "--dev-worker",
        "--pm-worker",
        "alln project workers",
        "edit worker",
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
        // MR-S02 — router + duplicate grammars (delete, not alias)
        "team hello",
        "route --for",
        "resolve --for",
        "commands --json",
        "team list",
        "team show",
        "team preflight",
        "team start",
        "recommended.command",
        "USE THIS FIRST",
        // ADP-S04 — a command summary must never name a verb that does not
        // exist ("teams new" carried "Not an alias for teams create" — there
        // is no `teams create`). A caller reading the false negative can
        // conclude the named verb exists, just unreachable from here.
        "not an alias for",
        // RSC-S05 — phantom grammar: this flag was never real CLI grammar (the
        // shipped detached-dispatch flag is `--no-wait`, RSC-S04). Deny-listed so
        // it can never be re-taught in prose/next-actions; still fine as a
        // discovery-only HelpTopic alias pointing callers at the real flag.
        "--detach",
        // Agent vocabulary retirement (2026-07-28): roster seats are agents; CLI pin is --model.
        "--worker",
        "--dev-worker",
        "--pm-worker",
        "edit worker",
        "alln project workers",
        "project recheck-workers",
        // WTA-S06 — retired JSON wire keys (do not teach in help/recipes)
        "\"workerAnswers\"",
        "\"producedByWorkerId\"",
        "\"devWorkerId\"",
        "\"pmWorkerId\"",
        "\"defaultWorkerId\"",
        "\"leadWorkerId\"",
        "\"rejectedWorkerIds\"",
        "\"sourceWorkerIds\"",
        // LVC-S01 — relay/pilot vocabulary retired in favor of `alln loop`
        "pair relay",
        "pair relay-status",
        "pair relay-resume",
        "pair pilot",
        "relay adopt",
        "--relay",
        "--pm-model",
        "--dev-model",
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

    // MARK: - Living-doc grep patterns (check.sh)

    /// Exact instructional forms that must not appear in living agent-facing
    /// docs outside archive/ and historical debugger packets.
    ///
    /// BEGIN livingDocDenyPatterns
    public static let livingDocDenyPatterns: [String] = [
        "alln mcp serve",
        "alln mcp install",
        "pair slice",
        "alln team hello",
        "alln route --for",
        "alln resolve --for",
        "alln commands --json",
        "alln team list",
        "alln team show",
        "alln team preflight",
        "alln team start",
        "alln run --worker",
        "alln project workers",
        "alln pair relay",
        "alln pair relay-status",
        "alln pair relay-resume",
        "alln pair pilot",
        "alln relay adopt",
    ]
    /// END livingDocDenyPatterns

    // MARK: - Enumerated flag-value deny (AE-S06)

    /// Phrases that must never appear in `FlagSpec.summary` / `ArgSpec.summary`
    /// (generated docs teach these as enum values). Extends ASF deny-list from
    /// command names to enumerated flag values.
    public static let retiredFlagValuePhrases: [String] = [
        "build | design | copy",
        "build|design|copy",
        "build | design | copy |",
    ]

    /// First retired flag-value phrase found in `text`, or nil.
    public static func flagSummaryContainsRetiredValue(_ text: String) -> String? {
        let lower = text.lowercased()
        for phrase in retiredFlagValuePhrases {
            if lower.contains(phrase.lowercased()) { return phrase }
        }
        // Lone dead lane token when presented as an enum alternative.
        if lower.contains("build |") || lower.contains("| build") || lower.contains("|build|") {
            return "build (as lane enum)"
        }
        return nil
    }

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

    /// True when `id` is a retired underscore tool id.
    public static func isBannedUnderscoreToolId(_ id: String) -> Bool {
        deadToolIds.contains(id)
    }
}
