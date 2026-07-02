import Foundation
import AllnighterCore

/// Terminal classification for one slice attempt (Pair_Programming_Team §5).
public enum SliceTerminalOutcome: String, Codable, Sendable, Equatable {
    case passed
    case failed
    case stalled
    case compacting
    case infraBackoff
}

public enum SliceTerminalClassifier {
    public struct Input: Sendable, Equatable {
        public var workerOutcome: WorkerRunOutcome
        public var check: CheckResult
        public var packet: WorkSlicePacket
        public var now: Date

        public init(workerOutcome: WorkerRunOutcome, check: CheckResult, packet: WorkSlicePacket, now: Date) {
            self.workerOutcome = workerOutcome
            self.check = check
            self.packet = packet
            self.now = now
        }
    }

    public static func classify(_ input: Input) -> SliceTerminalOutcome {
        let outcome = input.workerOutcome
        let packet = input.packet

        if outcome.status != .done {
            if isInfraBackoff(outcome) { return .infraBackoff }
            if isCompactionMarker(in: outcome.output, reasoning: outcome.reasoning) {
                return .compacting
            }
            return isStalled(outcome: outcome, packet: packet, now: input.now) ? .stalled : .failed
        }
        if input.check.skipped { return .passed }
        if input.check.timedOut { return .failed }
        if input.check.exitCode != 0 { return .failed }
        let visible = (outcome.output ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if visible.isEmpty {
            if packet.mode == .reviewVerify { return .stalled }
            return packet.isAdvisoryReview ? .passed : .stalled
        }
        return .passed
    }

    public static func isCompactionMarker(in output: String?, reasoning: String?) -> Bool {
        let haystack = [output, reasoning].compactMap { $0 }.joined(separator: "\n").lowercased()
        return haystack.contains("compaction")
    }

    private static func isInfraBackoff(_ outcome: WorkerRunOutcome) -> Bool {
        // Prefer the structured capacity fact when present (F2_B.3c: `DefaultWorkerRunner`
        // folds a classified capacity kind into `errorReason` as "capacity: <kind>" instead
        // of the raw vendor text `WorkerRunner` used to leave there, so the text heuristic
        // below can no longer see "429"/"rate limit" on a classified failure). Falls back to
        // the original text sniff for failures `CapacityClassifier` didn't structure (e.g. an
        // agy vendor-stdout timeout, which is a `.timedOut` errorKind, not a capacity fact).
        if let kind = outcome.capacityObservation?.kind {
            switch kind {
            case .accountRateLimit, .providerBusy, .cooldown, .unknownCapacity: return true
            case .authRequired, .manualRequired: break
            }
        }
        let text = [outcome.errorReason, outcome.output].compactMap { $0 }.joined(separator: " ").lowercased()
        return text.contains("429") || text.contains("busy") || text.contains("rate limit")
    }

    private static func isStalled(outcome: WorkerRunOutcome, packet: WorkSlicePacket, now: Date) -> Bool {
        guard let started = outcome.timing.startedAt else { return true }
        let age = now.timeIntervalSince(started)
        return age >= TimeInterval(packet.stallTimeoutSeconds)
    }
}
