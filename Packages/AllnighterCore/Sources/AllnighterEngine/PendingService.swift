import Foundation
import AllnighterCore

public enum PendingServiceError: Error, Equatable, Sendable {
    case notFound(String)
    case invalidWorker(String)
    case invalidState(String)
    case reorderInvalid(String)
    case mutationDeferred
    case unsupportedKind(String)
    case sourceGateBlocked(SourceGateBlocker)
}

/// Pending CRUD and lifecycle rules (Pending0/Pending1). Drain/admission deferred to Pending2.
public struct PendingService: Sendable {
    public let store: PendingStore
    public let models: [Model]
    private let idFactory: @Sendable () -> String
    private let now: @Sendable () -> Date

    public init(
        store: PendingStore,
        models: [Model],
        idFactory: @escaping @Sendable () -> String = { "pending_\(UUID().uuidString.lowercased())" },
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.store = store
        self.models = models
        self.idFactory = idFactory
        self.now = now
    }

    // MARK: - Add

    public struct AddRequest: Sendable {
        public var prompt: String
        public var kind: PendingItemKind
        public var workerToken: String?
        public var teamPresetId: String?
        public var fallbackTokens: [String]
        public var drainMode: PendingDrainMode
        public var workingDir: String?
        public var submit: Bool
        public var threadId: String?
        public var origin: PendingOrigin

        public init(
            prompt: String,
            kind: PendingItemKind = .workerChat,
            workerToken: String? = nil,
            teamPresetId: String? = nil,
            fallbackTokens: [String] = [],
            drainMode: PendingDrainMode = .manualStart,
            workingDir: String? = nil,
            submit: Bool = false,
            threadId: String? = nil,
            origin: PendingOrigin = .cli
        ) {
            self.prompt = prompt
            self.kind = kind
            self.workerToken = workerToken
            self.teamPresetId = teamPresetId
            self.fallbackTokens = fallbackTokens
            self.drainMode = drainMode
            self.workingDir = workingDir
            self.submit = submit
            self.threadId = threadId
            self.origin = origin
        }
    }

    public func add(_ request: AddRequest) throws -> PendingItem {
        let workerIds = try resolveWorkerIds(primary: request.workerToken, fallbacks: request.fallbackTokens)
        let timestamp = now()

        let item = PendingItem(
            id: idFactory(),
            threadId: request.threadId,
            title: PendingItemDerivation.title(from: request.prompt),
            kind: request.kind,
            status: request.submit ? .pending : .draft,
            createdAt: timestamp,
            updatedAt: timestamp,
            submittedAt: request.submit ? timestamp : nil,
            origin: request.origin,
            prompt: request.prompt,
            target: PendingTarget(
                modelIds: workerIds.all,
                teamPresetId: request.teamPresetId,
                preferredModelIds: workerIds.preferred,
                fallbackModelIds: workerIds.fallbacks
            ),
            policy: PendingPolicy(drainMode: request.drainMode),
            safety: PendingSafety(workingDir: request.workingDir)
        )

        try store.save(item)
        var (items, index) = try store.loadOrdered()
        if !index.itemOrder.contains(item.id) {
            index.itemOrder.append(item.id)
            try store.saveIndex(index)
        }
        _ = items
        return item
    }

    // MARK: - Submit / edit / cancel

    public func submit(id: String) throws -> PendingItem {
        guard var item = try store.load(id: id) else { throw PendingServiceError.notFound(id) }
        guard item.status == .draft else { throw PendingServiceError.invalidState("only Draft items can be submitted") }
        let timestamp = now()
        item.status = .pending
        item.submittedAt = timestamp
        item.updatedAt = timestamp
        try store.save(item)
        return item
    }

    public struct EditRequest: Sendable {
        public var prompt: String?
        public var workerToken: String?
        public var teamPresetId: String?
        public var fallbackTokens: [String]?
        public var drainMode: PendingDrainMode?
        public var workingDir: String?

        public init(
            prompt: String? = nil,
            workerToken: String? = nil,
            teamPresetId: String? = nil,
            fallbackTokens: [String]? = nil,
            drainMode: PendingDrainMode? = nil,
            workingDir: String? = nil
        ) {
            self.prompt = prompt
            self.workerToken = workerToken
            self.teamPresetId = teamPresetId
            self.fallbackTokens = fallbackTokens
            self.drainMode = drainMode
            self.workingDir = workingDir
        }
    }

