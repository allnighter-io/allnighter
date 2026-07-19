import Foundation

// Help System — H1/H2 contract envelopes + projector. `alln help …` calls
// `HelpProjector` so every caller (CLI, agents) projects the SAME shapes over the
// same `HelpService`/`HelpTopicRegistry` SSOT. Allnighter is CLI-only for agents
// (docs/phases/MCP_Retirement.md) — there is no second wire format to keep in sync.

public extension HelpService {
    /// The help-first routing law repeated on every help-aware surface (topic
    /// bodies, `alln team hello`, host-agent snippets).
    static let routingLaw =
        "For Allnighter product questions, run `alln help search <query>` or `alln help get <topic>` before answering from memory."

    /// Companion workflow lines shared with the teaching snippet (ONB-S01).
    /// Trigger + markers live in `TeachingSnippet`; binary fallback/install are
    /// assembled by `Bootstrap.snippet(binaryPath:onPath:)`.
    static var bootstrapWorkflowLines: [String] { TeachingSnippet.companionLines }

    /// Static help-topic preview when live binary path is unknown (help corpus only).
    static var hostInstructionBlock: String {
        Bootstrap.snippet(binaryPath: "alln", onPath: true)
    }
}

/// One ordered next-tool call so host agents don't synthesize orchestration from prose.
/// ASF-S02 migrates `tool` → full runnable `command` strings; S01 leaves the field.
public struct HelpNextToolStep: Codable, Sendable, Equatable {
    public var order: Int
    public var tool: String
    public var args: [String: String]
    public var why: String
    public init(order: Int, tool: String, args: [String: String] = [:], why: String) {
        self.order = order; self.tool = tool; self.args = args; self.why = why
    }
}

public struct HelpSearchJSON: Codable, Sendable, Equatable {
    public var schemaVersion: Int
    public var contractVersion: String
    public var routingLaw: String
    public var query: String
    public var results: [HelpSearchHit]
    public var suggestedAnswerMarkdown: String?
    public var suggestedAnswerRefs: [String]
    public var nextToolPlan: [HelpNextToolStep]
    public init(schemaVersion: Int = 1, contractVersion: String, routingLaw: String, query: String,
                results: [HelpSearchHit], suggestedAnswerMarkdown: String?, suggestedAnswerRefs: [String],
                nextToolPlan: [HelpNextToolStep]) {
        self.schemaVersion = schemaVersion; self.contractVersion = contractVersion
        self.routingLaw = routingLaw; self.query = query; self.results = results
        self.suggestedAnswerMarkdown = suggestedAnswerMarkdown; self.suggestedAnswerRefs = suggestedAnswerRefs
        self.nextToolPlan = nextToolPlan
    }
}

public struct HelpGetJSON: Codable, Sendable, Equatable {
    public var schemaVersion: Int
    public var contractVersion: String
    public var routingLaw: String
    public var found: Bool
    public var topic: HelpTopic?
    public var selectedSectionId: String?
    public var closeMatches: [String]
    public var sitemap: [HelpSitemapEntry]
    public var nextToolPlan: [HelpNextToolStep]
    public init(schemaVersion: Int = 1, contractVersion: String, routingLaw: String, found: Bool,
                topic: HelpTopic?, selectedSectionId: String?, closeMatches: [String],
                sitemap: [HelpSitemapEntry], nextToolPlan: [HelpNextToolStep]) {
        self.schemaVersion = schemaVersion; self.contractVersion = contractVersion
        self.routingLaw = routingLaw; self.found = found; self.topic = topic
        self.selectedSectionId = selectedSectionId; self.closeMatches = closeMatches
        self.sitemap = sitemap; self.nextToolPlan = nextToolPlan
    }
}

public struct HelpTopicsJSON: Codable, Sendable, Equatable {
    public var schemaVersion: Int
    public var contractVersion: String
    public var routingLaw: String
    public var topics: [HelpSitemapEntry]
    public init(schemaVersion: Int = 1, contractVersion: String, routingLaw: String, topics: [HelpSitemapEntry]) {
        self.schemaVersion = schemaVersion; self.contractVersion = contractVersion
        self.routingLaw = routingLaw; self.topics = topics
    }
}

