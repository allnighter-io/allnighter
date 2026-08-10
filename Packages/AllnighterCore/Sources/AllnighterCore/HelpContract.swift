import Foundation

// Help System — H1/H2 contract envelopes + projector. `alln help …` calls
// `HelpProjector` so every caller (CLI, agents) projects the SAME shapes.
// Search (MR-S05) projects `MenuCatalog` cards; get/topics stay on HelpTopicRegistry.

public extension HelpService {
    /// The help-first routing law repeated on every help-aware surface (topic
    /// bodies, host-agent snippets). Selection truth is the live menu.
    static let routingLaw =
        "For Allnighter product questions, read `alln menu --json` first. Use `alln help search <query>` to retrieve matching menu cards, or `alln help get <topic>` for narrative topics — never answer selection from memory or a pasted catalog."

    /// Host-instruction preview when live binary path is unknown (help corpus only).
    static var hostInstructionBlock: String {
        Bootstrap.snippet(binaryPath: "alln", onPath: true)
    }
}

/// One ordered next step so host agents don't synthesize orchestration from prose.
/// Carries a full runnable `alln …` command (ASF-S02 — no tool-id grammar).
public struct HelpNextToolStep: Codable, Sendable, Equatable {
    public var order: Int
    public var command: String
    public var why: String
    public init(order: Int, command: String, why: String) {
        self.order = order; self.command = command; self.why = why
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
        if let ref {
            plan.append(HelpNextToolStep(
                order: 1,
                command: "alln help get --ref \(ref) --json",
                why: "Read the recovery topic."))
        }
        if spec.ruleId.hasPrefix("source.") {
            plan.append(HelpNextToolStep(
                order: plan.count + 1,
                command: "alln doctor --json",
                why: "Re-probe the affected source for live state."))
        }
        return ErrorExplainJSON(contractVersion: contractVersion, error: spec,
                                helpTopicId: topic?.id, helpRef: ref, nextToolPlan: plan)
    }
}

/// Pure builder of the help contract envelopes. Search projects `MenuCatalog`
/// plus exact HelpTopicRegistry alias hits (so "cursor ide" / "detect" land on
/// teaching topics, not only Cursor model cards). get/topics project the topic registry.
public enum HelpProjector {
    public static func search(
        _ query: String,
        limit: Int,
        contractVersion: String,
        menu: MenuJSON? = nil
    ) -> HelpSearchJSON {
        let phrase = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let menuHits = MenuCatalog.search(query, limit: limit, menu: menu)
        var results = menuHits.results

        // Exact topic/alias phrase → surface the guide card ahead of model noise.
        if let topicId = HelpTopicRegistry.canonicalTopicId(for: phrase),
           let topic = HelpTopicRegistry.topic(id: topicId) {
            let topicHit = MenuSearchHit(
                kind: "topic",
                ref: "help:\(topic.id)",
                id: topic.id,
                title: topic.title,
                useWhen: topic.summary,
                dontUseWhen: "Guide truth — call menu/doctor for this machine's live state",
                example: "alln help get \(topic.id)",
                validateExample: "alln help get \(topic.id) --json"
            )
            results.removeAll { $0.kind == "topic" && $0.id == topic.id }
            results.insert(topicHit, at: 0)
            if results.count > max(1, limit) {
                results = Array(results.prefix(max(1, limit)))
            }
        }

        return HelpSearchJSON(
            contractVersion: contractVersion,
            catalogRevision: menuHits.catalogRevision,
            query: menuHits.query,
            results: results
        )
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

    // MARK: - Plans (get/error only — search never recommends)

    private static func planForTopic(_ topic: HelpTopic?, found: Bool) -> [HelpNextToolStep] {
        guard found, let topic else {
            return [HelpNextToolStep(
                order: 1,
                command: "alln help search <query> --json",
                why: "Topic not found — search menu cards for the right one.")]
        }
        guard topic.needsLiveCheck else { return [] }
        let command: String
        if topic.relatedCommandNames.contains("doctor"),
           !topic.relatedCommandNames.contains("menu") {
            command = "alln doctor --json"
        } else {
            command = "alln menu --json"
        }
        return [HelpNextToolStep(
            order: 1,
            command: command,
            why: "This topic depends on this machine's live state.")]
    }
}
