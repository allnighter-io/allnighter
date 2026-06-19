import Foundation
import AllnighterCore
import AllnighterEngine

/// PRJ-S13: MCP projection of the project-scoped CLI. These handlers call the SAME
/// Engine services + stores and emit the SAME `Project*JSON` envelopes as `alln
/// project …` — no MCP-only semantics.
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

    private static func buildContextPacket(
        project: Project,
        recentThreadSummaries: [String],
        pendingItems: [String]
    ) -> ProjectContextPacket {
        let git = GitObserver()
        let rootState = RootNormalization.observeRootState(key: project.normalizedRootPath)
        let obs = git.observe(rootPath: project.normalizedRootPath)
        let recentCommits = git.recentCommits(rootPath: project.normalizedRootPath, limit: 5)
        let readiness = ProjectWorkerReadinessStore().load(projectId: project.id)
        let ready = readiness.filter { $0.status == .ready }
        let blocked = readiness.filter { $0.status != .ready }
        let workers = ProjectContextPacket.Workers(
            readinessSummary: "\(ready.count) ready · \(blocked.count) blocked",
            readyWorkerIds: ready.map { $0.workerId ?? $0.sourceId },
            blockedWorkerSummaries: blocked.map { "\($0.sourceId): \($0.status.rawValue)" }
        )
        var warnings: [String] = []
        if rootState != .available { warnings.append("root \(rootState.rawValue): \(project.localRootPath)") }
        if let dirty = obs.dirtySummary { warnings.append("dirty tree: \(dirty)") }
        for summary in blocked { warnings.append("worker blocked — \(summary.sourceId): \(summary.status.rawValue)") }
        return ProjectContextPacket(
            id: "pkt_" + UUID().uuidString.prefix(8).lowercased(),
            projectId: project.id,
            generatedAt: Date(),
            root: .init(localRootPath: project.localRootPath, kind: obs.kind, rootState: rootState),
            git: .init(branch: obs.branch, head: obs.head, remote: obs.remote,
                       dirtySummary: obs.dirtySummary, recentCommits: Array(recentCommits.prefix(10))),
            docs: .init(entrypoints: project.docsEntrypoints),
            threads: .init(managerThreadId: project.managerThreadId,
                           recentThreadSummaries: Array(recentThreadSummaries.prefix(10))),
            work: .init(pendingItems: Array(pendingItems.prefix(10))),
            workers: workers,
            proof: .init(commands: project.proofCommands),
            warnings: warnings
        )
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
            let threads = ThreadStore().list().filter { $0.projectId == p.id }.sorted { $0.updatedAt > $1.updatedAt }
            let pending = ((try? PendingStore().loadAll()) ?? []).filter { $0.projectId == p.id }
            let pkt = buildContextPacket(
                project: p,
                recentThreadSummaries: threads.prefix(10).map { "\($0.title) [\($0.status.rawValue)]" },
                pendingItems: pending.prefix(10).map { "\($0.title) [\($0.status.rawValue)]" }
            )
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

    private static func summary(_ w: [ProjectWorkerReadiness]) -> String {
        let ready = w.filter { $0.status == .ready }.count
        return "\(ready) ready · \(w.count - ready) blocked"
    }

    private static func workersJSON(project: Project, workers: [ProjectWorkerReadiness], cached: Bool) -> String {
        AllnighterCLI.jsonString(ProjectWorkersJSON(contractVersion: cv(), projectId: project.id,
            readinessSummary: summary(workers), cached: cached, workers: workers))
    }
}
