import Foundation
import AllnighterCore

/// Coordinator-owned dispatcher for the closed resident operation union. This
/// is the only component that turns an accepted local request into a Team
/// runner; foreground clients only write/read the rendezvous files.
public final class ResidentExecutionBroker: @unchecked Sendable {
    public struct Dependencies: Sendable {
        public var asyncTeam: AsyncTeamService
        public var readyModels: @Sendable () -> [Model]
        public var executablePath: @Sendable () -> String?

        public init(
            asyncTeam: AsyncTeamService,
            readyModels: @escaping @Sendable () -> [Model],
            executablePath: @escaping @Sendable () -> String? = ProcessOwnership.currentExecutablePath
        ) {
            self.asyncTeam = asyncTeam
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
        default:
            try? rendezvous.reject(
                claim,
                code: "RESIDENT_REQUEST_REJECTED",
                message: "operation \(claim.request.operation.kind.rawValue) is not enabled by this broker slice"
            )
        }
    }
}
