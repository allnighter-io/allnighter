import Foundation

/// The deterministic Try Fix gate (Try_Fix_Auto_Implement). Decides whether an automatic fix
/// attempt may START from a Bug Hunt FixPacket. The rule is "danger blocks, doubt does not":
/// there is NO confidence threshold and NO tier block — a low-confidence or T3 packet still
/// runs (it just expects more rounds). What blocks is a danger flag, no actionable
/// hypothesis, no named proof, or an invalid executor. Pure + tested.
public enum TryFixGate {
    /// What the gate needs to know about the chosen executor team (resolved by the caller).
    public struct ExecutorFacts: Equatable, Sendable {
        public var teamId: String
        public var exists: Bool
        public var isMutating: Bool
        public var isRunnable: Bool
        public var workerCount: Int
        public init(teamId: String, exists: Bool, isMutating: Bool, isRunnable: Bool, workerCount: Int) {
            self.teamId = teamId; self.exists = exists; self.isMutating = isMutating
            self.isRunnable = isRunnable; self.workerCount = workerCount
        }
    }

    public enum Decision: Equatable, Sendable {
        /// The loop may start by trying this hypothesis id.
        case allowed(topHypothesisId: String)
        case blocked(code: String, reason: String)

        public var isAllowed: Bool { if case .allowed = self { return true }; return false }
    }

    public static func evaluate(packet: FixPacket?, executor: ExecutorFacts) -> Decision {
        guard let packet else {
            return .blocked(code: "TRY_FIX_PACKET_MISSING", reason: "answer run produced no typed fix packet")
        }
        // Danger blocks — about harm, not uncertainty.
        if !packet.dangerFlags.isEmpty {
            return .blocked(code: "TRY_FIX_PACKET_UNSAFE",
                            reason: "danger flag(s): \(packet.dangerFlags.joined(separator: ", "))")
        }
        // Need an actionable top hypothesis (a fix within a boundary).
        guard let top = packet.hypotheses.first(where: {
            !$0.fix.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !$0.fixBoundary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }) else {
            return .blocked(code: "TRY_FIX_PACKET_UNSAFE", reason: "no actionable hypothesis (fix + boundary)")
        }
        guard !packet.truthOwner.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return .blocked(code: "TRY_FIX_PACKET_UNSAFE", reason: "no truth owner named")
        }
        // A proof method must be present and complete (userObservation is honest + allowed).
        switch packet.proofMethod {
        case .command where (packet.proofCommand ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty:
            return .blocked(code: "TRY_FIX_PACKET_UNSAFE", reason: "proofMethod is command but no proofCommand")
        case .guiFixture where (packet.guiProofFixture ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty:
            return .blocked(code: "TRY_FIX_PACKET_UNSAFE", reason: "proofMethod is guiFixture but no fixture named")
        default:
            break
        }
        // Exactly one mutating, runnable executor worker.
        guard executor.exists else {
            return .blocked(code: "TRY_FIX_EXECUTOR_INVALID", reason: "unknown executor team \(executor.teamId)")
        }
        guard executor.isMutating else {
            return .blocked(code: "TRY_FIX_EXECUTOR_INVALID", reason: "executor \(executor.teamId) is not a mutating team")
        }
        guard executor.isRunnable else {
            return .blocked(code: "TRY_FIX_EXECUTOR_INVALID", reason: "executor \(executor.teamId) cannot run on this bench")
        }
        guard executor.workerCount == 1 else {
            return .blocked(code: "TRY_FIX_EXECUTOR_INVALID", reason: "executor must resolve to exactly one worker")
        }
        return .allowed(topHypothesisId: top.id)
    }
}
