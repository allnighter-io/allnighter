import Foundation

/// The agent-facing return of a Try Fix chain (`alln run --try-fix`, MCP team_run try-fix).
/// One round of the elimination loop: the read-only Bug Hunt diagnosis, the gate verdict, the
/// typed FixPacket, and — when the gate allowed it — the child fix-attempt run. Schema-backed so
/// a caller (or doctor/autofix) can read the outcome without scraping prose.
public struct TryFixChainJSON: Codable, Equatable, Sendable {
    public enum Status: String, Codable, Sendable {
        /// A child fix attempt ran (the loop took a swing — fixed or not, see the fixAttempt run).
        case fixAttempted = "fix_attempted"
        /// The gate refused (danger / bad packet / bad executor). No mutation happened.
        case blocked
        /// The diagnosis produced no typed packet to act on.
        case noPacket = "no_packet"
    }

    /// The gate verdict — mirrors `TryFixGate.Decision`, never blocks on confidence.
    public struct Gate: Codable, Equatable, Sendable {
        public var decision: String        // "allowed" | "blocked"
        public var code: String?           // TRY_FIX_PACKET_MISSING | _UNSAFE | EXECUTOR_INVALID
        public var reason: String?
        public var topHypothesisId: String?
        public init(decision: String, code: String? = nil, reason: String? = nil, topHypothesisId: String? = nil) {
            self.decision = decision; self.code = code; self.reason = reason; self.topHypothesisId = topHypothesisId
        }
    }

    public var contractVersion: String
    public var status: Status
    /// The read-only Bug Hunt run.
    public var diagnosis: TeamRunJSON
    public var gate: Gate
    /// The lifted packet (the ranked ladder + proof method), when one parsed.
    public var packet: FixPacket?
    /// The child execution run that tried the top hypothesis, when the gate allowed it.
    public var fixAttempt: TeamRunJSON?
    /// What the user should do next (human one-liner; the loop is iterative).
    public var nextStep: String?

    public init(
        contractVersion: String, status: Status, diagnosis: TeamRunJSON, gate: Gate,
        packet: FixPacket? = nil, fixAttempt: TeamRunJSON? = nil, nextStep: String? = nil
    ) {
        self.contractVersion = contractVersion; self.status = status
        self.diagnosis = diagnosis; self.gate = gate
        self.packet = packet; self.fixAttempt = fixAttempt; self.nextStep = nextStep
    }
}

public extension TryFixChainJSON.Gate {
    /// Project a `TryFixGate.Decision` into the wire shape.
    static func from(_ decision: TryFixGate.Decision) -> TryFixChainJSON.Gate {
        switch decision {
        case .allowed(let topId):
            return .init(decision: "allowed", topHypothesisId: topId)
        case .blocked(let code, let reason):
            return .init(decision: "blocked", code: code, reason: reason)
        }
    }
}
