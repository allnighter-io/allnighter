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
        workerId: String? = nil
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
    }
}