    public func edit(id: String, _ request: EditRequest) throws -> PendingItem {
        guard var item = try store.load(id: id) else { throw PendingServiceError.notFound(id) }
        guard item.status != .running else { throw PendingServiceError.invalidState("running items cannot be edited") }

        if let prompt = request.prompt {
            item.prompt = prompt
            item.title = PendingItemDerivation.title(from: prompt)
        }
        if let workerToken = request.workerToken {
            let resolved = try resolveWorkerIds(primary: workerToken, fallbacks: request.fallbackTokens ?? [])
            item.target.modelIds = resolved.all
            item.target.preferredModelIds = resolved.preferred
            item.target.fallbackModelIds = resolved.fallbacks
        } else if let fallbacks = request.fallbackTokens {
            let resolved = try resolveWorkerIds(primary: nil, fallbacks: fallbacks)
            item.target.fallbackModelIds = resolved.fallbacks
        }
        if let team = request.teamPresetId { item.target.teamPresetId = team }
        if let drain = request.drainMode { item.policy.drainMode = drain }
        if let cwd = request.workingDir { item.safety.workingDir = cwd }

        if item.status == .pending {
            item.status = .draft
            item.submittedAt = nil
            item.lease = nil
            item.resume = nil
        }
        item.updatedAt = now()
        try store.save(item)
        return item
    }

    public func cancel(id: String) throws -> PendingItem {
        guard var item = try store.load(id: id) else { throw PendingServiceError.notFound(id) }
        if item.status == .running {
            item = try stopRunning(item)
        }
        guard item.status == .draft || item.status == .pending else {
            throw PendingServiceError.invalidState("only Draft or Pending items can be cancelled")
        }
        item.status = .cancelled
        item.lease = nil
        item.updatedAt = now()
        try store.save(item)
        return item
    }

    // MARK: - Reorder

    public enum ReorderAnchor: Sendable {
        case before(String)
        case after(String)
        case position(Int)
    }

    public func reorder(id: String, anchor: ReorderAnchor) throws -> PendingItem {
        guard let item = try store.load(id: id) else { throw PendingServiceError.notFound(id) }
        guard item.status == .draft || item.status == .pending else {
            throw PendingServiceError.reorderInvalid("reorder only affects Draft or Pending items")
        }

        var (_, index) = try store.loadOrdered()
        guard index.itemOrder.contains(id) else {
            throw PendingServiceError.reorderInvalid("item not in order index")
        }

        var order = index.itemOrder
        guard let fromIndex = order.firstIndex(of: id) else {
            throw PendingServiceError.reorderInvalid("item not in order index")
        }
        order.remove(at: fromIndex)
        let insertAt: Int
        switch anchor {
        case .before(let other):
            guard let anchorIndex = order.firstIndex(of: other) else {
                throw PendingServiceError.reorderInvalid("anchor not found")
            }
            insertAt = anchorIndex
        case .after(let other):
            guard let anchorIndex = order.firstIndex(of: other) else {
                throw PendingServiceError.reorderInvalid("anchor not found")
            }
            insertAt = anchorIndex + 1
        case .position(let pos):
            insertAt = max(0, min(pos, order.count))
        }
        order.insert(id, at: min(insertAt, order.count))
        index.itemOrder = order
        try store.saveIndex(index)
        return item
    }

    // MARK: - Run (manual attempt)

    public struct BeginRunOptions: Sendable {
        public var leaseOwner: PendingLeaseOwner
        public var attemptReason: String
        public var origin: PendingOrigin?

        public init(
            leaseOwner: PendingLeaseOwner = .cli,
            attemptReason: String = "workerChatRun",
            origin: PendingOrigin? = nil
        ) {
            self.leaseOwner = leaseOwner
            self.attemptReason = attemptReason
            self.origin = origin
        }

        public static let cliDefault = BeginRunOptions()
        public static let wakeTicket = BeginRunOptions(leaseOwner: .serve, attemptReason: "wakeTicket", origin: .system)
    }

