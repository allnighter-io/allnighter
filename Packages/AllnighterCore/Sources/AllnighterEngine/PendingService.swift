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
        let intent = PendingItemDerivation.defaultIntent(for: request.kind)
        var execution: PendingExecution?
        if intent == .execute, let workerId = workerIds.preferred.first {
            let laneKey = PendingItemDerivation.executionLaneKey(workerId: workerId, workingDir: request.workingDir)
            execution = PendingExecution(intent: .execute, executionLaneKey: laneKey)
        } else {
            execution = PendingExecution(intent: intent)
        }

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
                workerIds: workerIds.all,
                teamPresetId: request.teamPresetId,
                preferredWorkerIds: workerIds.preferred,
                fallbackWorkerIds: workerIds.fallbacks
            ),
            policy: PendingPolicy(drainMode: request.drainMode),
            execution: execution,
            safety: PendingSafety(workingDir: request.workingDir)
        )

        try store.save(item)
        var (items, index) = try store.loadOrdered()
        if !index.itemOrder.contains(item.id) {
            index.itemOrder.append(item.id)
            if let laneKey = execution?.executionLaneKey, execution?.intent == .execute {
                upsertLane(&index, laneKey: laneKey, itemId: item.id)
            }
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
        if item.execution?.intent == .execute, let workerId = item.target.preferredWorkerIds.first ?? item.target.workerIds.first {
            let laneKey = PendingItemDerivation.executionLaneKey(workerId: workerId, workingDir: item.safety.workingDir)
            item.execution?.executionLaneKey = laneKey
            var (_, index) = try store.loadOrdered()
            upsertLane(&index, laneKey: laneKey, itemId: item.id)
            try store.saveIndex(index)
        }
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
            item.target.workerIds = resolved.all
            item.target.preferredWorkerIds = resolved.preferred
            item.target.fallbackWorkerIds = resolved.fallbacks
        } else if let fallbacks = request.fallbackTokens {
            let resolved = try resolveWorkerIds(primary: nil, fallbacks: fallbacks)
            item.target.fallbackWorkerIds = resolved.fallbacks
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
        removeFromLanes(itemId: item.id)
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

        if item.execution?.intent == .execute, let laneKey = item.execution?.executionLaneKey,
           let laneIndex = index.executionLanes.firstIndex(where: { $0.executionLaneKey == laneKey }) {
            var lane = index.executionLanes[laneIndex]
            guard let laneFrom = lane.orderedItemIds.firstIndex(of: id) else {
                throw PendingServiceError.reorderInvalid("item not in execution lane")
            }
            lane.orderedItemIds.remove(at: laneFrom)
            let laneInsert: Int
            switch anchor {
            case .before(let other):
                guard let otherItem = try store.load(id: other),
                      otherItem.execution?.executionLaneKey == laneKey,
                      otherItem.status == .draft || otherItem.status == .pending,
                      let laneTo = lane.orderedItemIds.firstIndex(of: other) else {
                    throw PendingServiceError.reorderInvalid("anchor must be a Pending item in the same execution lane")
                }
                laneInsert = laneTo
            case .after(let other):
                guard let otherItem = try store.load(id: other),
                      otherItem.execution?.executionLaneKey == laneKey,
                      otherItem.status == .draft || otherItem.status == .pending,
                      let laneTo = lane.orderedItemIds.firstIndex(of: other) else {
                    throw PendingServiceError.reorderInvalid("anchor must be a Pending item in the same execution lane")
                }
                laneInsert = laneTo + 1
            case .position(let pos):
                laneInsert = max(0, min(pos, lane.orderedItemIds.count))
            }
            lane.orderedItemIds.insert(id, at: min(laneInsert, lane.orderedItemIds.count))
            lane.executionLanePolicy = .userOrdered
            index.executionLanes[laneIndex] = lane
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

    /// Validates and starts a Pending run: submits Draft items, records a running attempt, and leases to CLI.
    public func beginRun(id: String) throws -> PendingItem {
        guard var item = try store.load(id: id) else { throw PendingServiceError.notFound(id) }
        if item.status == .draft { item = try submit(id: id) }
        guard item.status == .pending else {
            throw PendingServiceError.invalidState("only Draft or Pending items can be run")
        }
        try validateRunnableKind(item)

        let timestamp = now()
        let attemptId = "attempt_\(UUID().uuidString.lowercased())"
        let workerId = item.target.preferredWorkerIds.first ?? item.target.workerIds.first ?? ""
        let attempt = PendingAttemptSummary(
            attemptId: attemptId,
            createdAt: timestamp,
            startedAt: timestamp,
            workerIds: workerId.isEmpty ? [] : [workerId],
            status: .running,
            executionLaneKey: item.execution?.executionLaneKey,
            reason: "workerChatRun"
        )
        item.attempts.append(attempt)
        item.status = .running
        item.lease = PendingLease(leaseId: UUID().uuidString, owner: .cli, leasedAt: timestamp, attemptId: attemptId)
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
                switch observation.kind {
                case .accountRateLimit, .cooldown, .unknownCapacity:
                    item.resume = PendingResume(
                        reason: .cooldown,
                        lastAttemptId: attempt.attemptId,
                        transcriptRef: transcriptRef,
                        observedResetAt: observation.observedResetAt,
                        wakeAfter: observation.wakeAfter,
                        capacityObservation: observation
                    )
                case .providerBusy:
                    item.resume = PendingResume(
                        reason: .providerBusy,
                        lastAttemptId: attempt.attemptId,
                        transcriptRef: transcriptRef,
                        observedResetAt: observation.observedResetAt,
                        wakeAfter: observation.wakeAfter,
                        capacityObservation: observation
                    )
                case .authRequired, .manualRequired:
                    item.resume = nil
                }
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

    /// Legacy entry point — use `PendingRunExecutor` for workerChat execution.
    public func run(id: String) throws -> PendingItem {
        try beginRun(id: id)
    }

    private func validateRunnableKind(_ item: PendingItem) throws {
        if let blocker = PendingMutatingSourceGate.evaluate(item: item, readyModels: models) {
            throw PendingServiceError.sourceGateBlocked(blocker)
        }
        switch item.kind {
        case .workerChat:
            return
        case .dispatch:
            throw PendingServiceError.mutationDeferred
        case .workOrder:
            if item.execution?.intent == .execute {
                throw PendingServiceError.mutationDeferred
            }
            throw PendingServiceError.unsupportedKind(item.kind.rawValue)
        case .teamRun, .returnReview, .followUp:
            throw PendingServiceError.unsupportedKind(item.kind.rawValue)
        }
    }

    // MARK: - Projection helpers

    public func list() throws -> [PendingItem] {
        try store.loadOrdered().items
    }

    public func executionLaneHead(for item: PendingItem, index: PendingStoreIndex) -> String? {
        guard let laneKey = item.execution?.executionLaneKey else { return nil }
        guard let lane = index.executionLanes.first(where: { $0.executionLaneKey == laneKey }) else { return nil }
        return lane.orderedItemIds.first
    }

    public func mapJSON(_ item: PendingItem, userReordered: Bool? = nil) throws -> PendingItemJSON {
        let (_, index) = try store.loadOrdered()
        let head = executionLaneHead(for: item, index: index)
        return PendingItemJSONMapper.map(
            item,
            context: .init(
                pendingStorePath: store.rootDirectory.path,
                executionLaneHeadItemId: head,
                userReorderedExecutionLane: userReordered
            )
        )
    }

    // MARK: - Worker resolution

    private struct ResolvedWorkers {
        var preferred: [String]
        var fallbacks: [String]
        var all: [String] { Array(Set(preferred + fallbacks)) }
    }

    private func resolveWorkerIds(primary: String?, fallbacks: [String]) throws -> ResolvedWorkers {
        let preferred = try primary.map { try resolveWorkerId($0) }.map { [$0] } ?? []
        let fb = try fallbacks.map { try resolveWorkerId($0) }
        if preferred.isEmpty && fb.isEmpty {
            throw PendingServiceError.invalidWorker("no worker specified; use --worker")
        }
        return ResolvedWorkers(preferred: preferred.isEmpty ? (fb.first.map { [$0] } ?? []) : preferred, fallbacks: fb)
    }

    private func resolveWorkerId(_ token: String) throws -> String {
        let normalized = token.lowercased()
        if models.contains(where: { $0.id == token }) { return token }
        if let model = models.first(where: { $0.id.lowercased() == normalized }) { return model.id }
        let driverAliases: [String: String] = [
            "claude": "claude_code", "codex": "codex", "grok": "grok",
            "gemini": "antigravity", "antigravity": "antigravity",
        ]
        let driverId = driverAliases[normalized] ?? normalized
        if let model = models.first(where: { $0.driverId == driverId && $0.enabled }) {
            return model.id
        }
        throw PendingServiceError.invalidWorker(token)
    }

    // MARK: - Private lane helpers

    private func upsertLane(_ index: inout PendingStoreIndex, laneKey: String, itemId: String) {
        if let i = index.executionLanes.firstIndex(where: { $0.executionLaneKey == laneKey }) {
            if !index.executionLanes[i].orderedItemIds.contains(itemId) {
                index.executionLanes[i].orderedItemIds.append(itemId)
            }
        } else {
            index.executionLanes.append(PendingExecutionLaneState(executionLaneKey: laneKey, orderedItemIds: [itemId]))
        }
    }

    private func removeFromLanes(itemId: String) {
        guard var index = try? store.loadIndex() else { return }
        for i in index.executionLanes.indices {
            index.executionLanes[i].orderedItemIds.removeAll { $0 == itemId }
        }
        try? store.saveIndex(index)
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
