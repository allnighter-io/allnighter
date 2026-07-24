import Foundation
import AllnighterCore

private actor ForegroundRunCompletion {
    private var result: Result<TeamRun, RunServiceError>?

    func finish(_ result: Result<TeamRun, RunServiceError>) { self.result = result }
    func current() -> Result<TeamRun, RunServiceError>? { result }
}

private final class ForegroundRunTaskRegistry: @unchecked Sendable {
    private let lock = NSLock()
    private var tasks: [String: Task<Void, Never>] = [:]

    func insert(_ task: Task<Void, Never>, runId: String) {
        lock.lock(); defer { lock.unlock() }
        tasks[runId] = task
    }

    func remove(runId: String) {
        lock.lock(); defer { lock.unlock() }
        tasks.removeValue(forKey: runId)
    }
}

/// Coordinator-owned dispatcher for the closed resident operation union. This
/// is the only component that turns an accepted local request into a Team
/// runner; foreground clients only write/read the rendezvous files.
public final class ResidentExecutionBroker: @unchecked Sendable {
    public struct Dependencies: Sendable {
        public var asyncTeam: AsyncTeamService
        public var runService: RunService
        public var models: [Model]
        public var registry: DriverRegistry
        public var runStore: RunStore
        public var readyModels: @Sendable () -> [Model]
        public var executablePath: @Sendable () -> String?

        public init(
            asyncTeam: AsyncTeamService,
            runService: RunService? = nil,
            models: [Model] = [],
            registry: DriverRegistry = DefaultConfig.registry,
            runStore: RunStore = RunStore(),
            readyModels: @escaping @Sendable () -> [Model],
            executablePath: @escaping @Sendable () -> String? = ProcessOwnership.currentExecutablePath
        ) {
            self.asyncTeam = asyncTeam
            self.runService = runService ?? RunService(models: models, registry: registry, runStore: runStore)
            self.models = models
            self.registry = registry
            self.runStore = runStore
            self.readyModels = readyModels
            self.executablePath = executablePath
        }
    }

    private let rendezvous: ResidentExecutionRendezvous
    private let dependencies: Dependencies
    private let foregroundTasks = ForegroundRunTaskRegistry()

    public init(rendezvous: ResidentExecutionRendezvous, dependencies: Dependencies) {
        self.rendezvous = rendezvous
        self.dependencies = dependencies
    }

    public func run(isCancelled: @escaping @Sendable () -> Bool) async {
        while !isCancelled() && !Task.isCancelled {
            do {
                if let claim = try rendezvous.claimNext() {
                    await dispatch(claim)
                    continue
                }
            } catch {
                // A malformed/hostile entry is never executed. Leave forensic
                // evidence in the claimed inbox; the coordinator remains alive
                // for subsequent operator recovery rather than silently falling
                // back to caller-owned work.
            }
            try? await Task.sleep(nanoseconds: 100_000_000)
        }
    }

    private func dispatch(_ claim: ResidentExecutionRendezvous.Claim) async {
        switch claim.request.operation {
        case .teamRun(let request):
            guard let executable = dependencies.executablePath() else {
                try? rendezvous.reject(
                    claim,
                    code: "RESIDENT_REQUEST_REJECTED",
                    message: "resident coordinator could not resolve its alln executable"
                )
                return
            }
            let outcome = await dependencies.asyncTeam.start(
                request,
                origin: .cli,
                readyModels: dependencies.readyModels(),
                ownership: .detachedRunner(executablePath: executable)
            )
            switch outcome {
            case .success(let response):
                try? rendezvous.accept(
                    claim,
                    canonicalId: response.runId,
                    result: .teamStart(response)
                )
            case .failure(let refusal):
                try? rendezvous.reject(claim, code: refusal.code, message: refusal.message)
            }
        case .foregroundTeamRun(let request):
            await startForegroundRun(request, claim: claim)
        case .query(let query) where query.kind == .health:
            try? rendezvous.accept(claim, canonicalId: claim.request.coordinatorId)
        case .query(let query) where query.kind == .runStatus:
            guard let runId = query.canonicalId, let status = await dependencies.asyncTeam.status(runId: runId) else {
                try? rendezvous.reject(claim, code: "RUN_NOT_FOUND", message: "no run matches \(query.canonicalId ?? "")")
                return
            }
            try? rendezvous.accept(claim, canonicalId: runId, result: .teamStatus(status))
        case .query(let query) where query.kind == .runResult:
            guard let runId = query.canonicalId else {
                try? rendezvous.reject(claim, code: "RUN_NOT_FOUND", message: "no run id was supplied")
                return
            }
            switch await dependencies.asyncTeam.result(runId: runId) {
            case .notFound:
                try? rendezvous.reject(claim, code: "RUN_NOT_FOUND", message: "no run matches \(runId)")
            case .notReady(let result):
                try? rendezvous.accept(claim, canonicalId: runId, result: .teamResultNotReady(result))
            case .ready(let run):
                let directory = try? dependencies.runStore.runDirectory(forRunId: run.id)
                let context = TeamRunJSONMapper.Context(
                    runJournalPath: directory?.appendingPathComponent("run.json").path ?? "",
                    runDirectory: directory
                )
                let result = TeamRunJSONMapper.map(
                    run,
                    models: dependencies.models,
                    manifests: dependencies.registry.all,
                    context: context
                )
                try? rendezvous.accept(claim, canonicalId: runId, result: .teamResult(result))
            }
        default:
            try? rendezvous.reject(
                claim,
                code: "RESIDENT_REQUEST_REJECTED",
                message: "operation \(claim.request.operation.kind.rawValue) is not enabled by this broker slice"
            )
        }
    }

