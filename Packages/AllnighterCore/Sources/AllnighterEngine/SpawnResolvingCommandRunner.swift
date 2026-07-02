import Foundation
import AllnighterCore

/// Wraps a real `StreamingCommandRunner` (normally `SubprocessCommandRunner`) and
/// rewrites `(command, args)` per Allnighter's setup-detected `ToolInvocation` before
/// delegating — the "health == runs" rule (`01` §4.3): a tool that passed Setup's
/// detection must spawn through that SAME resolved plan (direct path / version-manager
/// shim / login-shell alias), not the bare command on the ambient PATH.
///
/// AgentOS's `DefaultWorkerRunner` calls `streamingRunner.runStreaming(command:...)`
/// with the manifest's literal `invoke.command` (e.g. `"claude"`, `"agy"`) — it never
/// sees the driver id. So the map here is keyed by that literal command string, not by
/// driver id, mirroring `WorkerRunner.resolveSpawn`'s switch (see `WorkerRunner.swift`,
/// NOT modified here) but adapted to the seam this decorator actually receives.
public struct SpawnResolvingCommandRunner: StreamingCommandRunner {
    private let inner: any StreamingCommandRunner
    private let invocations: [String: ToolInvocation]
    private let shellPath: String

    public init(
        inner: any StreamingCommandRunner = SubprocessCommandRunner(),
        invocations: [String: ToolInvocation],
        shellPath: String? = nil
    ) {
        self.inner = inner
        self.invocations = invocations
        self.shellPath = shellPath ?? ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
    }

    public func runStreaming(
        command: String,
        args: [String],
        stdin: String?,
        env: [String: String],
        workingDirectory: String?,
        timeout: Duration
    ) -> AsyncThrowingStream<CommandEvent, Error> {
        let (resolvedCommand, resolvedArgs) = Self.resolve(
            command: command, args: args, invocations: invocations, shellPath: shellPath)
        return inner.runStreaming(
            command: resolvedCommand, args: resolvedArgs, stdin: stdin,
            env: env, workingDirectory: workingDirectory, timeout: timeout)
    }

    /// Pure resolution, shared with `invocationKindLabel` below so both read the same
    /// map the same way.
    static func resolve(
        command: String, args: [String], invocations: [String: ToolInvocation], shellPath: String
    ) -> (command: String, args: [String]) {
        switch invocations[command] {
        case .direct(let path), .shim(let path):
            return (path, args)
        case .loginShell(let name):
            // Resolve an alias/function via the login shell; argv flows through
            // "$@" — never concatenated into the shell string (no injection).
            return (shellPath, ["-lic", "\(name) \"$@\"", name] + args)
        case nil:
            return (command, args)
        }
    }

    /// How `command` would resolve: `direct`/`shim`/`login_shell`/`ambient` — the same
    /// label `WorkerRunner.invocationKindLabel` produces today. Exposed so
    /// `InvocationKindStampingWorkerRunner` can stamp `spawnDiagnostics.invocationKind`
    /// without re-deriving the switch.
    static func invocationKindLabel(command: String?, invocations: [String: ToolInvocation]) -> String {
        guard let command else { return "ambient" }
        switch invocations[command] {
        case .direct: return "direct"
        case .shim: return "shim"
        case .loginShell: return "login_shell"
        case nil: return "ambient"
        }
    }
}

/// Tiny `WorkerInvoking` decorator: stamps `result.spawnDiagnostics?.invocationKind`
/// using the SAME `[command: ToolInvocation]` map `SpawnResolvingCommandRunner`
/// resolves spawns through. `DefaultWorkerRunner` builds `spawnDiagnostics` from the
/// manifest's UNRESOLVED literal command and never sets `invocationKind` — this fills
/// that one field in, on the terminal event only, without touching diagnostics
/// construction itself.
public struct InvocationKindStampingWorkerRunner: WorkerInvoking {
    private let inner: any WorkerInvoking
    private let invocations: [String: ToolInvocation]

    public init(inner: any WorkerInvoking, invocations: [String: ToolInvocation]) {
        self.inner = inner
        self.invocations = invocations
    }

    public func invoke(_ invocation: WorkerInvocation) -> AsyncThrowingStream<WorkerStreamEvent, Error> {
        let label = SpawnResolvingCommandRunner.invocationKindLabel(
            command: invocation.manifest.invoke?.command, invocations: invocations)
        let inner = self.inner

        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    for try await event in inner.invoke(invocation) {
                        switch event {
                        case .completed(var result):
                            result.spawnDiagnostics?.invocationKind = label
                            continuation.yield(.completed(result))
                        case .failed(var result):
                            result.spawnDiagnostics?.invocationKind = label
                            continuation.yield(.failed(result))
                        default:
                            continuation.yield(event)
                        }
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
