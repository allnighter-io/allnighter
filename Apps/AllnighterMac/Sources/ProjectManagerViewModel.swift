import Foundation
import Observation
import AllnighterCore
import AllnighterEngine

/// The live Project Manager conversation for one project (PRJ-S15 wiring). Reads the
/// Manager turn log + proposals + work orders + verifications into one chronological
/// timeline, and drives the real Engine services for send/propose/approve/dispatch/
/// verify. @MainActor + @Observable like the other view models; model/proof work runs
/// async and reloads on completion. Project/git/proof truth lives in the stores.
@MainActor
@Observable
final class ProjectManagerViewModel {
    /// One rendered item in the Manager timeline.
    enum Item: Identifiable {
        case answer(ProjectManagerTurn)
        case proposal(ProjectProposal)
        case workOrder(WorkOrder)
        case verification(VerificationRecord)

        var id: String {
            switch self {
            case .answer(let t): return "a_\(t.id)"
            case .proposal(let p): return "p_\(p.id)"
            case .workOrder(let w): return "w_\(w.id)"
            case .verification(let v): return "v_\(v.id)"
            }
        }
        var date: Date {
            switch self {
            case .answer(let t): return t.createdAt
            case .proposal(let p): return p.createdAt
            case .workOrder(let w): return w.createdAt
            case .verification(let v): return v.createdAt
            }
        }
    }

    private(set) var project: Project?
    private(set) var items: [Item] = []
    private(set) var isWorking = false
    var lastError: String?

    // Runtime (bundle config + cached health), built once like ThreadsViewModel.
    private let registry: DriverRegistry
    private let models: [Model]
    private let records: [ToolProbeRecord]
    private let invocations: [String: ToolInvocation]
    private let teams: [TeamPreset]
    private var seeded = false

    init() {
        let config = AppConfig.loadConfiguration()
        self.registry = config.registry
        self.models = config.models
        self.records = SetupStore().load().records
        var inv: [String: ToolInvocation] = [:]
        for r in records where r.invocation != nil { inv[r.driverId] = r.invocation }
        self.invocations = inv
        self.teams = TeamCatalog.all
    }

    private var readyModels: [Model] {
        let ready = Set(records.filter { $0.status.isReady }.map(\.driverId))
        let resolved = models.filter { $0.enabled && ready.contains($0.driverId) }
        return resolved.isEmpty ? models.filter(\.enabled) : resolved   // optimistic in dev
    }

    // MARK: - Load

    func open(_ project: Project) {
        self.project = project
        reload()
    }

    func reload() {
        guard let project, !seeded else { return }
        let turns = ProjectManagerTurnStore().load(projectId: project.id)
        let proposals = ProjectProposalStore().load(projectId: project.id)
        let orders = ProjectWorkOrderStore().load(projectId: project.id)
        let verifications = VerificationStore().load(projectId: project.id)
        items = Self.timeline(turns: turns, proposals: proposals, orders: orders, verifications: verifications)
    }

    /// Merge the four sources into one chronological timeline. A `.propose` turn is
    /// represented by its proposal card (not an empty answer); `.answer`/`.wait` turns
    /// render their markdown / blocker.
    static func timeline(turns: [ProjectManagerTurn], proposals: [ProjectProposal], orders: [WorkOrder], verifications: [VerificationRecord]) -> [Item] {
        var out: [Item] = []
        for t in turns where t.mode != .propose { out.append(.answer(t)) }
        out.append(contentsOf: proposals.map(Item.proposal))
        out.append(contentsOf: orders.map(Item.workOrder))
        out.append(contentsOf: verifications.map(Item.verification))
        return out.sorted { $0.date < $1.date }
    }

    private func contextPacket(_ project: Project) -> ProjectContextPacket {
        let threads = ThreadStore().list().filter { $0.projectId == project.id }.sorted { $0.updatedAt > $1.updatedAt }
        let pending = ((try? PendingStore().loadAll()) ?? []).filter { $0.projectId == project.id }
        return ProjectContextPacketBuilder.build(
            project: project,
            recentThreadSummaries: threads.prefix(10).map { "\($0.title) [\($0.status.rawValue)]" },
            pendingItems: pending.prefix(10).map { "\($0.title) [\($0.status.rawValue)]" })
    }

    // MARK: - Actions (real services)

    /// Chat with the Manager (answer only — never auto-creates work).
    func send(_ message: String) {
        let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let project, !trimmed.isEmpty, !isWorking else { return }
        isWorking = true
        let svc = ProjectManagerService(runner: SubprocessCommandRunner(), registry: registry, invocations: invocations)
        let packet = contextPacket(project), ready = readyModels
        Task {
            let turn = await svc.chat(project: project, packet: packet, message: trimmed, readyModels: ready)
            try? ProjectManagerTurnStore().append(turn)
            self.isWorking = false
            if turn.mode == .wait { self.lastError = turn.warnings.first }
            self.reload()
        }
    }

