import Foundation

/// One-shot mid-run reseat when a seat fails on a capacity/session wall.
/// Vendor-agnostic: Claude session limits, Codex usage limits, provider busy,
/// and cooldowns all qualify. Auth/manual do not (user action required).
///
/// Ready ≠ automatic substitute still applies: reseat walks the seat's declared
/// `fallbackModelIds` / home-CLI policy via `TeamResolver.selectModel`, never
/// invents Cursor Sol or other `neverAutomaticSubstituteIds`.
public enum SeatReseat {

    /// Whether the seat preset allows a cross-bench substitute (ordered fallbacks or
    /// lane-capable policy). Used with `isEligible` so mid-run reseat matches initial
    /// seating intent for teams like `build_slice` that declare no ordered chain.
    public static func allowsSubstitute(fallbacks: [String], policy: ModelFallbackPolicy) -> Bool {
        !fallbacks.isEmpty || policy == .laneCapable
    }

    /// True when this failed result should trigger exactly one substitute invoke.
    public static func isEligible(_ result: WorkerRunResult, hasDeclaredFallbacks: Bool = false) -> Bool {
        guard result.status != .done, result.status != .cancelled else { return false }
        if let kind = result.capacityObservation?.kind {
            switch kind {
            case .accountRateLimit, .providerBusy, .cooldown, .unknownCapacity:
                return true
            case .authRequired, .manualRequired:
                return false
            }
        }
        if hasDeclaredFallbacks {
            return true
        }
        let text = [result.errorReason, result.output]
            .compactMap { $0 }
            .joined(separator: " ")
            .lowercased()
        let cues = [
            "429", "402", "rate limit", "rate-limit", "session limit", "usage limit",
            "usage_limit", "overloaded", "at capacity", "cooldown",
            "temporarily unavailable", "service unavailable",
            "payment required", "payment_required", "balance exhausted", "usage balance"
        ]
        return cues.contains { text.contains($0) }
    }

    /// Pick the next model for a failed seat. Excludes the failed model and its
    /// entire cooling driver so Claude→Claude won't reseat onto another cooling
    /// Claude seat; ordered `fallbackModelIds` may still land on another CLI.
    public static func nextModel(
        failedModelId: String,
        failedDriverId: String,
        preferredModelId: String?,
        fallbackModelIds: [String],
        requiredTags: [ModelCapabilityTag],
        fallback: ModelFallbackPolicy,
        lane: WorkLane,
        ready: [Model],
        preferredTags: [ModelCapabilityTag] = []
    ) -> Model? {
        let pool = ready.filter { $0.id != failedModelId && $0.driverId != failedDriverId }
        guard !pool.isEmpty else { return nil }
        let chain = fallbackModelIds.filter { $0 != failedModelId }
        return TeamResolver.selectModel(
            preferredModelId: preferredModelId,
            fallbackModelIds: chain,
            allowedModelIds: [],
            requiredTags: requiredTags,
            fallback: fallback,
            lane: lane,
            ready: pool,
            capabilities: ModelCatalog.capabilities,
            preferredTags: preferredTags
        )?.model
    }

    /// Resolve preferred / fallback chain for a worker (or Lead) from the team preset.
    public static func chain(
        for worker: Agent,
        team: TeamPreset,
        isLead: Bool
    ) -> (preferred: String?, fallbacks: [String], tags: [ModelCapabilityTag],
          preferredTags: [ModelCapabilityTag], policy: ModelFallbackPolicy) {
        if isLead {
            let lead = team.lead
            return (
                lead.preferredModelId ?? worker.modelId,
                lead.fallbackModelIds ?? [],
                lead.requiredCapabilityTags,
                [],
                lead.fallbackPolicy
            )
        }
        if let scout = team.scout, scout.id == worker.skillId || scout.skillId == worker.skillId {
            return (
                scout.preferredModelId,
                scout.fallbackModelIds ?? [],
                scout.requiredCapabilityTags,
                scout.preferredCapabilityTags,
                scout.fallbackPolicy
            )
        }
        if let row = team.agentSpecs.first(where: {
            $0.skillId == worker.skillId || $0.id == worker.skillId
        }) {
            return (
                row.preferredModelId,
                row.fallbackModelIds ?? [],
                row.requiredCapabilityTags,
                row.preferredCapabilityTags,
                row.fallbackPolicy
            )
        }
        // Capability-only need rows: no declared preferred — reseat may pick any
        // remaining free auto seat (still respects neverAutomaticSubstituteIds).
        return (
            nil,
            [],
            [],
            [],
            .strongestReady
        )
    }
}
