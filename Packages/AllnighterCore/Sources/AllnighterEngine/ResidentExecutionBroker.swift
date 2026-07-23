import Foundation
import AllnighterCore

/// Coordinator-owned dispatcher for the closed resident operation union. This
/// is the only component that turns an accepted local request into a Team
/// runner; foreground clients only write/read the rendezvous files.
public final class ResidentExecutionBroker: @unchecked Sendable {
    public struct Dependencies: Sendable {
        public var asyncTeam: AsyncTeamService
        public var models: [Model]
        public var registry: DriverRegistry
        public var runStore: RunStore
        public var readyModels: @Sendable () -> [Model]
        public var executablePath: @Sendable () -> String?

        public init(
            asyncTeam: AsyncTeamService,
            models: [Model] = [],
            registry: DriverRegistry = DefaultConfig.registry,
            runStore: RunStore = RunStore(),
            readyModels: @escaping @Sendable () -> [Model],
            executablePath: @escaping @Sendable () -> String? = ProcessOwnership.currentExecutablePath
        ) {
            self.asyncTeam = asyncTeam
            self.models = models
            self.registry = registry
            self.runStore = runStore
            self.readyModels = readyModels
            self.executablePath = executablePath
        }
    }

    private let rendezvous: ResidentExecutionRendezvous
    private let dependencies: Dependencies

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
}
