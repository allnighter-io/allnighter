import Foundation
import AllnighterCore

/// Terminal classification for ONE PM Relay turn (PM or dev). Adapted from
/// `SliceTerminalClassifier` (Pair_Programming_Team §5) per PM_Relay.md §1's one named
/// salvage: **compaction ≠ stall**. Ported verbatim (same logic, same text/structured-fact
/// checks): the compaction-marker text sniff (`isCompactionMarker`) and the infra-backoff
/// detection (`isInfraBackoff` — structured capacity fact preferred, text sniff fallback).
/// Both apply unchanged to a single synchronous `RunService.run()` turn: a compacting or
/// rate-limited CLI is exactly as real a worker outcome here as it was mid-slice, and
/// killing a compacting worker is still the loop's worst false positive (PM_Relay.md §5.4).
///
/// Simplified vs. the original for a single relay turn: `SliceTerminalClassifier` split
/// `.stalled` (not-done, aged past a packet-scoped timeout) from `.failed` (not-done, fast)
/// so the slice queue's nudge prompt could pick a failure-reason string. The relay has no
/// per-outcome nudge — every not-done, non-infra, non-compacting turn gets the SAME bounded
/// retry-then-escalate treatment (`RelayCoordinator`'s turn dispatch loop), so that
/// elapsed-time split collapses into one `.stalled` case here; the caller's retry count is
/// what actually decides retry vs. escalate, not how the turn failed.
public enum RelayTurnOutcome: Sendable, Equatable {
    /// The turn finished `.done` with usable, non-empty output — carried verbatim, never
    /// summarized.
    case delivered(output: String)
    /// Not done, and neither an infra backoff nor a mid-compaction turn — a hung or sharply
    /// failed worker. Bounded-retried, then escalated; never silently killed.
    case stalled
    /// Rate-limited / provider-busy. Retried after a grace sleep, capped.
    case infraBackoff
    /// Finished `.done` but produced no visible output.
    case emptyResult
    /// Mid auto-compaction (every major CLI agent does this on long turns). NEVER folded
    /// into `.stalled` — see the file doc comment.
    case compacting
}

public enum RelayTurnClassifier {
    /// Retry ceilings for one relay turn's dispatch loop (PM or dev), mirroring
    /// `PairCoordinator`'s per-failure-mode caps (QUEUE-S01/S02: `maxCompactionRetries`,
    /// `maxInfraBackoffRetries`, `infraBackoffGraceSeconds`, executor attempt budget) —
    /// small, named constants so one kind of trouble never masks another, and a genuinely
    /// wedged turn always ends in `escalate`, never a silent hang.
    public enum RetryCeiling {
        public static let maxStalledAttempts = 3
        public static let maxEmptyResultAttempts = 3
        public static let maxInfraBackoffAttempts = 10
        public static let infraBackoffGraceSeconds = 5
        public static let maxCompactionAttempts = 10
        public static let compactionGraceSeconds = 5
    }

    public struct Input: Sendable, Equatable {
        public var outcome: WorkerRunOutcome

        public init(outcome: WorkerRunOutcome) {
            self.outcome = outcome
        }
    }

    public static func classify(_ input: Input) -> RelayTurnOutcome {
        let outcome = input.outcome
        if outcome.status != .done {
            if isInfraBackoff(outcome) { return .infraBackoff }
            if isCompactionMarker(in: outcome.output, reasoning: outcome.reasoning) { return .compacting }
            return .stalled
        }
        let visible = (outcome.output ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return visible.isEmpty ? .emptyResult : .delivered(output: outcome.output ?? visible)
    }

    /// Ported verbatim from `SliceTerminalClassifier.isCompactionMarker`.
    public static func isCompactionMarker(in output: String?, reasoning: String?) -> Bool {
        let haystack = [output, reasoning].compactMap { $0 }.joined(separator: "\n").lowercased()
        return haystack.contains("compaction")
    }

    /// Ported from `SliceTerminalClassifier.isInfraBackoff` — same structured-capacity-fact
    /// preference (`CapacityObservation.kind`), same text-sniff fallback for failures the
    /// capacity classifier didn't structure, unchanged.
    private static func isInfraBackoff(_ outcome: WorkerRunOutcome) -> Bool {
        if let kind = outcome.capacityObservation?.kind {
            switch kind {
            case .accountRateLimit, .providerBusy, .cooldown, .unknownCapacity: return true
            case .authRequired, .manualRequired: break
            }
        }
        let text = [outcome.errorReason, outcome.output].compactMap { $0 }.joined(separator: " ").lowercased()
        return text.contains("429") || text.contains("busy") || text.contains("rate limit")
    }
}