    /// "What should we do next?" → one bounded proposal or one visible blocker.
    func proposeNext() {
        guard let project, !isWorking else { return }
        isWorking = true
        let svc = ProjectManagerService(runner: SubprocessCommandRunner(), registry: registry, invocations: invocations)
        let packet = contextPacket(project), ready = readyModels
        Task {
            let result = await svc.propose(project: project, packet: packet, readyModels: ready)
            try? ProjectManagerTurnStore().append(result.turn)
            if let proposal = result.proposal { try? ProjectProposalStore().append(proposal) }
            else { self.lastError = result.turn.warnings.first }
            self.isWorking = false
            self.reload()
        }
    }

    func approve(_ proposalId: String) {
        guard let project else { return }
        let store = ProjectProposalStore()
        guard var p = store.get(projectId: project.id, proposalId: proposalId), p.status.canTransition(to: .approved) else { return }
        let now = Date()
        let head = GitObserver().observe(rootPath: project.normalizedRootPath).head ?? p.baseGitHead
        p.baseGitHead = head
        p.status = .approved
        p.approval = ProjectApproval(approvedBy: "mac-user", approvedAt: now, approvedContentHash: WorkOrderBuilder.approvalContentHash(p))
        let order = WorkOrderBuilder.build(from: p, project: project, baseGitHead: head, now: now, idSuffix: UUID().uuidString.prefix(8).lowercased().description)
        p.workOrderId = order.id
        p.updatedAt = now
        try? ProjectWorkOrderStore().upsert(order)
        try? store.update(p)
        reload()
    }

    func postpone(_ proposalId: String) {
        guard let project else { return }
        let store = ProjectProposalStore()
        guard var p = store.get(projectId: project.id, proposalId: proposalId), p.status.canTransition(to: .postponed) else { return }
        p.status = .postponed
        p.updatedAt = Date()
        try? store.update(p)
        reload()
    }

    /// Dispatch an approved work order under the execution lane (INVIOLABLE).
    func dispatch(_ workOrderId: String) {
        guard let project, !isWorking, let order = ProjectWorkOrderStore().find(id: workOrderId) else { return }
        let proposalStore = ProjectProposalStore()
        let proposal = proposalStore.get(projectId: project.id, proposalId: order.proposalId)
        guard proposal?.status == .approved else { lastError = "Proposal not approved"; return }
        let ready = readyModels
        let (sourceId, model) = resolveDispatch(order: order, readyModels: ready)
        guard let model else { lastError = "No ready worker for this work order"; return }
        var d = order; d.mode = .dispatch; d.targetSourceId = sourceId
        isWorking = true
        let svc = ProjectDispatchService(runner: SubprocessCommandRunner(), registry: registry, invocations: invocations)
        Task {
            let git = GitObserver()
            let outcome = await svc.dispatch(
                order: d, project: project, proposal: proposal, targetModel: model,
                workerReadiness: ProjectWorkerReadinessStore().load(projectId: project.id), readyModels: ready,
                currentGitHead: git.observe(rootPath: project.normalizedRootPath).head,
                dirtyFiles: git.dirtyFiles(rootPath: project.normalizedRootPath),
                observedRootState: RootNormalization.observeRootState(key: project.normalizedRootPath),
                dirtyAcknowledged: false, teams: self.teams)
            switch outcome {
            case .dispatched(let ret):
                try? WorkReturnStore().append(ret)
                try? ProjectWorkOrderStore().upsert(d)
                if var pr = proposal { pr.status = ret.status == .returned ? .returned : .blocked; pr.updatedAt = Date(); try? proposalStore.update(pr) }
            case .blocked(_, let m): self.lastError = m
            case .laneBusy: self.lastError = "Another execute order is running on this lane."
            }
            self.isWorking = false
            self.reload()
        }
    }

    /// Verify a work order's return (runs declared proof; never verified on failure).
    func verify(workOrderId: String) {
        guard let project, !isWorking, let order = ProjectWorkOrderStore().find(id: workOrderId) else { return }
        let workReturn = WorkReturnStore().load(projectId: project.id).filter { $0.workOrderId == order.id }.last
        isWorking = true
        Task {
            let rec = await ProjectVerificationService(runner: SubprocessCommandRunner())
                .verify(workOrder: order, workReturn: workReturn, project: project, runProof: true)
            try? VerificationStore().append(rec)
            let ps = ProjectProposalStore()
            if var p = ps.get(projectId: project.id, proposalId: order.proposalId), rec.outcome.isDone, p.status.canTransition(to: .verified) {
                p.status = .verified; p.updatedAt = Date(); try? ps.update(p)
            }
            self.isWorking = false
            self.reload()
        }
    }

    private func resolveDispatch(order: WorkOrder, readyModels: [Model]) -> (String?, Model?) {
        if let src = order.resolvedTargetSourceId, let m = readyModels.first(where: { $0.driverId == src }) { return (src, m) }
        let strongest = readyModels.max { ModelCatalog.capabilities($0.id).strengthRank < ModelCatalog.capabilities($1.id).strengthRank }
        return (strongest?.driverId, strongest)
    }

    #if DEBUG
    /// Designer-mock seed for the GUI proof (never real data; freezes the timeline).
    func seedForProof(project: Project, items: [Item]) {
        self.project = project
        self.items = items
        self.seeded = true
    }
    #endif
}
