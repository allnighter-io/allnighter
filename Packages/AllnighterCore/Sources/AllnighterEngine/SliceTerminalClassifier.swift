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
        if isInfraBackoff(outcome) { return .infraBackoff }
        if outcome.status != .done,
           isCompactionMarker(in: outcome.output, reasoning: outcome.reasoning) {
            return .compacting
        }
        if outcome.status != .done {
            return isStalled(outcome: outcome, packet: input.packet, now: input.now) ? .stalled : .failed
        }
        let visible = (outcome.output ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if visible.isEmpty { return .stalled }
        if input.check.skipped { return .passed }
        if input.check.timedOut { return .failed }
        if input.check.exitCode != 0 { return .failed }
        return .passed
    }

    public static func isCompactionMarker(in output: String?, reasoning: String?) -> Bool {
        let haystack = [output, reasoning].compactMap { $0 }.joined(separator: "\n").lowercased()
        return haystack.contains("compaction")
    }

    private static func isInfraBackoff(_ outcome: WorkerRunOutcome) -> Bool {
        let text = [outcome.errorReason, outcome.output].compactMap { $0 }.joined(separator: " ").lowercased()
        return text.contains("429") || text.contains("busy") || text.contains("rate limit")
    }

    private static func isStalled(outcome: WorkerRunOutcome, packet: WorkSlicePacket, now: Date) -> Bool {
        guard let started = outcome.startedAt else { return true }
        let age = now.timeIntervalSince(started)
        return age >= TimeInterval(packet.stallTimeoutSeconds)
    }
}
