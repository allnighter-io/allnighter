import Foundation

/// Danger + scope gate for pair-programming slice dispatch (Pair_Programming_Team §5).
/// Danger blocks; doubt does not. `touchAllowlist` is required for mutating units.
public enum SliceGate {
    public typealias ExecutorFacts = TryFixGate.ExecutorFacts

    public enum Decision: Equatable, Sendable {
        case allowed
        case blocked(code: String, reason: String)

        public var isAllowed: Bool {
            if case .allowed = self { return true }
            return false
        }
    }

    public static func evaluate(packet: WorkSlicePacket?, executor: ExecutorFacts) -> Decision {
        guard let packet else {
            return .blocked(code: "PAIR_SLICE_PACKET_MISSING", reason: "no typed work slice packet")
        }
        if !packet.dangerFlags.isEmpty {
            return .blocked(
                code: "PAIR_SLICE_UNSAFE",
                reason: "danger flag(s): \(packet.dangerFlags.joined(separator: ", "))")
        }
        guard !packet.sliceId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return .blocked(code: "PAIR_SLICE_UNSAFE", reason: "sliceId is required")
        }
        guard !packet.intent.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return .blocked(code: "PAIR_SLICE_UNSAFE", reason: "intent is required")
        }
        guard packet.touchAllowlist.contains(where: {
            !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }) else {
            return .blocked(code: "PAIR_SLICE_UNSAFE", reason: "touchAllowlist is required for mutating units")
        }
        if let checkBlocked = Self.decisionForCheckMethod(
            rawValue: packet.check.method.rawValue,
            command: packet.check.command,
            fixture: packet.check.fixture
        ) {
            return checkBlocked
        }
        guard executor.exists else {
            return .blocked(code: "PAIR_SLICE_EXECUTOR_INVALID", reason: "unknown executor team \(executor.teamId)")
        }
        guard executor.isMutating else {
            return .blocked(code: "PAIR_SLICE_EXECUTOR_INVALID", reason: "executor \(executor.teamId) is not mutating")
        }
        guard executor.isRunnable else {
            return .blocked(code: "PAIR_SLICE_EXECUTOR_INVALID", reason: "executor \(executor.teamId) cannot run on this bench")
        }
        guard executor.workerCount == 1 else {
            return .blocked(code: "PAIR_SLICE_EXECUTOR_INVALID", reason: "executor must resolve to exactly one worker")
        }
        return .allowed
    }

    internal static func decisionForCheckMethod(
        rawValue: String,
        command: String?,
        fixture: String?
    ) -> Decision? {
        guard let method = FixPacket.ProofMethod(rawValue: rawValue) else {
            return .blocked(code: "PAIR_SLICE_UNSAFE", reason: "unsupported check.method: \(rawValue)")
        }
        switch method {
        case .command where (command ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty:
            return .blocked(code: "PAIR_SLICE_UNSAFE", reason: "check.method is command but no check.command")
        case .guiFixture where (fixture ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty:
            return .blocked(code: "PAIR_SLICE_UNSAFE", reason: "check.method is guiFixture but no check.fixture")
        case .command, .guiFixture, .userObservation:
            return nil
        }
    }
}