    /// Begins a full foreground run in the coordinator process and accepts only
    /// after its canonical journal exists. That makes the receipt's run id
    /// immediately queryable while leaving no caller-owned worker path behind.
    private func startForegroundRun(
        _ request: ResidentExecutionOperation.ForegroundTeamRunRequest,
        claim: ResidentExecutionRendezvous.Claim
    ) async {
        let runId = UUID().uuidString.lowercased()
        let completion = ForegroundRunCompletion()
        let runRequest = RunRequest(
            message: request.message,
            repoRoot: request.repoRoot,
            projectId: request.projectId,
            presetId: request.presetId,
            workerId: request.workerId,
            effort: request.effort,
            lane: request.lane,
            type: request.type,
            context: request.context,
            workerTimeoutSeconds: request.workerTimeoutSeconds,
            handshakeTimeoutSeconds: request.handshakeTimeoutSeconds,
            firstActivityTimeoutSeconds: request.firstActivityTimeoutSeconds,
            wallTimeoutSeconds: request.wallTimeoutSeconds,
            commitMessage: request.commitMessage,
            noCommit: request.noCommit,
            proofCommand: request.proofCommand,
            idempotencyKey: request.idempotencyKey,
            retryOf: request.retryOf,
            acceptSurvivors: request.acceptSurvivors
        )
        let service = dependencies.runService
        let tasks = foregroundTasks
        let task = Task {
            let result = await service.run(
                runRequest, origin: .cli, originAgent: request.originAgent, runId: runId
            )
            await completion.finish(result)
            tasks.remove(runId: runId)
        }
        foregroundTasks.insert(task, runId: runId)

        let deadline = Date().addingTimeInterval(5)
        while Date() < deadline {
            if let run = dependencies.runStore.loadRaw(runId: runId)
                ?? dependencies.runStore.load(runId: runId) {
                let status = AsyncTeamStatusMapper.statusResponse(for: run)
                let response = TeamStartResponse(
                    runId: run.id,
                    status: status.status,
                    lane: run.lane?.rawValue,
                    teamPresetId: run.presetId,
                    teamDisplayName: run.teamDisplayName,
                    effort: run.effort?.rawValue,
                    acceptedAt: Date(),
                    nextPollAfterMs: status.nextPollAfterMs,
                    nextActions: [.pollStatus(runId: run.id)]
                )
                try? rendezvous.accept(claim, canonicalId: run.id, result: .teamStart(response))
                return
            }
            if let result = await completion.current() {
                switch result {
                case .success(let run):
                    let status = AsyncTeamStatusMapper.statusResponse(for: run)
                    let response = TeamStartResponse(
                        runId: run.id, status: status.status, lane: run.lane?.rawValue,
                        teamPresetId: run.presetId, teamDisplayName: run.teamDisplayName,
                        effort: run.effort?.rawValue, acceptedAt: Date(),
                        nextPollAfterMs: status.nextPollAfterMs,
                        nextActions: [.fetchResult(runId: run.id)]
                    )
                    try? rendezvous.accept(claim, canonicalId: run.id, result: .teamStart(response))
                case .failure(let error):
                    try? rendezvous.reject(claim, code: error.code, message: error.description)
                }
                return
            }
            try? await Task.sleep(for: .milliseconds(25))
        }
        task.cancel()
        foregroundTasks.remove(runId: runId)
        try? rendezvous.reject(
            claim,
            code: "RESIDENT_ACCEPT_TIMEOUT",
            message: "resident run did not create a durable journal before acceptance"
        )
    }
}
