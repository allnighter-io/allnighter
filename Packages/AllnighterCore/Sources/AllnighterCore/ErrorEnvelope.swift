import Foundation

/// The shared structured-error envelope
/// (docs/phases/CLI_Implementation_Contract.md §Error Envelope).
///
/// One shape, reused everywhere a failure can surface: JSON-mode `errors`,
/// `TeamRunJSON.AnswerInfo.error` (a failed worker is shown failed, never
/// hidden), NDJSON `error.error`, and `DoctorResult` fixes. Every emitted `code`
/// must carry default `agentAction`/`requiresManual`/`retryable`/doctor-explain
/// text in the contract registry before it can be emitted.
public struct ErrorEnvelope: Codable, Equatable, Sendable {
    public var code: String
    public var ruleId: String?
    public var message: String
    public var agentAction: String?
    public var fixCommand: String?
    public var requiresManual: Bool
    public var retryable: Bool
    public var traceId: String?
    public var runId: String?
    public var sourceId: String?
    public var modelId: String?
    public var workerId: String?
    /// Effective `ALLNIGHTER_SUPPORT_DIR` at the time of a not-found / kill
    /// failure (RLR-L1). Set on `RUN_NOT_FOUND` so a machine caller can see which
    /// support root was searched (RCA class 5 — wrong/isolated config home).
    public var supportDir: String?
    /// Top near-match ids (AE-S07). Suggestion-only — never auto-dispatched.
    public var suggestions: [String]
    /// MR-S04: same-kind candidates with id / displayName / driver / state.
    public var candidates: [ExactIdResolver.Candidate]
    /// Discovery next action for the failed noun (AE-S07).
    public var nextAction: AgentNextAction?

    public init(
        code: String,
        ruleId: String? = nil,
        message: String,
        agentAction: String? = nil,
        fixCommand: String? = nil,
        requiresManual: Bool,
        retryable: Bool,
        traceId: String? = nil,
        runId: String? = nil,
        sourceId: String? = nil,
        modelId: String? = nil,
        workerId: String? = nil,
        supportDir: String? = nil,
        suggestions: [String] = [],
        candidates: [ExactIdResolver.Candidate] = [],
        nextAction: AgentNextAction? = nil
    ) {
        self.code = code
        self.ruleId = ruleId
        self.message = message
        self.agentAction = agentAction
        self.fixCommand = fixCommand
        self.requiresManual = requiresManual
        self.retryable = retryable
        self.traceId = traceId
        self.runId = runId
        self.sourceId = sourceId
        self.modelId = modelId
        self.workerId = workerId
        self.supportDir = supportDir
        self.suggestions = suggestions
        self.candidates = candidates
        self.nextAction = nextAction ?? ErrorDiscovery.nextAction(forErrorCode: code)
    }

    private enum CodingKeys: String, CodingKey {
        case code, ruleId, message, agentAction, fixCommand, requiresManual, retryable
        case traceId, runId, sourceId, modelId, workerId, supportDir, suggestions, candidates, nextAction
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        code = try c.decode(String.self, forKey: .code)
        ruleId = try c.decodeIfPresent(String.self, forKey: .ruleId)
        message = try c.decode(String.self, forKey: .message)
        agentAction = try c.decodeIfPresent(String.self, forKey: .agentAction)
        fixCommand = try c.decodeIfPresent(String.self, forKey: .fixCommand)
        requiresManual = try c.decode(Bool.self, forKey: .requiresManual)
        retryable = try c.decode(Bool.self, forKey: .retryable)
        traceId = try c.decodeIfPresent(String.self, forKey: .traceId)
        runId = try c.decodeIfPresent(String.self, forKey: .runId)
        sourceId = try c.decodeIfPresent(String.self, forKey: .sourceId)
        modelId = try c.decodeIfPresent(String.self, forKey: .modelId)
        workerId = try c.decodeIfPresent(String.self, forKey: .workerId)
        supportDir = try c.decodeIfPresent(String.self, forKey: .supportDir)
        suggestions = try c.decodeIfPresent([String].self, forKey: .suggestions) ?? []
        candidates = try c.decodeIfPresent([ExactIdResolver.Candidate].self, forKey: .candidates) ?? []
        nextAction = try c.decodeIfPresent(AgentNextAction.self, forKey: .nextAction)
            ?? ErrorDiscovery.nextAction(forErrorCode: code)
    }
}
