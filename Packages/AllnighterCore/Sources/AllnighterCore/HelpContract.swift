import Foundation

// MCP Help System — H1/H2 contract envelopes + projector. `alln help …` and the MCP
// help tools both call `HelpProjector` so the CLI and MCP project the SAME shapes over
// the same `HelpService`/`HelpTopicRegistry` SSOT.

public extension HelpService {
    /// The help-first routing law repeated on every help-aware surface (tool
    /// descriptions, mcp_hello, install snippets).
    static let routingLaw =
        "For Allnighter product questions, call help_search/help_get before answering from memory."
}

/// One ordered next-tool call so host agents don't synthesize orchestration from prose.
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

    public static func get(topic: String? = nil, ref: String? = nil, tool: String? = nil,
                           error: String? = nil, contractVersion: String) -> HelpGetJSON {
        let r = HelpService.get(topic: topic, ref: ref, tool: tool, error: error)
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
            steps.append(HelpNextToolStep(order: 2, tool: "mcp_hello",
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
        // Live-state topics route to the live tool rather than pretend to know.
        let liveTool = topic.relatedToolIds.first { $0 == "mcp_hello" || $0 == "doctor" } ?? "mcp_hello"
        return [HelpNextToolStep(order: 1, tool: liveTool,
                                 why: "This topic depends on this machine's live state.")]
    }
}
