import Foundation

// MARK: - Signal Insight (docs/phases/Team_Run_Floor.md §Signal Insight)

/// The typed output of a Signal team — a Project-aware interpretation of public
/// outside-world change, separate from generic plan markdown. Observed facts are
/// kept distinct from inference; "no move today" is a valid, complete Insight.
public struct SignalInsight: Codable, Sendable, Equatable {
    /// Whether the opportunity window is still open. `uncertain` when it cannot be
    /// determined — never guessed.
    public enum Window: String, Codable, Sendable, CaseIterable {
        case open, closing, closed, uncertain
    }

    public struct Freshness: Codable, Sendable, Equatable {
        public enum Status: String, Codable, Sendable, CaseIterable { case fresh, stale, uncertain }
        public var observedAt: Date
        public var newestSourceAt: Date?
        public var oldestSourceAt: Date?
        public var status: Status
        public init(observedAt: Date, newestSourceAt: Date? = nil, oldestSourceAt: Date? = nil, status: Status) {
            self.observedAt = observedAt; self.newestSourceAt = newestSourceAt
            self.oldestSourceAt = oldestSourceAt; self.status = status
        }
    }

    public struct SkepticPass: Codable, Sendable, Equatable {
        public enum Verdict: String, Codable, Sendable, CaseIterable { case pass, caution, reject, uncertain }
        public var verdict: Verdict
        public var reason: String
        public var saturationRisk: Bool?
        public var ownedByAnotherAccount: Bool?
        public init(verdict: Verdict, reason: String, saturationRisk: Bool? = nil, ownedByAnotherAccount: Bool? = nil) {
            self.verdict = verdict; self.reason = reason
            self.saturationRisk = saturationRisk; self.ownedByAnotherAccount = ownedByAnotherAccount
        }
    }

    public var title: String
    public var summary: String
    public var whatHappened: String
    public var whyItMatters: String
    public var whyThisProject: String
    public var window: Window
    public var freshness: Freshness
    public var internalLessons: [String]
    public var externalProductIdeas: [String]
    public var skepticPass: SkepticPass
    public var receipts: [SignalReceipt]
    public var recommendedNextActionId: String?

    public init(title: String, summary: String, whatHappened: String, whyItMatters: String,
                whyThisProject: String, window: Window, freshness: Freshness,
                internalLessons: [String] = [], externalProductIdeas: [String] = [],
                skepticPass: SkepticPass, receipts: [SignalReceipt] = [],
                recommendedNextActionId: String? = nil) {
        self.title = title; self.summary = summary; self.whatHappened = whatHappened
        self.whyItMatters = whyItMatters; self.whyThisProject = whyThisProject
        self.window = window; self.freshness = freshness
        self.internalLessons = internalLessons; self.externalProductIdeas = externalProductIdeas
        self.skepticPass = skepticPass; self.receipts = receipts
        self.recommendedNextActionId = recommendedNextActionId
    }

    private enum CodingKeys: String, CodingKey {
        case title, summary, whatHappened, whyItMatters, whyThisProject, window, freshness
        case internalLessons, externalProductIdeas, skepticPass, receipts, recommendedNextActionId
    }
    // Tolerant decode for parsing model output: list fields default to empty when
    // the writer omits them. Core fields (title/window/freshness/skepticPass) are
    // required — an incomplete block parses to nil and the markdown still renders.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        title = try c.decode(String.self, forKey: .title)
        summary = try c.decode(String.self, forKey: .summary)
        whatHappened = try c.decode(String.self, forKey: .whatHappened)
        whyItMatters = try c.decode(String.self, forKey: .whyItMatters)
        whyThisProject = try c.decode(String.self, forKey: .whyThisProject)
        window = try c.decode(Window.self, forKey: .window)
        freshness = try c.decode(Freshness.self, forKey: .freshness)
        internalLessons = try c.decodeIfPresent([String].self, forKey: .internalLessons) ?? []
        externalProductIdeas = try c.decodeIfPresent([String].self, forKey: .externalProductIdeas) ?? []
        skepticPass = try c.decode(SkepticPass.self, forKey: .skepticPass)
        receipts = try c.decodeIfPresent([SignalReceipt].self, forKey: .receipts) ?? []
        recommendedNextActionId = try c.decodeIfPresent(String.self, forKey: .recommendedNextActionId)
    }
}

/// One source receipt behind an Insight. Distinguishes observed facts from model
/// inference; public sources only (protected/private data is out of scope).
public struct SignalReceipt: Codable, Sendable, Equatable, Identifiable {
    public enum SourceKind: String, Codable, Sendable, CaseIterable {
        case xPost, xThread, article, releaseNote, repo, other
    }
    public enum EvidenceRole: String, Codable, Sendable, CaseIterable {
        case primary, corroborating, counterSignal, saturation, skeptic
    }
    public var id: String
    public var sourceKind: SourceKind
    public var url: String?
    public var sourceId: String?
    public var authorOrPublisher: String?
    public var observedAt: Date
    public var publishedAt: Date?
    public var title: String?
    public var snippet: String?
    public var relevance: String
    public var evidenceRole: EvidenceRole
    public var artifactRef: String?

    public init(id: String, sourceKind: SourceKind, url: String? = nil, sourceId: String? = nil,
                authorOrPublisher: String? = nil, observedAt: Date, publishedAt: Date? = nil,
                title: String? = nil, snippet: String? = nil, relevance: String,
                evidenceRole: EvidenceRole, artifactRef: String? = nil) {
        self.id = id; self.sourceKind = sourceKind; self.url = url; self.sourceId = sourceId
        self.authorOrPublisher = authorOrPublisher; self.observedAt = observedAt
        self.publishedAt = publishedAt; self.title = title; self.snippet = snippet
        self.relevance = relevance; self.evidenceRole = evidenceRole; self.artifactRef = artifactRef
    }
}

// MARK: - Parsing the writer's structured block

public enum SignalInsightParser {
    /// Best-effort extraction of a typed `SignalInsight` from the Insight Writer's
    /// markdown. The writer is instructed to append a fenced
    /// ```signal-insight … ``` JSON block; we parse and validate it. Returns `nil`
    /// when no valid block is present — the markdown still renders, so the Floor
    /// degrades gracefully rather than fabricating structure.
    public static func parse(fromWriterOutput markdown: String?) -> SignalInsight? {
        guard let markdown, let json = fencedBlock(in: markdown, fence: "signal-insight") else { return nil }
        return try? CoreJSON.decode(SignalInsight.self, from: Data(json.utf8))
    }

    /// Extract the contents of the first ```<fence> … ``` code block (shared helper).
    static func fencedBlock(in text: String, fence: String) -> String? {
        FencedBlock.extract(from: text, fence: fence)
    }
}