/// `error_explain` / `doctor explain` output, bridged to help: the catalog recovery
/// metadata PLUS the help topic that documents this error and a next-tool plan, so a
/// failed tool is one call away from recovery (no extra search).
public struct ErrorExplainJSON: Codable, Sendable, Equatable {
    public var schemaVersion: Int
    public var contractVersion: String
    public var error: ContractRegistry.ErrorSpec
    public var helpTopicId: String?
    public var helpRef: String?
    public var nextToolPlan: [HelpNextToolStep]
    public init(schemaVersion: Int = 1, contractVersion: String, error: ContractRegistry.ErrorSpec,
                helpTopicId: String?, helpRef: String?, nextToolPlan: [HelpNextToolStep]) {
        self.schemaVersion = schemaVersion; self.contractVersion = contractVersion
        self.error = error; self.helpTopicId = helpTopicId; self.helpRef = helpRef
        self.nextToolPlan = nextToolPlan
    }
}

public enum ErrorHelpBridge {
    /// Derive the help topic for an error from `HelpTopicRegistry` (no per-ErrorSpec
    /// hand-authoring) and build the recovery plan.
    public static func explain(_ spec: ContractRegistry.ErrorSpec, contractVersion: String) -> ErrorExplainJSON {
        let topic = HelpTopicRegistry.topics.first { $0.errorRefs.contains(spec.code) }
        let ref = topic.map { HelpRef.help($0.id) }
        var plan: [HelpNextToolStep] = []
        if let ref { plan.append(HelpNextToolStep(order: 1, tool: "help_get", args: ["ref": ref], why: "Read the recovery topic.")) }
        if spec.ruleId.hasPrefix("source.") {
            plan.append(HelpNextToolStep(order: plan.count + 1, tool: "doctor", why: "Re-probe the affected source for live state."))
        }
        return ErrorExplainJSON(contractVersion: contractVersion, error: spec,
                                helpTopicId: topic?.id, helpRef: ref, nextToolPlan: plan)
    }
}

/// Pure builder of the help contract envelopes (adds contractVersion + routing law +
/// next-tool plans over `HelpService`). No IO.
public enum HelpProjector {
    public static func search(_ query: String, limit: Int, contractVersion: String) -> HelpSearchJSON {
        let r = HelpService.search(query, limit: limit)
        return HelpSearchJSON(
            contractVersion: contractVersion, routingLaw: HelpService.routingLaw, query: r.query,
            results: r.results, suggestedAnswerMarkdown: r.suggestedAnswerMarkdown,
            suggestedAnswerRefs: r.suggestedAnswerRefs, nextToolPlan: planForSearch(r))
    }

    public static func get(topic: String? = nil, ref: String? = nil,
                           error: String? = nil, contractVersion: String) -> HelpGetJSON {
        let r = HelpService.get(topic: topic, ref: ref, error: error)
        return HelpGetJSON(
            contractVersion: contractVersion, routingLaw: HelpService.routingLaw, found: r.found,
            topic: r.topic, selectedSectionId: r.selectedSectionId, closeMatches: r.closeMatches,
            sitemap: r.sitemap, nextToolPlan: planForTopic(r.topic, found: r.found))
    }

    public static func topics(contractVersion: String) -> HelpTopicsJSON {
        HelpTopicsJSON(contractVersion: contractVersion, routingLaw: HelpService.routingLaw,
                       topics: HelpService.sitemap())
    }

    // MARK: - Plans

    private static func planForSearch(_ r: HelpSearchResult) -> [HelpNextToolStep] {
        guard let top = r.results.first else { return [] }
        var steps = [HelpNextToolStep(order: 1, tool: "help_get",
                                      args: ["topic": top.topicId, "detail": "machine"],
                                      why: "Retrieve the full topic, decision table, and refs.")]
        if top.needsLiveCheck {
            steps.append(HelpNextToolStep(order: 2, tool: "team_hello",
                                          why: "This answer depends on local readiness — check live state."))
        }
        return steps
    }

    private static func planForTopic(_ topic: HelpTopic?, found: Bool) -> [HelpNextToolStep] {
        guard found, let topic else {
            return [HelpNextToolStep(order: 1, tool: "help_search",
                                     why: "Topic not found — search for the right one.")]
        }
        guard topic.needsLiveCheck else { return [] }
        // Live-state topics route to a live command rather than pretend to know.
        // Prefer `team hello` when listed; otherwise `doctor`. (ASF-S02 replaces `tool`.)
        let liveTool: String
        if topic.relatedCommandNames.contains("team hello") {
            liveTool = "team_hello"
        } else if topic.relatedCommandNames.contains("doctor") {
            liveTool = "doctor"
        } else {
            liveTool = "team_hello"
        }
        return [HelpNextToolStep(order: 1, tool: liveTool,
                                 why: "This topic depends on this machine's live state.")]
    }
}
