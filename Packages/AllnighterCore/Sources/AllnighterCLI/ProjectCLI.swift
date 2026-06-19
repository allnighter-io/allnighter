import Foundation
import AllnighterCore
import AllnighterEngine

/// `alln project …` — the Project-first CLI foundation (PRJ-S07). Boring on
/// purpose: list/add/show/archive the local work floors, and read the threads,
/// pending, and on-demand context bound to one Project. Manager chat, proposals,
/// dispatch, and verification are later slices (PRJ-S08+); worker readiness
/// (workers/recheck-workers) lands in the S07 follow-up. Every JSON envelope is a
/// projection of Core truth via `ProjectJSON` — the registry owns the contract.
enum ProjectCLI {
    static func run(_ subcommand: String?, _ args: [String], runtime: ToolRuntime) async {
        switch subcommand {
        case "list": runList(args)
        case "add": runAdd(args)
        case "show": runShow(args)
        case "archive": runArchive(args)
        case "unarchive": runUnarchive(args)
        case "threads": runThreads(args)
        case "pending": runPending(args)
        case "context": runContext(args)
        case "workers": runWorkers(args)
        case "recheck-workers": await runRecheck(args, runtime)
        case "chat": await runChat(args, runtime)
        case "propose": await runPropose(args, runtime)
        case "proposals": runProposals(args)
        case nil:
            FileHandle.standardError.write(Data("usage: alln project <list|add|show|archive|unarchive|threads|pending|context|workers|recheck-workers|chat|propose|proposals> ...\n".utf8))
            exit(2)
        default:
            FileHandle.standardError.write(Data("unknown project subcommand: \(subcommand!)\n".utf8))
            exit(2)
        }
    }

    // MARK: - Commands

    private static func runList(_ args: [String]) {
        let opts = Options(args)
        let store = ProjectStore()
        do {
            let projects = opts.flag("all") ? try store.list() : try store.activeProjects()
            if opts.flag("json") {
                let payload = ProjectListJSON(
                    contractVersion: ContractRegistry.contractVersion,
                    projects: projects,
                    nextActions: projects.isEmpty
                        ? [.init(kind: .addProject, label: "Add a project", command: "alln project add <path> --json")]
                        : []
                )
                print(AllnighterCLI.jsonString(payload))
            } else if projects.isEmpty {
                print("(no projects — `alln project add <path>`)")
            } else {
                for p in projects { print("\(p.id)\t\(p.archived ? "archived" : p.rootState.rawValue)\t\(p.displayName)\t\(p.localRootPath)") }
            }
        } catch {
            AllnighterCLI.fail(code: "INTERNAL_ERROR", message: String(describing: error))
        }
    }

    private static func runAdd(_ args: [String]) {
        let opts = Options(args)
        guard let path = opts.positional.first else {
            usageError("usage: alln project add <path> [--name <name>] [--json]")
        }
        let store = ProjectStore()
        do {
            // `add` is idempotent: the same normalized root returns the existing
            // Project rather than a duplicate (DUPLICATE_PROJECT_ROOT semantics).
            let project = try store.add(path: path, name: opts.value("name"))
            emitProject(project, json: opts.flag("json"))
        } catch {
            AllnighterCLI.fail(code: "INTERNAL_ERROR", message: String(describing: error))
        }
    }

    private static func runShow(_ args: [String]) {
        let opts = Options(args)
        guard let idOrName = opts.positional.first else { usageError("usage: alln project show <project-id-or-name> [--json]") }
        let store = ProjectStore()
        let project = resolve(idOrName, store)
        // Re-observe root/git so `show` reflects current truth, never the last save.
        let refreshed = (try? store.refreshObservation(id: project.id)) ?? project
        emitProject(refreshed ?? project, json: opts.flag("json"))
    }

    private static func runArchive(_ args: [String]) {
        let opts = Options(args)
        guard let idOrName = opts.positional.first else { usageError("usage: alln project archive <project-id-or-name> [--json]") }
        let store = ProjectStore()
        let project = resolve(idOrName, store)
        do {
            guard let archived = try store.archive(id: project.id) else {
                AllnighterCLI.fail(code: "PROJECT_NOT_FOUND", message: "project not found: \(idOrName)")
            }
            emitProject(archived, json: opts.flag("json"))
        } catch {
            AllnighterCLI.fail(code: "INTERNAL_ERROR", message: String(describing: error))
        }
    }

