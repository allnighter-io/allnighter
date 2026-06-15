import Foundation

/// The exact prompt sent to one seat. Identical text per seat in the MVP; the
/// per-seat stance prefix (RB1) and optional bounded context (RB6) make it vary —
/// the `MemberPrompt` "no longer identical-text-only" growth seam.
public struct MemberPrompt: Codable, Sendable, Equatable {
    public var seatId: String
    public var workerId: String
    public var text: String

    public init(seatId: String, workerId: String, text: String) {
        self.seatId = seatId
        self.workerId = workerId
        self.text = text
    }
}

/// One seat's result for a council run. Keyed by `seatId` (so self-fusion seats
/// never collide); `workerId` is provenance — which worker ran the seat.
public struct MemberResponse: Codable, Sendable, Equatable, Identifiable {
    public var seatId: String
    public var workerId: String
    public var status: MemberStatus
    public var output: String?
    public var errorKind: MemberErrorKind?
    public var errorReason: String?
    public var startedAt: Date?
    public var finishedAt: Date?
    public var durationMs: Int?
    public var exitCode: Int?

    /// Identifiable identity is the seat id. Computed — not encoded (only
    /// `seatId`/`workerId` are stored).
    public var id: String { seatId }

    public init(
        seatId: String,
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
        self.seatId = seatId
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
