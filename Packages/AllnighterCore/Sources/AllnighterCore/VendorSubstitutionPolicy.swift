import Foundation

/// RLC-S04 — substitution authorized by selection provenance only.
///
/// Provenance table (SSOT: `Rate_Limit_Continuity.md` §Substitution):
/// | Selection origin | Automatic substitution |
/// | Auto/default | Same-tier compatible when Auto toggle on |
/// | Team preset with declared fallbacks | Follow declared chain |
/// | Explicitly named worker | Never silent hop — park; offer "Use another model" |
/// | Substitutions off / unresolved | Wait for the same source |
///
/// Park precedence: when `VendorBackoffPolicy.shouldPark` is true, **park wins**
/// over immediate `SeatReseat` unless automatic hop is explicitly allowed by the
/// table above *and* waiting is worse than substituting (long/unknown reset).
/// Same-vendor continuation is always preferred on short, known resets.
public enum RunSelectionOrigin {
    public static let auto = "selection.auto"
    public static let explicit = "selection.explicit"
    public static let teamFallback = "selection.teamFallback"
    public static let automaticSubstitute = "substitution.automatic"
    public static let manualSubstitute = "substitution.manual"
}

public enum VendorSubstitutionPolicy {
    /// Never bounce between cooling vendors; substitution hops are separate from
    /// vendor wake resume attempts but share the same hard ceiling.
    public static let maximumSubstitutionHops = 3
    /// Prefer parking (same-source resume) when the vendor-stated reset is soon.
    public static let longResetPreferenceThreshold: TimeInterval = 60 * 60

    // MARK: - Provenance

    public static func inferInitialSelectionOrigin(
        autoResolved: Bool,
        explicitWorkerPin: Bool,
        explicitTeamChosen: Bool,
        teamHasDeclaredFallbacks: Bool
    ) -> String {
        if autoResolved { return RunSelectionOrigin.auto }
        if explicitWorkerPin { return RunSelectionOrigin.explicit }
        if explicitTeamChosen, teamHasDeclaredFallbacks { return RunSelectionOrigin.teamFallback }
        if explicitTeamChosen { return RunSelectionOrigin.explicit }
        return RunSelectionOrigin.auto
    }

    public static func teamHasDeclaredFallbacks(worker: Worker, team: TeamPreset) -> Bool {
        let chain = SeatReseat.chain(for: worker, team: team, isLead: false)
        if !chain.fallbacks.isEmpty { return true }
        return chain.policy != .exactOnly
    }

    /// True when provenance authorizes a silent/automatic hop (never inferred from prompt).
    public static func allowsAutomaticSubstitution(
        selectionOrigin: String?,
        allowHealthySubstitutions: Bool
    ) -> Bool {
        guard allowHealthySubstitutions, let origin = selectionOrigin else { return false }
        switch origin {
        case RunSelectionOrigin.auto, RunSelectionOrigin.teamFallback:
            return true
        case RunSelectionOrigin.automaticSubstitute, RunSelectionOrigin.manualSubstitute:
            return true
        case RunSelectionOrigin.explicit:
            return false
        case MorningReceipt.automaticResumeOrigin, MorningReceipt.manualResumeOrigin:
            return false
        default:
            return false
        }
    }

    // MARK: - Visited set + hop bound

    public static func visitedSourceIds(from attempts: [RunAttempt]) -> Set<String> {
        Set(attempts.compactMap { $0.resolvedSourceId ?? $0.requestedSourceId })
    }

    public static func substitutionHopCount(from attempts: [RunAttempt]) -> Int {
        attempts.filter { $0.substitutionOfAttempt != nil }.count
    }

    public static func canHopAgain(from attempts: [RunAttempt]) -> Bool {
        substitutionHopCount(from: attempts) < maximumSubstitutionHops
    }

    // MARK: - Park vs substitute

    /// True when an authorized substitute should be attempted instead of parking or
    /// resuming the same cooling source (unknown reset or a long vendor window).
    public static func prefersSubstitutionOverPark(
        wakeAfter: Date?,
        observation: CapacityObservation?,
        now: Date = Date()
    ) -> Bool {
        if wakeAfter == nil { return true }
        guard let wakeAfter else { return true }
        let distance = wakeAfter.timeIntervalSince(now)
        guard distance.isFinite else { return true }
        return distance > longResetPreferenceThreshold
    }

    // MARK: - Candidate resolution (SBDS + SeatReseat only)

    public struct Candidate: Sendable, Equatable {
        public var modelId: String
        public var sourceId: String
        public var selectionOrigin: String

        public init(modelId: String, sourceId: String, selectionOrigin: String) {
            self.modelId = modelId
            self.sourceId = sourceId
            self.selectionOrigin = selectionOrigin
        }
    }

