import Foundation
import AllnighterCore
import AgentOSTeam

/// Mirrors iOS-originated async team runs into `ThreadStore` so `alln serve` can
/// publish thread snapshots the phone actually reads. Without this, runs execute in
/// `AsyncTeamService` but the remote thread publisher stays empty.
public actor RemoteIOSThreadMirrorExecutor: RemoteTeamCommandExecuting {
    private struct ActiveMirror: Sendable {
        var threadId: String
        var workerTurnId: String
    }

    private let underlying: RemoteTeamCommandExecuting
    private let threadStore: ThreadStore
    private let runStore: RunStore
    private let idFactory: @Sendable () -> String
    private let now: @Sendable () -> Date
    private var activeMirrors: [String: ActiveMirror] = [:]

    public init(
        underlying: RemoteTeamCommandExecuting,
        threadStore: ThreadStore,
        runStore: RunStore,
        idFactory: @escaping @Sendable () -> String = { UUID().uuidString },
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.underlying = underlying
        self.threadStore = threadStore
        self.runStore = runStore
        self.idFactory = idFactory
        self.now = now
    }

    public func startRun(_ request: AsyncTeamStartRequest) async -> Result<TeamStartResponse, AsyncTeamStartRefusal> {
        let result = await underlying.startRun(request)
        guard case .success(let response) = result else { return result }
        mirrorAcceptedStart(request: request, runId: response.runId)
        Task { await self.settleWhenComplete(runId: response.runId) }
        return result
    }

    public func stopRun(runId: String) async -> TeamCancelResponse? {
        await underlying.stopRun(runId: runId)
    }

    public func stopAllRuns() async -> StopAllResult {
        await underlying.stopAllRuns()
    }

    private func mirrorAcceptedStart(request: AsyncTeamStartRequest, runId: String) {
        let timestamp = now()
        let prompt = request.question.trimmingCharacters(in: .whitespacesAndNewlines)
        let threadId = normalizedThreadId(request.threadId) ?? idFactory()
        let userTurnId = idFactory()
        let workerTurnId = idFactory()
        let modelId = resolvedModelId(from: request)

        do {
            if threadStore.get(threadId) == nil {
                _ = try threadStore.create(
                    id: threadId,
                    title: threadTitle(from: prompt),
                    now: timestamp,
                    defaultModelId: modelId
                )
            }

            let userTurn = ThreadTurn(
                id: userTurnId,
                threadId: threadId,
                kind: .userMessage,
                status: .done,
                createdAt: timestamp,
                completedAt: timestamp,
                author: .user,
                text: prompt
            )
            _ = try threadStore.appendTurn(userTurn, toThreadId: threadId, now: timestamp)

            let workerTurn = ThreadTurn(
                id: workerTurnId,
                threadId: threadId,
                kind: .workerChat,
                status: .running,
                createdAt: timestamp,
                author: .worker,
                text: "Working on this on your Mac…",
                modelId: modelId,
                runId: runId
            )
            _ = try threadStore.appendTurn(workerTurn, toThreadId: threadId, now: timestamp)
            activeMirrors[runId] = ActiveMirror(threadId: threadId, workerTurnId: workerTurnId)
        } catch {
            return
        }
    }

    private func settleWhenComplete(runId: String) async {
        for _ in 0..<1_800 {
            guard let mirror = activeMirrors[runId] else { return }
            guard let run = runStore.load(runId: runId) else {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                continue
            }

            if let partial = partialWorkerText(from: run) {
                try? updateWorkerTurn(
                    threadId: mirror.threadId,
                    workerTurnId: mirror.workerTurnId,
                    text: partial,
                    status: .running,
                    completedAt: nil
                )
            }

            guard run.status.isTerminal else {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                continue
            }

            let answer = run.answers.first
            let status = chatStatus(for: answer?.result.status ?? .failed)
            let text = settlementText(for: answer, run: run)
            try? updateWorkerTurn(
                threadId: mirror.threadId,
                workerTurnId: mirror.workerTurnId,
                text: text,
                status: status,
                completedAt: answer?.result.timing.finishedAt ?? now()
            )
            activeMirrors[runId] = nil
            return
        }
    }

    private func updateWorkerTurn(
        threadId: String,
        workerTurnId: String,
        text: String,
        status: ThreadTurnStatus,
        completedAt: Date?
    ) throws {
        guard let thread = threadStore.get(threadId),
              var turn = thread.turns.first(where: { $0.id == workerTurnId }) else { return }
        turn.text = text
        turn.status = status
        turn.completedAt = completedAt
        _ = try threadStore.updateTurn(turn, inThreadId: threadId, now: now())
    }

    private func partialWorkerText(from run: TeamRun) -> String? {
        guard let answer = run.answers.first(where: { $0.result.status == .running || $0.result.status == .done }) else {
            return nil
        }
        let text = (answer.output ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? nil : text
    }

    private func settlementText(for answer: TeamAnswer?, run: TeamRun) -> String {
        guard let answer else {
            return "Run finished without a worker reply."
        }
        switch answer.result.status {
        case .done:
            let text = (answer.output ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            return text.isEmpty ? "Done." : text
        case .cancelled:
            return "Stopped on your Mac."
        case .failed, .timedOut, .skipped:
            return answer.result.errorReason ?? "Run failed on your Mac."
        case .queued, .running:
            return "Working on this on your Mac…"
        }
    }

    private func chatStatus(for answer: WorkerAnswerStatus) -> ThreadTurnStatus {
        switch answer {
        case .done: return .done
        case .failed: return .failed
        case .timedOut: return .timedOut
        case .cancelled: return .cancelled
        case .queued, .running: return .running
        case .skipped: return .failed
        }
    }

    private func resolvedModelId(from request: AsyncTeamStartRequest) -> String? {
        guard let modelId = request.modelId?.trimmingCharacters(in: .whitespacesAndNewlines),
              !modelId.isEmpty else {
            return nil
        }
        return modelId.contains("#") ? modelId : "\(modelId)#0"
    }

    private func normalizedThreadId(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func threadTitle(from prompt: String) -> String {
        let collapsed = prompt
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !collapsed.isEmpty else { return "New conversation" }
        guard collapsed.count > 48 else { return collapsed }
        return String(collapsed.prefix(45)) + "…"
    }
}
