import Foundation

/// How strongly a panel agrees on a point.
public enum AnalysisStrength: String, Codable, Sendable, CaseIterable {
    case strong
    case moderate
    case weak
}

/// One analyzed point, attributed to the seats that raised it.
public struct AnalysisPoint: Codable, Sendable, Equatable {
    public var statement: String
    public var sourceAgentIds: [String]
    public var strength: AnalysisStrength?

    public init(statement: String, sourceAgentIds: [String] = [], strength: AnalysisStrength? = nil) {
        self.statement = statement
        self.sourceAgentIds = sourceAgentIds
        self.strength = strength
    }
}

/// A genuine disagreement among seats, plus the judge's recommended resolution.
public struct Contradiction: Codable, Sendable, Equatable {
    public struct Position: Codable, Sendable, Equatable {
        public var agentId: String
        public var summary: String
        public init(agentId: String, summary: String) {
            self.agentId = agentId
            self.summary = summary
        }
    }
    public var topic: String
    public var positions: [Position]
    public var recommendedResolution: String

    public init(topic: String, positions: [Position] = [], recommendedResolution: String) {
        self.topic = topic
        self.positions = positions
        self.recommendedResolution = recommendedResolution
    }
}

/// What one seat addressed vs stayed silent on.
public struct CoverageNote: Codable, Sendable, Equatable {
    public var agentId: String
    public var addressed: [String]
    public var silentOn: [String]

    public init(agentId: String, addressed: [String] = [], silentOn: [String] = []) {
        self.agentId = agentId
        self.addressed = addressed
        self.silentOn = silentOn
    }
}

/// A seat that did not return a usable answer (honest, never hidden).
public struct WorkerFailure: Codable, Sendable, Equatable {
    public var agentId: String
    public var reason: String
    public init(agentId: String, reason: String) {
        self.agentId = agentId
        self.reason = reason
    }
}

/// The judge's structured analysis of the panel — the Fusion-grade lever, stored
/// as data (Markdown is derived). Produced by the `analysis` reduce stage.
public struct PlanAnalysis: Codable, Sendable, Equatable {
    public var consensus: [AnalysisPoint]
    public var contradictions: [Contradiction]
    public var partialCoverage: [CoverageNote]
    public var uniqueInsights: [AnalysisPoint]
    public var blindSpots: [String]
    public var failedWorkers: [WorkerFailure]
    public var confidenceNote: String?

    public init(
        consensus: [AnalysisPoint] = [],
        contradictions: [Contradiction] = [],
        partialCoverage: [CoverageNote] = [],
        uniqueInsights: [AnalysisPoint] = [],
        blindSpots: [String] = [],
        failedWorkers: [WorkerFailure] = [],
        confidenceNote: String? = nil
    ) {
        self.consensus = consensus
        self.contradictions = contradictions
        self.partialCoverage = partialCoverage
        self.uniqueInsights = uniqueInsights
        self.blindSpots = blindSpots
        self.failedWorkers = failedWorkers
        self.confidenceNote = confidenceNote
    }

    public var isEmpty: Bool {
        consensus.isEmpty && contradictions.isEmpty && partialCoverage.isEmpty
            && uniqueInsights.isEmpty && blindSpots.isEmpty
    }
}
