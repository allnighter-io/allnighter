import Foundation

/// The exact prompt sent to one worker.
public struct WorkerPrompt: Codable, Sendable, Equatable {
    public var workerId: String
    public var modelId: String
    public var text: String

    public init(workerId: String, modelId: String, text: String) {
        self.workerId = workerId
        self.modelId = modelId
        self.text = text
    }
}

/// One worker's output from a team run.
public struct WorkerAnswer: Codable, Sendable, Equatable, Identifiable {
    public var workerId: String
    public var modelId: String
    public var status: WorkerAnswerStatus
    public var output: String?
    public var errorKind: WorkerAnswerErrorKind?
    public var errorReason: String?
    public var startedAt: Date?
    public var finishedAt: Date?
    public var durationMs: Int?
    public var exitCode: Int?

    public var id: String { workerId }

    public init(
        workerId: String,
        modelId: String,
        status: WorkerAnswerStatus = .queued,
        output: String? = nil,
        errorKind: WorkerAnswerErrorKind? = nil,
        errorReason: String? = nil,
        startedAt: Date? = nil,
        finishedAt: Date? = nil,
        durationMs: Int? = nil,
        exitCode: Int? = nil
    ) {
        self.workerId = workerId
        self.modelId = modelId
        self.status = status
        self.output = output
        self.errorKind = errorKind
        self.errorReason = errorReason
        self.startedAt = startedAt
        self.finishedAt = finishedAt
        self.durationMs = durationMs
        self.exitCode = exitCode
    }

    public var hasAnswer: Bool {
        status == .done && (output?.isEmpty == false)
    }
}
