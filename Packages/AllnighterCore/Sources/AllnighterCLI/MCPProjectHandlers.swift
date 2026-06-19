import Foundation
import AllnighterCore
import AllnighterEngine

/// PRJ-S13: MCP projection of the project-scoped CLI. These handlers call the SAME
/// Engine services + stores and emit the SAME `Project*JSON` envelopes as `alln
/// project …` — no MCP-only semantics. External agents are CALLERS, never approvers:
/// approve/edit/postpone are intentionally NOT exposed here. Agent-originated
/// dispatch still satisfies every approval + mutating gate (it can only dispatch a
/// human-approved work order, under the execution lane).
enum MCPProjectHandlers {
    enum Outcome: Error, Sendable {
        case success(String, summary: String)
        case toolError(ErrorEnvelope)
    }

    private static func cv() -> String { ContractRegistry.contractVersion }

    private static func err(_ code: String, _ message: String, retryable: Bool = false) -> Outcome {
        .toolError(ErrorEnvelope(code: code, message: message, requiresManual: !retryable, retryable: retryable))
    }

    private static func project(_ args: [String: Any]) -> Result<Project, Outcome> {
        guard let token = args["project"] as? String, !token.isEmpty else {
            return .failure(err("CLI_USAGE_ERROR", "project required"))
        }
        guard let p = (try? ProjectStore().get(token)) ?? nil else {
            return .failure(err("PROJECT_NOT_FOUND", "project not found: \(token)"))
        }
        return .success(p)
    }

    private static func packet(for project: Project) -> ProjectContextPacket {
        let threads = ThreadStore().list().filter { $0.projectId == project.id }.sorted { $0.updatedAt > $1.updatedAt }
        let pending = ((try? PendingStore().loadAll()) ?? []).filter { $0.projectId == project.id }
        return ProjectContextPacketBuilder.build(
            project: project,
            recentThreadSummaries: threads.prefix(10).map { "\($0.title) [\($0.status.rawValue)]" },
            pendingItems: pending.prefix(10).map { "\($0.title) [\($0.status.rawValue)]" })
    }

    private static func boolArg(_ v: Any?) -> Bool {
        switch v {
        case let b as Bool: return b
        case let s as String: return ["true", "1", "yes"].contains(s.lowercased())
        case let n as NSNumber: return n.boolValue
        default: return false
        }
    }

    // MARK: - Read tools

    static func list(args: [String: Any]) -> Outcome {
        let store = ProjectStore()
        let projects = (boolArg(args["all"]) ? (try? store.list()) : (try? store.activeProjects())) ?? []
        return .success(AllnighterCLI.jsonString(ProjectListJSON(contractVersion: cv(), projects: projects)),
                        summary: "\(projects.count) project(s)")
    }

    static func get(args: [String: Any]) -> Outcome {
        switch project(args) {
        case .failure(let o): return o
        case .success(let p):
            let refreshed = (try? ProjectStore().refreshObservation(id: p.id)) ?? p
            return .success(AllnighterCLI.jsonString(ProjectJSON(contractVersion: cv(), project: refreshed ?? p)),
                            summary: (refreshed ?? p).displayName)
        }
    }

    static func context(args: [String: Any]) -> Outcome {
        switch project(args) {
        case .failure(let o): return o
        case .success(let p):
            let pkt = packet(for: p)
            return .success(AllnighterCLI.jsonString(ProjectContextJSON(contractVersion: cv(), packet: pkt)),
                            summary: "context for \(p.displayName) — \(pkt.workers.readinessSummary)")
        }
    }

    static func workers(args: [String: Any]) -> Outcome {
        switch project(args) {
        case .failure(let o): return o
        case .success(let p):
            let cached = ProjectWorkerReadinessStore().load(projectId: p.id)
            return .success(workersJSON(project: p, workers: cached, cached: true), summary: summary(cached))
        }
    }