    private static func runUnarchive(_ args: [String]) {
        let opts = Options(args)
        guard let idOrName = opts.positional.first else { usageError("usage: alln project unarchive <project-id-or-name> [--json]") }
        let store = ProjectStore()
        let project = resolve(idOrName, store)
        do {
            guard let restored = try store.unarchive(id: project.id) else {
                AllnighterCLI.fail(code: "PROJECT_NOT_FOUND", message: "project not found: \(idOrName)")
            }
            emitProject(restored, json: opts.flag("json"))
        } catch {
            AllnighterCLI.fail(code: "INTERNAL_ERROR", message: String(describing: error))
        }
    }

    private static func runThreads(_ args: [String]) {
        let opts = Options(args)
        guard let idOrName = opts.positional.first else { usageError("usage: alln project threads <project-id-or-name> [--json]") }
        let store = ProjectStore()
        let project = resolve(idOrName, store)
        let threads = boundThreads(projectId: project.id)
        if opts.flag("json") {
            let payload = ProjectThreadsJSON(
                contractVersion: ContractRegistry.contractVersion,
                projectId: project.id,
                threads: threads.map(threadSummary),
                nextActions: [.init(kind: .projectContext, label: "Project context", command: "alln project context \(project.id) --json")]
            )
            print(AllnighterCLI.jsonString(payload))
        } else if threads.isEmpty {
            print("(no threads in \(project.displayName))")
        } else {
            for t in threads { print("\(t.id)\t\(t.status.rawValue)\t\(t.hasUnread ? "•" : " ")\t\(t.title)") }
        }
    }

    private static func runPending(_ args: [String]) {
        let opts = Options(args)
        guard let idOrName = opts.positional.first else { usageError("usage: alln project pending <project-id-or-name> [--json]") }
        let store = ProjectStore()
        let project = resolve(idOrName, store)
        let items = boundPending(projectId: project.id)
        if opts.flag("json") {
            let payload = ProjectPendingJSON(
                contractVersion: ContractRegistry.contractVersion,
                projectId: project.id,
                items: items.map { ProjectPendingSummary(id: $0.id, title: $0.title, status: $0.status.rawValue, needsAttention: $0.status == .failed) }
            )
            print(AllnighterCLI.jsonString(payload))
        } else if items.isEmpty {
            print("(no pending work in \(project.displayName))")
        } else {
            for i in items { print("\(i.id)\t\(i.status.rawValue)\t\(i.title)") }
        }
    }

    private static func runContext(_ args: [String]) {
        let opts = Options(args)
        guard let idOrName = opts.positional.first else { usageError("usage: alln project context <project-id-or-name> [--json]") }
        let store = ProjectStore()
        let project = resolve(idOrName, store)
        let threads = boundThreads(projectId: project.id)
        let pending = boundPending(projectId: project.id)
        // Real source-labeled summaries — no fabricated activity. Runs/proposals/
        // returns wire in later slices; the builder leaves them empty until then.
        let packet = ProjectContextPacketBuilder.build(
            project: project,
            recentThreadSummaries: threads.prefix(10).map { "\($0.title) [\($0.status.rawValue)]" },
            pendingItems: pending.prefix(10).map { "\($0.title) [\($0.status.rawValue)]" }
        )
        if opts.flag("json") {
            let payload = ProjectContextJSON(contractVersion: ContractRegistry.contractVersion, packet: packet)
            print(AllnighterCLI.jsonString(payload))
        } else {
            print("\(project.displayName) — \(packet.workers.readinessSummary)")
            for w in packet.warnings { print("⚠︎ \(w)") }
        }
    }

    /// Cached readiness — read-only, never probes (silent probes are background work).
    private static func runWorkers(_ args: [String]) {
        let opts = Options(args)
        guard let idOrName = opts.positional.first else { usageError("usage: alln project workers <project-id-or-name> [--json]") }
        let store = ProjectStore()
        let project = resolve(idOrName, store)
        let cached = ProjectWorkerReadinessStore().load(projectId: project.id)
        emitWorkers(project: project, workers: cached, cached: true, json: opts.flag("json"))
    }