    /// Validates and starts a Pending run: submits Draft items, records a running attempt, and leases.
    public func beginRun(id: String, options: BeginRunOptions = .cliDefault) throws -> PendingItem {
        guard var item = try store.load(id: id) else { throw PendingServiceError.notFound(id) }
        if item.status == .draft { item = try submit(id: id) }
        guard item.status == .pending else {
            throw PendingServiceError.invalidState("only Draft or Pending items can be run")
        }
        try validateRunnableKind(item)

        let timestamp = now()
        let attemptId = "attempt_\(UUID().uuidString.lowercased())"
        let modelId = item.target.preferredModelIds.first ?? item.target.modelIds.first ?? ""
        let attempt = PendingAttemptSummary(
            attemptId: attemptId,
            createdAt: timestamp,
            startedAt: timestamp,
            modelIds: modelId.isEmpty ? [] : [modelId],
            status: .running,
            reason: options.attemptReason
        )
        item.attempts.append(attempt)
        item.status = .running
        if let origin = options.origin { item.origin = origin }
        item.lease = PendingLease(
            leaseId: UUID().uuidString,
            owner: options.leaseOwner,
            leasedAt: timestamp,
            attemptId: attemptId
        )
        item.updatedAt = timestamp
        try store.save(item)
        return item
    }

    /// Settles a started attempt from `WorkerRunOutcome` and persists the item.
    public func settleRun(
        id: String,
        attemptIndex: Int,
        outcome: WorkerRunOutcome,
        transcriptRef: String?
    ) throws -> PendingItem {
        guard var item = try store.load(id: id) else { throw PendingServiceError.notFound(id) }
        guard attemptIndex < item.attempts.count else {
            throw PendingServiceError.invalidState("attempt index out of range")
        }

        let timestamp = now()
        var attempt = item.attempts[attemptIndex]
        attempt.completedAt = timestamp
        attempt.transcriptRef = transcriptRef

        switch outcome.status {
        case .done:
            attempt.status = .done
            attempt.reason = nil
            item.status = .done
            item.resume = nil
        case .failed:
            if let observation = outcome.capacityObservation {
                attempt.status = .blocked
                attempt.reason = observation.kind.rawValue
                item.status = .pending
                // Single capacity→resume policy (shared with settleTeamRun via resume(from:)).
                item.resume = resume(from: observation, attemptId: attempt.attemptId, transcriptRef: transcriptRef)
            } else {
                attempt.status = .failed
                attempt.reason = outcome.errorReason
                item.status = .failed
                item.resume = nil
            }
        case .timedOut:
            attempt.status = .timedOut
            attempt.reason = outcome.errorReason ?? "timedOut"
            item.status = .pending
            item.resume = PendingResume(
                reason: .timeout,
                lastAttemptId: attempt.attemptId,
                transcriptRef: transcriptRef
            )
        case .cancelled:
            attempt.status = .cancelled
            attempt.reason = outcome.errorReason ?? "cancelled"
            item.status = .pending
            item.resume = nil
        case .skipped:
            attempt.status = .failed
            attempt.reason = "workerSkipped"
            item.status = .failed
            item.resume = nil
        default:
            attempt.status = .failed
            attempt.reason = outcome.errorReason ?? "workerRunIncomplete"
            item.status = .failed
            item.resume = nil
        }

        item.attempts[attemptIndex] = attempt
        item.lease = nil
        item.updatedAt = timestamp
        try store.save(item)
        return item
    }

    /// Reserves a Pending item for direct worker execution.
    public func run(id: String) throws -> PendingItem {
        try beginRun(id: id)
    }

    private func validateRunnableKind(_ item: PendingItem) throws {
        switch item.kind {
        case .workerChat:
            return
        case .teamRun:
            return
        case .followUp:
            throw PendingServiceError.unsupportedKind(item.kind.rawValue)
        }
    }

    /// Settles a teamRun attempt from journal `TeamRun` truth.
    public func settleTeamRun(
        id: String,
        attemptIndex: Int,
        run: TeamRun,
        transcriptRef: String?
    ) throws -> PendingItem {
        guard var item = try store.load(id: id) else { throw PendingServiceError.notFound(id) }
        guard attemptIndex < item.attempts.count else {
            throw PendingServiceError.invalidState("attempt index out of range")
        }

        let timestamp = now()
        var attempt = item.attempts[attemptIndex]
        attempt.completedAt = timestamp
        attempt.transcriptRef = transcriptRef
        item.runId = run.id

        if let observation = dominantCapacityObservation(in: run) {
            attempt.status = .blocked
            attempt.reason = observation.kind.rawValue
            item.status = .pending
            item.resume = resume(from: observation, attemptId: attempt.attemptId, transcriptRef: transcriptRef)
        } else {
            switch run.status {
            case .complete, .done:
                attempt.status = .done
                attempt.reason = nil
                item.status = .done
                item.resume = nil
            case .partial:
                attempt.status = .done
                attempt.reason = "partial"
                item.status = .done
                item.resume = nil
            case .cancelled:
                attempt.status = .cancelled
                attempt.reason = "cancelled"
                item.status = .pending
                item.resume = nil
            case .failed, .interrupted:
                attempt.status = .failed
                attempt.reason = run.failedWorkerAnswers.first?.result.errorReason ?? run.status.rawValue
                item.status = .failed
                item.resume = nil
            default:
                attempt.status = .failed
                attempt.reason = "teamRunIncomplete"
                item.status = .failed
                item.resume = nil
            }
        }

        item.attempts[attemptIndex] = attempt
        item.lease = nil
        item.updatedAt = timestamp
        try store.save(item)
        return item
    }