    static func recheckWorkers(args: [String: Any], runtime: ToolRuntime) async -> Outcome {
        switch project(args) {
        case .failure(let o): return o
        case .success(let p):
            let detector = ProjectWorkerReadinessDetector(runner: SubprocessCommandRunner())
            let now = Date()
            var results: [ProjectWorkerReadiness] = []
            for manifest in runtime.registry.all.sorted(by: { $0.id < $1.id }) {
                results.append(await detector.detect(projectId: p.id, rootPath: p.normalizedRootPath,
                                                     manifest: manifest, probeKind: .explicitRecheck, now: now))
            }
            try? ProjectWorkerReadinessStore().save(projectId: p.id, results)
            return .success(workersJSON(project: p, workers: results, cached: false), summary: summary(results))
        }
    }

    static func proposals(args: [String: Any]) -> Outcome {
        switch project(args) {
        case .failure(let o): return o
        case .success(let p):
            let proposals = ProjectProposalStore().load(projectId: p.id)
            return .success(AllnighterCLI.jsonString(ProjectProposalsJSON(contractVersion: cv(), projectId: p.id, proposals: proposals)),
                            summary: "\(proposals.count) proposal(s)")
        }
    }

    // MARK: - Manager tools (model invocation)

    static func chat(args: [String: Any], runtime: ToolRuntime) async -> Outcome {
        switch project(args) {
        case .failure(let o): return o
        case .success(let p):
            guard let message = (args["message"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines), !message.isEmpty else {
                return err("CLI_USAGE_ERROR", "message required")
            }
            let svc = ProjectManagerService(runner: SubprocessCommandRunner(), registry: runtime.registry, invocations: runtime.invocations)
            let turn = await svc.chat(project: p, packet: packet(for: p), message: message, readyModels: runtime.readyModels)
            try? ProjectManagerTurnStore().append(turn)
            return .success(AllnighterCLI.jsonString(ProjectManagerTurnJSON(contractVersion: cv(), turn: turn)),
                            summary: "manager \(turn.mode.rawValue)")
        }
    }

    static func propose(args: [String: Any], runtime: ToolRuntime) async -> Outcome {
        switch project(args) {
        case .failure(let o): return o
        case .success(let p):
            let svc = ProjectManagerService(runner: SubprocessCommandRunner(), registry: runtime.registry, invocations: runtime.invocations)
            let result = await svc.propose(project: p, packet: packet(for: p), readyModels: runtime.readyModels)
            try? ProjectManagerTurnStore().append(result.turn)
            if let proposal = result.proposal { try? ProjectProposalStore().append(proposal) }
            return .success(AllnighterCLI.jsonString(ProjectProposalJSON(contractVersion: cv(), proposal: result.proposal, turn: result.turn, nextActions: result.turn.nextActions)),
                            summary: result.proposal.map { "proposal: \($0.title)" } ?? "blocked: \(result.turn.warnings.first ?? "")")
        }
    }

    // MARK: - Dispatch tools (caller, not approver)

    static func handoff(args: [String: Any], runtime: ToolRuntime) -> Outcome {
        guard let woId = args["workOrder"] as? String, !woId.isEmpty else { return err("CLI_USAGE_ERROR", "workOrder required") }
        guard let order = ProjectWorkOrderStore().find(id: woId) else { return err("WORK_ORDER_NOT_FOUND", "work order not found: \(woId)") }
        guard let p = (try? ProjectStore().load(id: order.projectId)) ?? nil else { return err("PROJECT_NOT_FOUND", "project not found: \(order.projectId)") }
        let proposal = ProjectProposalStore().get(projectId: order.projectId, proposalId: order.proposalId)
        guard proposal?.status == .approved else { return err("PROPOSAL_NOT_APPROVED", "the proposal behind \(woId) is not approved") }

        let sourceId = resolveSource(order: order, workerArg: args["worker"] as? String, readyModels: runtime.readyModels)
        var preview = order; preview.mode = .dispatch; if let sourceId { preview.targetSourceId = sourceId }
        let git = GitObserver()
        let gate = ProjectMutatingDispatchEvaluator.evaluate(
            workOrder: preview, project: p, proposal: proposal,
            observedRootState: RootNormalization.observeRootState(key: p.normalizedRootPath),
            dirtyFiles: git.dirtyFiles(rootPath: p.normalizedRootPath), dirtyAcknowledged: boolArg(args["ackDirty"]),
            workerReadiness: ProjectWorkerReadinessStore().load(projectId: p.id), readyModels: runtime.readyModels,
            currentGitHead: git.observe(rootPath: p.normalizedRootPath).head, teams: runtime.teams, registry: runtime.registry)
        let dp: ProjectHandoffJSON.DispatchPreview
        if case .allowed(_, let warnings) = gate { dp = .init(wouldDispatch: true, warnings: warnings) }
        else { dp = .init(wouldDispatch: false, blockerCode: gate.primaryErrorCode, message: gate.message) }
        return .success(AllnighterCLI.jsonString(ProjectHandoffJSON(
            contractVersion: cv(), workOrder: order, revealMarkdown: WorkOrderBuilder.revealMarkdown(order),
            resolvedSourceId: sourceId, dispatchPreview: dp)), summary: dp.wouldDispatch ? "ready to dispatch" : "blocked: \(dp.blockerCode ?? "")")
    }

    static func dispatch(args: [String: Any], runtime: ToolRuntime) async -> Outcome {
        guard let woId = args["workOrder"] as? String, !woId.isEmpty else { return err("CLI_USAGE_ERROR", "workOrder required") }
        guard let order = ProjectWorkOrderStore().find(id: woId) else { return err("WORK_ORDER_NOT_FOUND", "work order not found: \(woId)") }
        guard let p = (try? ProjectStore().load(id: order.projectId)) ?? nil else { return err("PROJECT_NOT_FOUND", "project not found: \(order.projectId)") }
        let proposalStore = ProjectProposalStore()
        let proposal = proposalStore.get(projectId: order.projectId, proposalId: order.proposalId)
        guard proposal?.status == .approved else { return err("PROPOSAL_NOT_APPROVED", "the proposal behind \(woId) is not approved") }
        let sourceId = resolveSource(order: order, workerArg: args["worker"] as? String, readyModels: runtime.readyModels)
        guard let model = resolveModel(order: order, workerArg: args["worker"] as? String, readyModels: runtime.readyModels) else {
            return err("WORKER_NOT_READY_IN_PROJECT", "no ready worker resolves; recheck workers or pass worker")
        }
        var dispatchOrder = order; dispatchOrder.mode = .dispatch; dispatchOrder.targetSourceId = sourceId
        let git = GitObserver()
        let service = ProjectDispatchService(runner: SubprocessCommandRunner(), registry: runtime.registry, invocations: runtime.invocations)
        let outcome = await service.dispatch(
            order: dispatchOrder, project: p, proposal: proposal, targetModel: model,
            workerReadiness: ProjectWorkerReadinessStore().load(projectId: p.id), readyModels: runtime.readyModels,
            currentGitHead: git.observe(rootPath: p.normalizedRootPath).head,
            dirtyFiles: git.dirtyFiles(rootPath: p.normalizedRootPath),
            observedRootState: RootNormalization.observeRootState(key: p.normalizedRootPath),
            dirtyAcknowledged: boolArg(args["ackDirty"]), teams: runtime.teams)
        switch outcome {
        case .blocked(let code, let message): return err(code, message)
        case .laneBusy(let key): return err("EXECUTION_LANE_BUSY", "another execute order is running on this lane (\(key))", retryable: true)
        case .dispatched(let ret):
            try? WorkReturnStore().append(ret)
            try? ProjectWorkOrderStore().upsert(dispatchOrder)
            if var pr = proposal { pr.status = ret.status == .returned ? .returned : .blocked; pr.updatedAt = Date(); try? proposalStore.update(pr) }
            let status = ret.status == .returned ? "returned" : "blocked"
            return .success(AllnighterCLI.jsonString(ProjectDispatchJSON(
                contractVersion: cv(), workReturn: ret, workOrder: dispatchOrder, proposalStatus: status)),
                summary: "dispatch \(ret.status.rawValue)")
        }
    }

    static func verify(args: [String: Any]) async -> Outcome {
        switch project(args) {
        case .failure(let o): return o
        case .success(let p):
            let woStore = ProjectWorkOrderStore()
            let order: WorkOrder? = (args["workOrder"] as? String).flatMap { woStore.find(id: $0) } ?? woStore.load(projectId: p.id).last
            guard let workOrder = order else { return err("WORK_ORDER_NOT_FOUND", "no work order to verify in \(p.displayName)") }
            let returns = WorkReturnStore().load(projectId: p.id).filter { $0.workOrderId == workOrder.id }
            let workReturn = (args["return"] as? String).flatMap { rid in returns.first { $0.id == rid } } ?? returns.last
            let now = Date()
            let record: VerificationRecord
            if let reason = args["waive"] as? String {
                record = VerificationRecord(id: "ver_" + UUID().uuidString.prefix(8).lowercased(), projectId: p.id,
                    workOrderId: workOrder.id, returnId: workReturn?.id, outcome: .waived, proofResults: [],
                    gitObservation: nil, scopeFindings: [], docsDriftFindings: [], missingProof: [],
                    recommendation: "Proof waived by caller: \(reason)", createdAt: now)
            } else {
                record = await ProjectVerificationService(runner: SubprocessCommandRunner())
                    .verify(workOrder: workOrder, workReturn: workReturn, project: p, runProof: !boolArg(args["noRun"]))
            }
            try? VerificationStore().append(record)
            var proposalStatus: String?
            let proposalStore = ProjectProposalStore()
            if var proposal = proposalStore.get(projectId: p.id, proposalId: workOrder.proposalId) {
                if record.outcome.isDone, proposal.status.canTransition(to: ProposalStatus.verified) {
                    proposal.status = ProposalStatus.verified; proposal.updatedAt = now; try? proposalStore.update(proposal)
                }
                proposalStatus = proposal.status.rawValue
            }
            return .success(AllnighterCLI.jsonString(ProjectVerificationJSON(contractVersion: cv(), verification: record, proposalStatus: proposalStatus)),
                            summary: "verify \(record.outcome.rawValue)")
        }
    }

    // MARK: - Shared resolution

    private static func resolveSource(order: WorkOrder, workerArg: String?, readyModels: [Model]) -> String? {
        if let wid = workerArg, let m = readyModels.first(where: { $0.id == wid }) { return m.driverId }
        if let src = order.resolvedTargetSourceId { return src }
        return readyModels.max { ModelCatalog.capabilities($0.id).strengthRank < ModelCatalog.capabilities($1.id).strengthRank }?.driverId
    }

    private static func resolveModel(order: WorkOrder, workerArg: String?, readyModels: [Model]) -> Model? {
        if let wid = workerArg, let m = readyModels.first(where: { $0.id == wid }) { return m }
        if let src = order.resolvedTargetSourceId, let m = readyModels.first(where: { $0.driverId == src }) { return m }
        return readyModels.max { ModelCatalog.capabilities($0.id).strengthRank < ModelCatalog.capabilities($1.id).strengthRank }
    }

    private static func summary(_ w: [ProjectWorkerReadiness]) -> String {
        let ready = w.filter { $0.status == .ready }.count
        return "\(ready) ready · \(w.count - ready) blocked"
    }

    private static func workersJSON(project: Project, workers: [ProjectWorkerReadiness], cached: Bool) -> String {
        AllnighterCLI.jsonString(ProjectWorkersJSON(contractVersion: cv(), projectId: project.id,
            readinessSummary: summary(workers), cached: cached, workers: workers))
    }
}
