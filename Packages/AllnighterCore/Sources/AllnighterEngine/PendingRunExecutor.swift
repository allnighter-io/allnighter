import Foundation
import AllnighterCore

/// Executes and settles one Pending item (workerChat or non-mutating teamRun) through
/// `WorkerRunner` / `CatalogRunCoordinator` (WTK-S02a/S02b).
public struct PendingRunExecutor: Sendable {
    public struct RunOptions: Sendable {
        public var beginRun: PendingService.BeginRunOptions

        public init(beginRun: PendingService.BeginRunOptions = .cliDefault) {
            self.beginRun = beginRun
        }
    }

    public let service: PendingService
    public let registry: DriverRegistry
    public let commandRunner: CommandRunner
    public let invocations: [String: ToolInvocation]
    public let teams: [TeamPreset]
    public let runStore: RunStore
    private let now: @Sendable () -> Date

    public init(
        service: PendingService,
        registry: DriverRegistry,
        commandRunner: CommandRunner,
        invocations: [String: ToolInvocation] = [:],
        teams: [TeamPreset] = TeamCatalog.all,
        runStore: RunStore = RunStore(),
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.service = service
        self.registry = registry
        self.commandRunner = commandRunner
        self.invocations = invocations
        self.teams = teams
        self.runStore = runStore
        self.now = now
    }

    /// Run one Pending item to completion and return the settled item.
    public func run(id: String, options: RunOptions = RunOptions()) async throws -> PendingItem {
        var item = try service.beginRun(id: id, options: options.beginRun)
        let attemptIndex = item.attempts.count - 1
        let attemptId = item.attempts[attemptIndex].attemptId

        switch item.kind {
        case .workerChat:
            item = try await runWorkerChat(item: item, attemptIndex: attemptIndex, attemptId: attemptId)
        case .teamRun:
            item = try await runTeamRun(item: item, attemptIndex: attemptIndex, attemptId: attemptId, options: options)
        default:
            throw PendingServiceError.unsupportedKind(item.kind.rawValue)
        }
        return item
    }

    // MARK: - workerChat

    private func runWorkerChat(item: PendingItem, attemptIndex: Int, attemptId: String) async throws -> PendingItem {
        let workerId = item.target.preferredWorkerIds.first ?? item.target.workerIds.first ?? ""
        guard let model = service.models.first(where: { $0.id == workerId }) else {
            throw PendingServiceError.invalidWorker(workerId.isEmpty ? "no worker specified" : workerId)
        }
        guard let manifest = registry.manifest(id: model.driverId) else {
            throw PendingServiceError.invalidWorker("no driver manifest for \(model.driverId)")
        }

        let runner = WorkerRunner(commandRunner: commandRunner, invocations: invocations, now: now)
        let outcome = await runner.invoke(
            worker: model,
            manifest: manifest,
            prompt: item.prompt,
            workingDirectoryOverride: item.safety.workingDir
        )

        let transcriptRef = try writeTranscript(attemptId: attemptId, outcome: outcome)
        return try service.settleRun(
            id: item.id,
            attemptIndex: attemptIndex,
            outcome: outcome,
            transcriptRef: transcriptRef
        )
    }

    // MARK: - teamRun

    private func runTeamRun(
        item: PendingItem,
        attemptIndex: Int,
        attemptId: String,
        options: RunOptions
    ) async throws -> PendingItem {
        guard let teamId = item.target.teamPresetId else {
            throw PendingServiceError.invalidState("teamRun pending item requires teamPresetId")
        }
        guard let team = teams.first(where: { $0.id == teamId }) else {
            throw PendingServiceError.invalidState("unknown team preset: \(teamId)")
        }
        if team.mutating {
            throw PendingServiceError.mutationDeferred
        }

        let readyModels = service.models.filter(\.enabled)
        let resolved = TeamResolver.resolve(
            team: team,
            requestLane: team.lane,
            requestEffort: team.defaultEffort,
            readyModels: readyModels
        )
        guard resolved.isRunnable else {
            throw PendingServiceError.invalidState(resolved.blockReason ?? "team cannot run")
        }
        if let blocker = ExecutionTeamSourceGate.evaluate(resolved: resolved, models: readyModels).sourceGateBlocker {
            throw PendingServiceError.sourceGateBlocked(blocker)
        }

        let coordinator = CatalogRunCoordinator(
            workerRunner: WorkerRunner(commandRunner: commandRunner, invocations: invocations, now: now),
            registry: registry,
            now: now
        )
        let origin: RunOrigin = options.beginRun.origin.map { PendingOriginMapper.runOrigin($0) } ?? .cli
        @Sendable func stamped(_ run: TeamRun) -> TeamRun {
            var copy = run
            copy.lane = team.lane
            copy.type = team.typeTags.first
            copy.effort = team.defaultEffort
            copy.teamDisplayName = resolved.teamDisplayName
            copy.outputKind = resolved.outputKind
            copy.warnings = resolved.warnings
            copy.mutating = resolved.mutating
            copy.executionSourceId = resolved.executionSourceId
            copy.threadId = item.threadId
            return copy
        }
        let persist: @Sendable (TeamRun) -> Void = { try? runStore.save(stamped($0), models: readyModels) }
        let run = await coordinator.run(
            resolved: resolved,
            prompt: item.prompt,
            models: readyModels,
            origin: origin,
            originAgent: nil,
            runId: item.runId ?? "run_\(UUID().uuidString.lowercased())",
            persist: persist
        )
        return try service.settleTeamRun(
            id: item.id,
            attemptIndex: attemptIndex,
            run: stamped(run),
            transcriptRef: teamTranscriptRef(attemptId: attemptId, run: run)
        )
    }

    // MARK: - Transcript receipt

    private func writeTranscript(attemptId: String, outcome: WorkerRunOutcome) throws -> String? {
        let text: String?
        switch outcome.status {
        case .done:
            text = outcome.output
        case .failed, .timedOut:
            text = [outcome.errorReason, outcome.output]
                .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
                .joined(separator: "\n")
                .nilIfEmpty
        case .cancelled:
            text = outcome.errorReason?.nilIfEmpty
        default:
            text = nil
        }
        guard let text else { return nil }

        let relative = "attempts/\(attemptId).txt"
        let url = service.store.rootDirectory.appendingPathComponent(relative)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try text.write(to: url, atomically: true, encoding: .utf8)
        return relative
    }

    private func teamTranscriptRef(attemptId: String, run: TeamRun) -> String? {
        let summary = [
            run.status.rawValue,
            run.plan.map { "plan:\($0.prefix(200))" },
            run.failedWorkerAnswers.map(\.errorReason).compactMap { $0 }.joined(separator: "; ")
        ].compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }.joined(separator: "\n")
        guard !summary.isEmpty else { return nil }
        let relative = "attempts/\(attemptId).txt"
        let url = service.store.rootDirectory.appendingPathComponent(relative)
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? summary.write(to: url, atomically: true, encoding: .utf8)
        return relative
    }
}

private enum PendingOriginMapper {
    static func runOrigin(_ origin: PendingOrigin) -> RunOrigin {
        switch origin {
        case .cli: return .cli
        case .gui: return .gui
        case .mcp: return .mcp
        case .ios, .localApi, .system, .preset: return .cli
        }
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
