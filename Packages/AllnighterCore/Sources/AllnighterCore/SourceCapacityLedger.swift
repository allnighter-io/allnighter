import Foundation

/// One source that is cooling down — tapped out until `coolingUntil`, derived from a
/// recent `CapacityObservation`. The readiness gates treat a cooling source as not-ready
/// so Auto/team resolution substitutes around it PRE-DISPATCH (no run-path retry, no extra
/// worker). Auto-expires the instant `coolingUntil` passes.
public struct SourceCooldown: Codable, Sendable, Equatable {
    /// Driver/source id — `claude_code`, `codex`, `cursor_agent`, `grok`, `agy`…
    public let source: String
    public let kind: CapacityObservationKind
    public let coolingUntil: Date
    public let confidence: CapacitySourceConfidence
    public let observedAt: Date

    public init(source: String, kind: CapacityObservationKind, coolingUntil: Date,
                confidence: CapacitySourceConfidence, observedAt: Date) {
        self.source = source
        self.kind = kind
        self.coolingUntil = coolingUntil
        self.confidence = confidence
        self.observedAt = observedAt
    }
}

/// Pure projection: recent `CapacityObservation`s → a per-source "cooling until" map. The
/// truth (the observations) is already recorded by `CapacityClassifier` on failed worker
/// answers; this just rolls them up so dispatch readiness can route around a tapped source.
public enum SourceCapacityLedger {

    /// Per-source cooldowns active at `now`. Confidence/kind-gated; a source already past its
    /// reset is dropped; when a source has several observations the longest live one wins.
    public static func cooldowns(observations: [CapacityObservation], now: Date) -> [String: SourceCooldown] {
        var out: [String: SourceCooldown] = [:]
        for obs in observations {
            guard isActionable(obs), let until = coolingUntil(of: obs), until > now else { continue }
            if let existing = out[obs.source], existing.coolingUntil >= until { continue }
            out[obs.source] = SourceCooldown(
                source: obs.source, kind: obs.kind, coolingUntil: until,
                confidence: obs.sourceConfidence, observedAt: obs.observedAt)
        }
        return out
    }

    /// The set of source ids that should be treated as not-ready at `now`.
    public static func coolingSources(observations: [CapacityObservation], now: Date) -> Set<String> {
        Set(cooldowns(observations: observations, now: now).keys)
    }

    /// Only bench a source on a real, trusted capacity signal. Auth/manual/unknown need user
    /// action (a different model won't help), and an unknown-confidence parse is too noisy.
    static func isActionable(_ obs: CapacityObservation) -> Bool {
        switch obs.kind {
        case .accountRateLimit, .providerBusy, .cooldown: break
        case .authRequired, .manualRequired, .unknownCapacity: return false
        }
        switch obs.sourceConfidence {
        case .structured, .messageFallback, .localPolicy: return true
        case .unknown: return false
        }
    }

    /// When the source frees up — the conservative local boundary, else the sourced reset.
    /// Nil when neither is known (we never bench a source on an open-ended guess).
    static func coolingUntil(of obs: CapacityObservation) -> Date? {
        obs.wakeAfter ?? obs.observedResetAt
    }
}