    /// Next automatic substitute for a parked or just-settled capacity event.
    public static func nextAutomaticCandidate(
        run: TeamRun,
        failedModelId: String,
        preset: TeamPreset,
        settings: DefaultModelSettings,
        models: [Model],
        readyModels: [Model],
        coolingSourceIds: Set<String>,
        lane: WorkLane
    ) -> Candidate? {
        guard canHopAgain(from: run.attempts) else { return nil }
        let origin = run.attempts.first?.selectionOrigin
        guard allowsAutomaticSubstitution(
            selectionOrigin: origin,
            allowHealthySubstitutions: settings.allowHealthySubstitutions
        ) else { return nil }

        guard let failed = models.first(where: { $0.id == failedModelId }) else { return nil }
        let visited = visitedSourceIds(from: run.attempts)
        let pool = readyModels.filter { model in
            model.id != failedModelId
                && !visited.contains(model.driverId)
                && !coolingSourceIds.contains(model.driverId)
                && ModelCatalog.allowsAutomaticSubstitution(model.id)
        }
        guard !pool.isEmpty else { return nil }

        switch origin {
        case RunSelectionOrigin.auto:
            let readyIds = Set(pool.map(\.id))
            let resolution = SubstitutionResolver.resolveAuto(
                settings: settings,
                readyModelIds: readyIds
            )
            guard let id = resolution.resolvedModelId,
                  resolution.substituted,
                  id != failedModelId,
                  let model = models.first(where: { $0.id == id }),
                  model.driverId != failed.driverId else { return nil }
            return Candidate(
                modelId: model.id,
                sourceId: model.driverId,
                selectionOrigin: RunSelectionOrigin.automaticSubstitute
            )

        case RunSelectionOrigin.teamFallback, RunSelectionOrigin.automaticSubstitute,
             RunSelectionOrigin.manualSubstitute:
            guard let worker = run.workers.first else { return nil }
            let chain = SeatReseat.chain(for: worker, team: preset, isLead: false)
            guard let model = SeatReseat.nextModel(
                failedModelId: failedModelId,
                failedDriverId: failed.driverId,
                preferredModelId: chain.preferred,
                fallbackModelIds: chain.fallbacks,
                requiredTags: chain.tags,
                fallback: chain.policy,
                lane: lane,
                ready: pool,
                preferredTags: chain.preferredTags
            ) else { return nil }
            return Candidate(
                modelId: model.id,
                sourceId: model.driverId,
                selectionOrigin: RunSelectionOrigin.automaticSubstitute
            )

        default:
            return nil
        }
    }

    /// Manual "Use another model" — user-authorized regardless of initial provenance.
    public static func manualCandidates(
        run: TeamRun,
        failedModelId: String,
        preset: TeamPreset,
        settings: DefaultModelSettings,
        models: [Model],
        readyModels: [Model],
        coolingSourceIds: Set<String>,
        lane: WorkLane
    ) -> [Model] {
        guard canHopAgain(from: run.attempts) else { return [] }
        guard models.contains(where: { $0.id == failedModelId }) else { return [] }
        let visited = visitedSourceIds(from: run.attempts)
        let pool = readyModels.filter { model in
            model.id != failedModelId
                && !visited.contains(model.driverId)
                && !coolingSourceIds.contains(model.driverId)
        }
        guard !pool.isEmpty else { return [] }

        if let auto = nextAutomaticCandidate(
            run: run,
            failedModelId: failedModelId,
            preset: preset,
            settings: settings,
            models: models,
            readyModels: pool,
            coolingSourceIds: coolingSourceIds,
            lane: lane
        ), let model = models.first(where: { $0.id == auto.modelId }) {
            return [model]
        }

        let worker = run.workers.first
        let chain = worker.map { SeatReseat.chain(for: $0, team: preset, isLead: false) }
        let tags = chain?.tags ?? []
        var candidates: [Model] = []
        for candidate in pool {
            if tags.isEmpty {
                candidates.append(candidate)
                continue
            }
            let required = ModelCatalog.capabilities(candidate.id)
            if tags.allSatisfy({ required.capabilityTags.contains($0) }) {
                candidates.append(candidate)
            }
        }
        return candidates.sorted {
            $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending
        }
    }

    public static func acceptsManualCandidate(
        _ modelId: String,
        run: TeamRun,
        failedModelId: String,
        preset: TeamPreset,
        settings: DefaultModelSettings,
        models: [Model],
        readyModels: [Model],
        coolingSourceIds: Set<String>,
        lane: WorkLane
    ) -> Bool {
        manualCandidates(
            run: run,
            failedModelId: failedModelId,
            preset: preset,
            settings: settings,
            models: models,
            readyModels: readyModels,
            coolingSourceIds: coolingSourceIds,
            lane: lane
        ).contains { $0.id == modelId }
    }
}
