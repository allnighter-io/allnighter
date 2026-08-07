import Foundation

/// One source that is cooling down — tapped out until `coolingUntil`, derived from a
/// recent `CapacityObservation`. The readiness gates treat a cooling source as not-ready
/// so Auto/team resolution substitutes around it PRE-DISPATCH, and
/// `CatalogRunCoordinator` may one-shot reseat a failed seat mid-run onto a
/// declared fallback (see `SeatReseat`). Auto-expires the instant `coolingUntil` passes.
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
/// answers/attempts; this just rolls them up so dispatch readiness can route around a
/// tapped source. RLC-S01 also uses the same observation in a `vendorBackoff`
/// blocker; that park gate is stricter (`VendorBackoffPolicy.shouldPark`) and must
/// not be replaced by this broader pre-dispatch readiness policy.
public enum SourceCapacityLedger {

    /// Per-source cooldowns active at `now`. Confidence/kind-gated; a source already
    /// past its reset is dropped; when a source has several observations the longest
    /// live one wins. Callers must retain observations through a future wake/reset
    /// even when their originating run is older than a short lookback.
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

    /// Cooling sources as a stable, source-sorted list — the agent-facing projection that
    /// the `alln capacity` CLI and the `capacity_status` MCP tool return.
    public static func sources(observations: [CapacityObservation], now: Date) -> [SourceCooldown] {
        cooldowns(observations: observations, now: now).values
            .sorted { $0.source < $1.source }
    }

    /// Source-scoped single-flight nomination for accepted unified runs. Exactly
    /// one parked run per quota scope may probe readiness: the oldest one. A
    /// repeated limit on that run advances the shared source boundary, keeping
    /// every newer park quiet until the next nomination.
    public static func oldestVendorParkRunIDs(runs: [TeamRun]) -> Set<String> {
        var oldest: [String: TeamRun] = [:]
        for run in runs where run.status == .queued && run.phase == .waitingForVendor {
            guard let blocker = run.blocker, blocker.resource == .vendorBackoff else { continue }
            let scope = blocker.quotaScope
                ?? blocker.capacityObservation?.source
                ?? run.executionSourceId
            guard let scope, !scope.isEmpty else { continue }
            if let current = oldest[scope] {
                if run.createdAt < current.createdAt
                    || (run.createdAt == current.createdAt && run.id < current.id) {
                    oldest[scope] = run
                }
            } else {
                oldest[scope] = run
            }
        }
        return Set(oldest.values.map(\.id))
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

    /// When the source frees up — vendor-stated reset first, then the local fallback.
    /// observedResetAt is vendor-sourced truth; wakeAfter may be a local backoff guess.
    /// This value reaches the user, so vendor truth must win.
    /// Nil when neither is known (we never bench a source on an open-ended guess).
    static func coolingUntil(of obs: CapacityObservation) -> Date? {
        obs.observedResetAt ?? obs.wakeAfter
    }
}

/// Agent-facing return for `alln capacity` / the `capacity_status` MCP tool: which sources
/// are cooling down right now and until when. ONE contract — CLI, MCP, and the GUI badge
/// all present this, never a parallel shape.
public struct CapacitySourcesJSON: Codable, Sendable, Equatable {
    public let generatedAt: Date
    public let sources: [SourceCooldown]

    public init(generatedAt: Date, sources: [SourceCooldown]) {
        self.generatedAt = generatedAt
        self.sources = sources
    }

    /// Build from raw capacity observations (the handler gathers these from recent runs).
    public init(observations: [CapacityObservation], now: Date) {
        self.generatedAt = now
        self.sources = SourceCapacityLedger.sources(observations: observations, now: now)
    }
}
