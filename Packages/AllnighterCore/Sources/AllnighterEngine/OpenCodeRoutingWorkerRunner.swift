import Foundation
import AllnighterCore

/// Composite `WorkerInvoking`: routes `manifest.id == "opencode"` to the warm
/// `opencode serve` HTTP API (`OpenCodeServeClient.streamRun`, via
/// `OpenCodeServeCoordinator.ensureRunning`) instead of a spawned CLI — `opencode run`
/// is a TTY-interactive client that emits nothing when piped (see
/// `docs/phases/OpenCode_Smoke_Probe_Blocker.md`). Every other driver goes to `inner`
/// (the CLI path, normally a `DefaultWorkerRunner`) unchanged. Reuses the existing
/// `OpenCodeServeClient`/`OpenCodeServeCoordinator` types as-is — no new HTTP/session
/// logic here, just the routing `WorkerRunner.invoke`/`runOpenCode` used to inline.
///
/// Gating (`DriverConcurrencyGate`) is deliberately NOT done here — compose this
/// UNDER a `GatedWorkerRunner` (or over it, wrapping only the CLI-path `inner`) so
/// opencode's `maxConcurrentSpawns` is honored the same way regardless of which route
/// a run takes. Kept out to stay thin and single-purpose.
public struct OpenCodeRoutingWorkerRunner: WorkerInvoking {
    private let inner: any WorkerInvoking
    private let client: OpenCodeServeClient
    private let coordinator: OpenCodeServeCoordinator
    private let now: @Sendable () -> Date

    public init(
        inner: any WorkerInvoking,
        client: OpenCodeServeClient = OpenCodeServeClient(),
        coordinator: OpenCodeServeCoordinator = OpenCodeServeCoordinator(),
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.inner = inner
        self.client = client
        self.coordinator = coordinator
        self.now = now
    }

    public func invoke(_ invocation: WorkerInvocation) -> AsyncThrowingStream<WorkerStreamEvent, Error> {
        guard invocation.manifest.id == "opencode" else {
            return inner.invoke(invocation)
        }
        let client = self.client
        let coordinator = self.coordinator
        let now = self.now
        let modelLabel = invocation.model.resolvedLabel(at: invocation.effort)
        let directory = invocation.workingDirectory
        let timeout = invocation.timeout ?? .seconds(invocation.manifest.invoke?.timeoutSeconds ?? 240)
        let prompt = invocation.prompt

        return AsyncThrowingStream { continuation in
            let task = Task {
                let startedAt = now()
                do {
                    try await coordinator.ensureRunning()
                } catch {
                    var timing = RunTiming(startedAt: startedAt)
                    timing.finishedAt = now()
                    continuation.yield(.failed(WorkerRunResult(
                        status: .failed, errorKind: .missingCLI,
                        errorReason: "opencode serve: \(error)", timing: timing)))
                    continuation.finish()
                    return
                }
                do {
                    for try await event in client.streamRun(
                        prompt, modelLabel: modelLabel, directory: directory,
                        autoApprove: true, timeout: timeout
                    ) {
                        continuation.yield(event)
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}
