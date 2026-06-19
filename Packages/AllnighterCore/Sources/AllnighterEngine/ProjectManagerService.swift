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

    // MARK: - Propose (PRJ-S09)

    /// The outcome of a propose call: at most one bounded proposal, plus the typed
    /// turn that produced it. A blocked/declined/no-model call yields a nil proposal
    /// and a `wait` turn with a sourced, visible blocker (never a guessed proposal).
    public struct ProposeOutcome: Sendable, Equatable {
        public var proposal: ProjectProposal?
        public var turn: ProjectManagerTurn
    }

    /// "What should we do next?" → one bounded `ProjectProposal` or one visible
    /// blocker. The model authors the proposal *content* as JSON; Allnighter stamps
    /// the durable fields (id, status, baseGitHead, timestamps) — never the model.
    /// This does NOT dispatch and does NOT approve (Readiness And Proposal Law).
    public func propose(
        project: Project,
        packet: ProjectContextPacket,
        readyModels: [Model],
        userMessageId: String? = nil
    ) async -> ProposeOutcome {
        let at = now()
        let turnId = "mgr_" + UUID().uuidString.prefix(8).lowercased()
        let threadId = project.managerThreadId ?? "mgr_thread_\(project.id)"
        let userMsgId = userMessageId ?? "umsg_" + UUID().uuidString.prefix(8).lowercased()

        func waitTurn(_ warning: String) -> ProposeOutcome {
            ProposeOutcome(proposal: nil, turn: ProjectManagerTurn(
                id: turnId, projectId: project.id, threadId: threadId, userMessageId: userMsgId,
                createdAt: at, mode: .wait, contextPacketId: packet.id, warnings: [warning],
                nextActions: [.init(kind: .recheckWorkers, label: "Recheck workers", command: "alln project recheck-workers \(project.id) --json")]))
        }

        guard let model = Self.resolveManagerModel(project: project, readyModels: readyModels) else {
            return waitTurn("No ready manager model. Enable a ready planner-capable model (`alln models --json`); no proposal will be guessed.")
        }
        guard let manifest = registry.manifest(for: model) else {
            return waitTurn("Manager model \(model.id) has no driver manifest; cannot run.")
        }

        let prompt = Self.buildProposePrompt(packet: packet)
        let outcome = await WorkerRunner(commandRunner: runner, invocations: invocations, now: now)
            .invoke(worker: model, manifest: manifest, prompt: prompt, effort: .med)

        guard outcome.hasOutput, let output = outcome.output else {
            return waitTurn("Manager model \(model.id) did not respond (\(outcome.errorReason ?? "no output")).")
        }
        guard let draft = Self.parseProposalDraft(output) else {
            return waitTurn("Manager model \(model.id) did not return a parseable proposal. Retry or ask in chat.")
        }
        // A model-declared blocker is a visible blocker, not a proposal.
        if let blocker = draft.blocker?.trimmingCharacters(in: .whitespacesAndNewlines), !blocker.isEmpty {
            return waitTurn(blocker)
        }
        guard let kindRaw = draft.kind, let kind = ProposalKind(rawValue: kindRaw),
              let title = draft.title?.trimmingCharacters(in: .whitespacesAndNewlines), !title.isEmpty else {
            return waitTurn("Manager model \(model.id) returned an incomplete proposal (missing kind/title). Retry or ask in chat.")
        }

        let proposalId = "prop_" + UUID().uuidString.prefix(8).lowercased()
        let proposal = ProjectProposal(
            id: proposalId, projectId: project.id, threadId: threadId, createdFromTurnId: turnId,
            kind: kind, status: .proposed, title: title,
            whyNow: draft.whyNow ?? "", userGoal: draft.userGoal ?? "",
            currentTruth: draft.currentTruth ?? [], scope: draft.scope ?? "",
            nonGoals: draft.nonGoals ?? [], likelyFilesOrAreas: draft.likelyFilesOrAreas ?? [],
            risks: draft.risks ?? [], blockingQuestions: draft.blockingQuestions ?? [],
            suggestedLane: draft.suggestedLane.flatMap { WorkLane(rawValue: $0.lowercased()) },
            suggestedTeamId: draft.suggestedTeamId,
            suggestedEffort: draft.suggestedEffort.flatMap { EffortLevel(rawValue: $0.lowercased()) },
            baseGitHead: packet.git.head, createdAt: at, updatedAt: at)

        let turn = ProjectManagerTurn(
            id: turnId, projectId: project.id, threadId: threadId, userMessageId: userMsgId,
            createdAt: at, mode: .propose, contextPacketId: packet.id, modelId: model.id,
            proposals: [proposalId], warnings: packet.warnings,
            nextActions: [
                .init(kind: .approve, label: "Approve", command: "alln project approve \(proposalId) --json"),
                .init(kind: .edit, label: "Edit", command: "alln project edit \(proposalId) --json"),
                .init(kind: .postpone, label: "Postpone", command: "alln project postpone \(proposalId) --json"),
            ])
        return ProposeOutcome(proposal: proposal, turn: turn)
    }

    /// The model-authored proposal fields (Allnighter stamps the rest). `blocker`
    /// lets the model honestly decline when facts don't decide or a gate is red.
    struct ProposalDraft: Decodable {
        var blocker: String?
        var kind: String?
        var title: String?
        var whyNow: String?
        var userGoal: String?
        var currentTruth: [String]?
        var scope: String?
        var nonGoals: [String]?
        var likelyFilesOrAreas: [String]?
        var risks: [String]?
        var blockingQuestions: [String]?
        var suggestedLane: String?
        var suggestedTeamId: String?
        var suggestedEffort: String?
    }

    /// Extract and decode the first balanced JSON object from possibly-noisy model
    /// output (CLIs wrap answers in prose/fences). Returns nil if none decodes.
    static func parseProposalDraft(_ output: String) -> ProposalDraft? {
        guard let json = firstJSONObject(in: output),
              let data = json.data(using: .utf8),
              let draft = try? JSONDecoder().decode(ProposalDraft.self, from: data)
        else { return nil }
        return draft
    }

    static func firstJSONObject(in text: String) -> String? {
        guard let start = text.firstIndex(of: "{") else { return nil }
        var depth = 0
        var inString = false
        var escaped = false
        var idx = start
        while idx < text.endIndex {
            let c = text[idx]
            if inString {
                if escaped { escaped = false }
                else if c == "\\" { escaped = true }
                else if c == "\"" { inString = false }
            } else {
                if c == "\"" { inString = true }
                else if c == "{" { depth += 1 }
                else if c == "}" {
                    depth -= 1
                    if depth == 0 { return String(text[start...idx]) }
                }
            }
            idx = text.index(after: idx)
        }
        return nil
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

    /// Built-in propose persona: produce ONE bounded next move as JSON, grounded in
    /// the context; decline with a blocker rather than guess. Legal kinds are fixed.
    static let proposePersona = """
    You are the Project Manager. Propose exactly ONE bounded next move for this \
    project, grounded ONLY in the context below. Output a SINGLE JSON object and \
    nothing else (no prose, no code fences).

    Schema:
    {
      "kind": one of [spec_explore, synthesis_review, execute_slice, docs_reconcile, verify_completion, audit, deslop, ask_user, wait],
      "title": short imperative title,
      "whyNow": why this is the right next move now (cite context),
      "userGoal": the user goal it advances,
      "currentTruth": [source-labeled facts it builds on],
      "scope": what is in scope (bounded),
      "nonGoals": [explicitly out of scope],
      "likelyFilesOrAreas": [paths/areas likely touched],
      "risks": [risks or unknowns],
      "blockingQuestions": [questions that must be answered first, if any],
      "suggestedLane": one of [code, design, copy] or omit,
      "suggestedEffort": one of [low, med, high] or omit
    }

    Rules: choose the cheapest safe move that advances the work. Do NOT invent \
    commits, files, or status not in the context. If the facts do not decide, or a \
    hard gate is red (dirty tree, missing root, no ready worker), instead return \
    {"blocker": "<one clear sentence naming the blocker>"}. Never dispatch or approve.
    """

    static func buildProposePrompt(packet: ProjectContextPacket) -> String {
        """
        \(proposePersona)

        # Project context (source-labeled; generated \(iso(packet.generatedAt)))
        \(renderPacket(packet))
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