    /// Reruns only driver-declared safe probes, rewrites the cache, and reports the
    /// fresh facts. Never accepts trust prompts, logs in, or writes vendor config.
    private static func runRecheck(_ args: [String], _ runtime: ToolRuntime) async {
        let opts = Options(args)
        guard let idOrName = opts.positional.first else { usageError("usage: alln project recheck-workers <project-id-or-name> [--json]") }
        let store = ProjectStore()
        let project = resolve(idOrName, store)
        let detector = ProjectWorkerReadinessDetector(runner: SubprocessCommandRunner())
        let now = Date()
        var results: [ProjectWorkerReadiness] = []
        for manifest in runtime.registry.all.sorted(by: { $0.id < $1.id }) {
            let r = await detector.detect(
                projectId: project.id,
                rootPath: project.normalizedRootPath,
                manifest: manifest,
                probeKind: .explicitRecheck,
                now: now
            )
            results.append(r)
        }
        try? ProjectWorkerReadinessStore().save(projectId: project.id, results)
        emitWorkers(project: project, workers: results, cached: false, json: opts.flag("json"))
    }

    /// Project Manager chat (PRJ-S08): one model-produced turn answered from the
    /// project context packet. No ready model → a `wait` turn (never fabricated).
    /// Recorded as run truth in the Manager turn log. Does not auto-create work.
    private static func runChat(_ args: [String], _ runtime: ToolRuntime) async {
        let opts = Options(args)
        guard let idOrName = opts.positional.first else {
            usageError("usage: alln project chat <project-id-or-name> [message] [--file <path>] [--json]")
        }
        let message = opts.value("message")
            ?? opts.value("file").flatMap { try? String(contentsOfFile: $0) }
            ?? opts.positional.dropFirst().joined(separator: " ")
        guard !message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            usageError("project chat requires a message (positional or --file)")
        }
        let store = ProjectStore()
        let project = resolve(idOrName, store)
        let threads = boundThreads(projectId: project.id)
        let pending = boundPending(projectId: project.id)
        let packet = ProjectContextPacketBuilder.build(
            project: project,
            recentThreadSummaries: threads.prefix(10).map { "\($0.title) [\($0.status.rawValue)]" },
            pendingItems: pending.prefix(10).map { "\($0.title) [\($0.status.rawValue)]" }
        )
        let service = ProjectManagerService(
            runner: SubprocessCommandRunner(),
            registry: runtime.registry,
            invocations: runtime.invocations
        )
        let turn = await service.chat(
            project: project, packet: packet, message: message, readyModels: runtime.readyModels
        )
        // Record run truth (the Manager turn log) regardless of mode.
        try? ProjectManagerTurnStore().append(turn)
        if opts.flag("json") {
            print(AllnighterCLI.jsonString(ProjectManagerTurnJSON(contractVersion: ContractRegistry.contractVersion, turn: turn)))
        } else if turn.mode == .wait {
            for w in turn.warnings { FileHandle.standardError.write(Data("⏸ \(w)\n".utf8)) }
        } else {
            print(turn.answerMarkdown ?? "")
        }
    }

    /// Proposal engine (PRJ-S09): one bounded next move or one visible blocker.
    /// No dispatch, no approval. Persists the proposal + records the propose turn.
    private static func runPropose(_ args: [String], _ runtime: ToolRuntime) async {
        let opts = Options(args)
        guard let idOrName = opts.positional.first else { usageError("usage: alln project propose <project-id-or-name> [--json]") }
        let store = ProjectStore()
        let project = resolve(idOrName, store)
        let threads = boundThreads(projectId: project.id)
        let pending = boundPending(projectId: project.id)
        let packet = ProjectContextPacketBuilder.build(
            project: project,
            recentThreadSummaries: threads.prefix(10).map { "\($0.title) [\($0.status.rawValue)]" },
            pendingItems: pending.prefix(10).map { "\($0.title) [\($0.status.rawValue)]" }
        )
        let service = ProjectManagerService(
            runner: SubprocessCommandRunner(), registry: runtime.registry, invocations: runtime.invocations)
        let result = await service.propose(project: project, packet: packet, readyModels: runtime.readyModels)
        try? ProjectManagerTurnStore().append(result.turn)
        if let proposal = result.proposal { try? ProjectProposalStore().append(proposal) }
        if opts.flag("json") {
            print(AllnighterCLI.jsonString(ProjectProposalJSON(
                contractVersion: ContractRegistry.contractVersion,
                proposal: result.proposal, turn: result.turn, nextActions: result.turn.nextActions)))
        } else if let p = result.proposal {
            print("\(p.id)\t\(p.kind.rawValue)\t\(p.title)")
            if !p.whyNow.isEmpty { print("why now: \(p.whyNow)") }
        } else {
            for w in result.turn.warnings { FileHandle.standardError.write(Data("⏸ \(w)\n".utf8)) }
        }
    }

    private static func runProposals(_ args: [String]) {
        let opts = Options(args)
        guard let idOrName = opts.positional.first else { usageError("usage: alln project proposals <project-id-or-name> [--json]") }
        let store = ProjectStore()
        let project = resolve(idOrName, store)
        let proposals = ProjectProposalStore().load(projectId: project.id)
        if opts.flag("json") {
            print(AllnighterCLI.jsonString(ProjectProposalsJSON(
                contractVersion: ContractRegistry.contractVersion, projectId: project.id, proposals: proposals)))
        } else if proposals.isEmpty {
            print("(no proposals — `alln project propose \(project.id)`)")
        } else {
            for p in proposals { print("\(p.id)\t\(p.status.rawValue)\t\(p.kind.rawValue)\t\(p.title)") }
        }
    }

    // MARK: - Helpers

    private static func resolve(_ idOrName: String, _ store: ProjectStore) -> Project {
        do {
            guard let project = try store.get(idOrName) else {
                AllnighterCLI.fail(code: "PROJECT_NOT_FOUND", message: "project not found: \(idOrName)")
            }
            return project
        } catch {
            AllnighterCLI.fail(code: "INTERNAL_ERROR", message: String(describing: error))
        }
    }

    private static func boundThreads(projectId: String) -> [WorkThread] {
        ThreadStore().list()
            .filter { $0.projectId == projectId }
            .sorted { $0.updatedAt > $1.updatedAt }
    }

    private static func boundPending(projectId: String) -> [PendingItem] {
        ((try? PendingStore().loadAll()) ?? []).filter { $0.projectId == projectId }
    }

    private static func threadSummary(_ t: WorkThread) -> ProjectThreadSummary {
        ProjectThreadSummary(
            id: t.id, title: t.title, status: t.status.rawValue, updatedAt: t.updatedAt,
            pinned: t.isPinned, unread: t.hasUnread, unassigned: t.projectId == nil
        )
    }

    private static func emitProject(_ project: Project, json: Bool) {
        if json {
            let payload = ProjectJSON(
                contractVersion: ContractRegistry.contractVersion,
                project: project,
                nextActions: [
                    .init(kind: .projectContext, label: "Project context", command: "alln project context \(project.id) --json"),
                    .init(kind: .listThreads, label: "Project threads", command: "alln project threads \(project.id) --json"),
                ]
            )
            print(AllnighterCLI.jsonString(payload))
        } else {
            print("\(project.id)\t\(project.archived ? "archived" : project.rootState.rawValue)\t\(project.displayName)\t\(project.localRootPath)")
        }
    }

    private static func emitWorkers(project: Project, workers: [ProjectWorkerReadiness], cached: Bool, json: Bool) {
        let ready = workers.filter { $0.status == .ready }.count
        let summary = "\(ready) ready · \(workers.count - ready) blocked"
        if json {
            let payload = ProjectWorkersJSON(
                contractVersion: ContractRegistry.contractVersion,
                projectId: project.id,
                readinessSummary: summary,
                cached: cached,
                workers: workers,
                nextActions: [.init(kind: .recheckWorkers, label: "Recheck workers", command: "alln project recheck-workers \(project.id) --json")]
            )
            print(AllnighterCLI.jsonString(payload))
        } else if workers.isEmpty {
            print(cached ? "(no readiness cache — `alln project recheck-workers \(project.id)`)" : "(no workers probed)")
        } else {
            print("\(project.displayName) — \(summary)\(cached ? " (cached)" : "")")
            for w in workers { print("\(w.sourceId)\t\(w.status.rawValue)\t\(w.setupHint ?? "")") }
        }
    }

    private static func usageError(_ message: String) -> Never {
        FileHandle.standardError.write(Data("\(message)\n".utf8))
        exit(2)
    }
}
