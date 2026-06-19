import Foundation
import AllnighterCore

/// PRJ-S08: produces one `ProjectManagerTurn` for a chat message in a Project.
///
/// The Manager is a **model invocation**, not hand-written logic and not a shell
/// in the repo — it reuses the same `WorkerRunner` and model resolution as team
/// runs (no new execution path). It answers from the `ProjectContextPacket`; it
/// never invents Project truth, and it does not auto-create work (Chat Law: a turn
/// may answer only). With no ready manager model the turn is `mode: .wait` with a
/// sourced readiness blocker — never a fabricated answer.
public struct ProjectManagerService: Sendable {
    private let runner: CommandRunner
    private let registry: DriverRegistry
    private let invocations: [String: ToolInvocation]
    private let now: @Sendable () -> Date

    public init(
        runner: CommandRunner,
        registry: DriverRegistry,
        invocations: [String: ToolInvocation] = [:],
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.runner = runner
        self.registry = registry
        self.invocations = invocations
        self.now = now
    }

    /// Resolve the manager model: the Project's pinned `managerModelId` when it is
    /// ready, else the strongest ready planner-capable model. Nil ⇒ wait turn.
    public static func resolveManagerModel(project: Project, readyModels: [Model]) -> Model? {
        if let pinned = project.managerModelId,
           let model = readyModels.first(where: { $0.id == pinned }) {
            return model
        }
        return readyModels
            .filter { ModelCatalog.capabilities($0.id).capabilityTags.contains(.planner) }
            .max { ModelCatalog.capabilities($0.id).strengthRank < ModelCatalog.capabilities($1.id).strengthRank }
    }

    /// Produce one Manager turn. `packet` is the regenerated context receipt the
    /// model reasons over; `readyModels` is the ready Bench.
    public func chat(
        project: Project,
        packet: ProjectContextPacket,
        message: String,
        readyModels: [Model],
        userMessageId: String? = nil
    ) async -> ProjectManagerTurn {
        let at = now()
        let turnId = "mgr_" + UUID().uuidString.prefix(8).lowercased()
        let threadId = project.managerThreadId ?? "mgr_thread_\(project.id)"
        let userMsgId = userMessageId ?? "umsg_" + UUID().uuidString.prefix(8).lowercased()

        func waitTurn(_ warning: String) -> ProjectManagerTurn {
            ProjectManagerTurn(
                id: turnId, projectId: project.id, threadId: threadId, userMessageId: userMsgId,
                createdAt: at, mode: .wait, contextPacketId: packet.id, answerMarkdown: nil,
                warnings: [warning],
                nextActions: [.init(kind: .recheckWorkers, label: "Recheck workers", command: "alln project recheck-workers \(project.id) --json")]
            )
        }

        guard let model = Self.resolveManagerModel(project: project, readyModels: readyModels) else {
            return waitTurn("No ready manager model. Enable a ready planner-capable model (`alln models --json`); the Manager will not fabricate an answer.")
        }
        guard let manifest = registry.manifest(for: model) else {
            return waitTurn("Manager model \(model.id) has no driver manifest; cannot run.")
        }

        let prompt = Self.buildPrompt(packet: packet, message: message)
        let outcome = await WorkerRunner(commandRunner: runner, invocations: invocations, now: now)
            .invoke(worker: model, manifest: manifest, prompt: prompt, effort: .med)

        guard outcome.hasOutput, let answer = outcome.output else {
            // The model ran but failed/empty — surface the reason, never invent one.
            let reason = outcome.errorReason ?? "no output"
            return waitTurn("Manager model \(model.id) did not answer (\(reason)). Retry or pick another model.")
        }

        return ProjectManagerTurn(
            id: turnId, projectId: project.id, threadId: threadId, userMessageId: userMsgId,
            createdAt: at, mode: .answer, contextPacketId: packet.id,
            answerMarkdown: answer.trimmingCharacters(in: .whitespacesAndNewlines),
            modelId: model.id,
            warnings: packet.warnings,
            nextActions: [.init(kind: .projectContext, label: "Refresh project context", command: "alln project context \(project.id) --json")]
        )
    }

    // MARK: - Prompt assembly (built-in persona snapshot)

    /// The built-in Manager persona. Static catalog content (not editable prose
    /// that can redefine semantics): answer from Project truth, name uncertainty,
    /// do not invent facts, do not propose/dispatch unless asked.
    static let persona = """
    You are the Project Manager for a local software project in Allnighter. You answer \
    the user's question using ONLY the project context below as ground truth. Rules:
    - Answer directly and concisely in Markdown. A plain question gets a plain answer.
    - Ground every claim in the provided context. If the context does not say, state \
    that you don't know rather than inventing facts, commits, files, or status.
    - Surface important uncertainty, dirty state, failed proof, or blocked workers — \
    never hide them.
    - Do NOT propose work, create a work order, or dispatch anything unless the user \
    explicitly asks "what should we do next" or to make/run work. A normal question \
    gets only an answer.
    """

    static func buildPrompt(packet: ProjectContextPacket, message: String) -> String {
        """
        \(persona)

        # Project context (source-labeled; generated \(iso(packet.generatedAt)))
        \(renderPacket(packet))

        # User message
        \(message)
        """
    }

    static func renderPacket(_ p: ProjectContextPacket) -> String {
        var lines: [String] = []
        lines.append("- root: \(p.root.localRootPath) [\(p.root.kind.rawValue), \(p.root.rootState.rawValue)]")
        let git = p.git
        lines.append("- git: branch=\(git.branch ?? "—") head=\(git.head?.prefix(8).description ?? "—") dirty=\(git.dirtySummary ?? "clean")")
        if !git.recentCommits.isEmpty { lines.append("- recent commits:\n" + git.recentCommits.map { "    - \($0)" }.joined(separator: "\n")) }
        if !p.docs.entrypoints.isEmpty { lines.append("- docs entrypoints: \(p.docs.entrypoints.joined(separator: ", "))") }
        if !p.threads.recentThreadSummaries.isEmpty { lines.append("- recent threads:\n" + p.threads.recentThreadSummaries.map { "    - \($0)" }.joined(separator: "\n")) }
        if !p.work.pendingItems.isEmpty { lines.append("- pending:\n" + p.work.pendingItems.map { "    - \($0)" }.joined(separator: "\n")) }
        lines.append("- workers: \(p.workers.readinessSummary)")
        if !p.workers.blockedWorkerSummaries.isEmpty { lines.append("    blocked: \(p.workers.blockedWorkerSummaries.joined(separator: ", "))") }
        if !p.proof.commands.isEmpty { lines.append("- proof commands: \(p.proof.commands.joined(separator: ", "))") }
        if !p.warnings.isEmpty { lines.append("- warnings:\n" + p.warnings.map { "    - \($0)" }.joined(separator: "\n")) }
        return lines.joined(separator: "\n")
    }

    private static func iso(_ date: Date) -> String {
        let f = ISO8601DateFormatter()
        return f.string(from: date)
    }
}