    private func dominantCapacityObservation(in run: TeamRun) -> CapacityObservation? {
        run.failedWorkerAnswers.compactMap(\.result.capacityObservation).first
    }

    /// Delegates to `PendingCapacityResumeWriter` — one capacity -> resume policy,
    /// including the local recheck cadence that keeps a vendor-silent transient
    /// block from sitting forever. This used to be a second copy of that mapping
    /// and drifted: it still read `wakeAfter` straight off the observation, so
    /// after VSI stripped invented wakes a `providerBusy` item got no wake at all
    /// and never became due.
    private func resume(
        from observation: CapacityObservation,
        attemptId: String,
        transcriptRef: String?,
        now: Date = Date()
    ) -> PendingResume? {
        PendingCapacityResumeWriter.resume(
            from: observation, attemptId: attemptId, transcriptRef: transcriptRef, now: now)
    }

    // MARK: - Projection helpers

    public func list() throws -> [PendingItem] {
        try store.loadOrdered().items
    }

    public func mapJSON(_ item: PendingItem) throws -> PendingItemJSON {
        return PendingItemJSONMapper.map(
            item,
            context: .init(pendingStorePath: store.rootDirectory.path)
        )
    }

    /// Render-ready queue: armed/running items grouped by project (in queue order),
    /// each group headed by its running item, plus the total armed count for the pill.
    public func queueJSON() throws -> PendingQueueJSON {
        let relevant = try list().filter { $0.status == .pending || $0.status == .running }
        var order: [String] = []
        var byProject: [String: [PendingItem]] = [:]
        for item in relevant {
            let key = item.projectId ?? "unassigned"
            if byProject[key] == nil { order.append(key) }
            byProject[key, default: []].append(item)
        }
        let projectStore = ProjectStore()
        var projects: [PendingQueueJSON.ProjectQueue] = []
        for key in order {
            let group = byProject[key] ?? []
            let name = key == "unassigned" ? "Unassigned" : (try? projectStore.get(key))?.displayName
            let running = try group.first { $0.status == .running }.map { try mapJSON($0) }
            let pending = try group.filter { $0.status == .pending }.map { try mapJSON($0) }
            projects.append(.init(projectId: key, projectName: name, running: running, pending: pending))
        }
        let total = relevant.filter { $0.status == .pending }.count
        return PendingQueueJSON(contractVersion: ContractRegistry.contractVersion, totalPending: total, projects: projects)
    }

    // MARK: - Agent resolution

    private struct ResolvedWorkers {
        var preferred: [String]
        var fallbacks: [String]
        var all: [String] { Array(Set(preferred + fallbacks)) }
    }

    private func resolveWorkerIds(primary: String?, fallbacks: [String]) throws -> ResolvedWorkers {
        let preferred = try primary.map { try resolveWorkerId($0) }.map { [$0] } ?? []
        let fb = try fallbacks.map { try resolveWorkerId($0) }
        if preferred.isEmpty && fb.isEmpty {
            throw PendingServiceError.invalidWorker("no worker specified; use --model")
        }
        return ResolvedWorkers(preferred: preferred.isEmpty ? (fb.first.map { [$0] } ?? []) : preferred, fallbacks: fb)
    }

    private func resolveWorkerId(_ token: String) throws -> String {
        switch ExactIdResolver.resolveWorker(token, flag: "--model", models: models) {
        case .success(let model):
            return model.id
        case .failure(let failure):
            throw PendingServiceError.invalidWorker(failure.message)
        }
    }

    private func stopRunning(_ item: PendingItem) throws -> PendingItem {
        var updated = item
        updated.status = .pending
        updated.lease = nil
        updated.updatedAt = now()
        if var last = updated.attempts.last, last.status == .queued || last.status == .running {
            last.status = .cancelled
            last.completedAt = now()
            updated.attempts[updated.attempts.count - 1] = last
        }
        try store.save(updated)
        return updated
    }
}
