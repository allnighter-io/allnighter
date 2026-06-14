import Foundation

/// The exact prompt sent to one worker. MVP: identical text for every member.
/// Growth seam: the prompt builder may later add per-worker repo/file context.
public struct MemberPrompt: Codable, Sendable, Equatable {
    public var workerId: String
    public var text: String

    public init(workerId: String, text: String) {
        self.workerId = workerId
        self.text = text
    }
}

/// One worker's result for a council run.
public struct MemberResponse: Codable, Sendable, Equatable, Identifiable {
    public var workerId: String
    public var status: MemberStatus
    public var output: String?
    public var errorKind: MemberErrorKind?
    public var errorReason: String?
    public var startedAt: Date?
    public var finishedAt: Date?
    public var durationMs: Int?
    public var exitCode: Int?

    public var id: String { workerId }

    public init(
        workerId: String,
        status: MemberStatus = .queued,
        output: String? = nil,
        errorKind: MemberErrorKind? = nil,
        errorReason: String? = nil,
        startedAt: Date? = nil,
        finishedAt: Date? = nil,
        durationMs: Int? = nil,
        exitCode: Int? = nil
    ) {
        self.workerId = workerId
        self.status = status
        self.output = output
        self.errorKind = errorKind
        self.errorReason = errorReason
        self.startedAt = startedAt
        self.finishedAt = finishedAt
        self.durationMs = durationMs
        self.exitCode = exitCode
    }

    /// A member that produced a usable answer.
    public var hasAnswer: Bool {
        status == .done && (output?.isEmpty == false)
    }
}
