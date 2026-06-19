import Foundation
import AllnighterCore

/// Executes and settles one `workerChat` Pending item through `WorkerRunner` (WTK-S02a).
public struct PendingRunExecutor: Sendable {
    public let service: PendingService
    public let registry: DriverRegistry
    public let commandRunner: CommandRunner
    public let invocations: [String: ToolInvocation]
    private let now: @Sendable () -> Date

    public init(
        service: PendingService,
        registry: DriverRegistry,
        commandRunner: CommandRunner,
        invocations: [String: ToolInvocation] = [:],
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.service = service
        self.registry = registry
        self.commandRunner = commandRunner
        self.invocations = invocations
        self.now = now
    }

    /// Run one Pending item to completion and return the settled item.
    public func run(id: String) async throws -> PendingItem {
        var item = try service.beginRun(id: id)
        let attemptIndex = item.attempts.count - 1
        let attemptId = item.attempts[attemptIndex].attemptId

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
        item = try service.settleRun(
            id: item.id,
            attemptIndex: attemptIndex,
            outcome: outcome,
            transcriptRef: transcriptRef
        )
        return item
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
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
