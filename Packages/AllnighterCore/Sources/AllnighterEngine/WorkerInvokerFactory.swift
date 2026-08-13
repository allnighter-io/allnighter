import Foundation
import AllnighterCore

/// Builds the ONE composed `WorkerInvoking` stack every Allnighter call site drives a
/// worker CLI through, replacing the deleted `WorkerRunner`'s construction (F2_B.3c
/// atomic cutover). Takes the same construction inputs `WorkerRunner.init` took
/// (invocations, defaultWorkingDirectory, shellPath, now) so call sites map cleanly,
/// plus an injectable `commandRunner` (defaults to the real subprocess spawner) so
/// tests can substitute a `StreamingCommandRunner` double the same way they used to
/// substitute `WorkerRunner`'s `commandRunner`/`streamingCommandRunner`.
///
/// Composition order (innermost → outermost), and why:
///
/// 1. `SpawnResolvingCommandRunner(inner: commandRunner, invocations:)` — rewrites
///    `(command, args)` per the detected `ToolInvocation` (health == runs) before any
///    process spawns. Innermost: everything above operates on already-resolved argv.
/// 2. `DefaultWorkerRunner(streamingRunner:)` — AgentOS's clean worker runner: drives
///    the resolved spawn, feeds its stream parser, normalizes the terminal
///    `WorkerRunResult`.
/// 3. `InvocationKindStampingWorkerRunner` — stamps `spawnDiagnostics.invocationKind`
///    from the SAME `[command: ToolInvocation]` map `SpawnResolvingCommandRunner`
///    resolved through (`DefaultWorkerRunner` builds diagnostics from the unresolved
///    literal command and never sets this field).
/// 4. `AntigravityAwareWorkerRunner` — rewrites agy's terminal answer from its on-disk
///    transcript. Pass-through for every other driver.
/// 5. `ClaudeLocalIsolatingWorkerRunner` — per-run Anthropic-compat env + meter strip
///    + observed served-window overlay for `claude_code` seats whose catalog label
///    is `ollama/<tag>`. Pass-through for paid Claude and every other driver.
///    Never writes shell/Claude settings. Never invents a context window.
/// 6. `OpenCodeRoutingWorkerRunner` (when `routeOpenCodeToServe` is true, the
///    production default) — routes `opencode` to the warm serve HTTP client instead of a
///    spawned CLI; every other driver falls through to steps 1-5 above. When
///    `routeOpenCodeToServe` is false, this step is omitted so opencode seats use the
///    injected `commandRunner` like every other driver (test doubles only — production
///    call sites leave the default `true`).
/// 6b. `OpenCodeStaleModelServeRefreshingWorkerRunner` — one reclaim+retry when a
///    warm serve returns `opencode session error: Model not found:` after a later
///    `opencode.json` tag registration. XCTest defaults to an inactive process table.
/// 7. `GatedWorkerRunner` — per-driver `DriverConcurrencyGate` + `gateWaitMs`. This
///    inverts the nesting a first reading of the four decorators' doc comments might
///    suggest (`OpenCodeRoutingWorkerRunner`'s own doc comment literally says to wrap
///    it in a `GatedWorkerRunner`, not the reverse): the ORIGINAL
///    `WorkerRunner.invoke`/`runOpenCode` both acquired the SAME per-driver spawn gate
///    (`acquireDriverSpawnGate(driverId:limit:)`) before doing their respective work —
///    the CLI spawn and the opencode-serve call are equally gated by
///    `manifest.maxConcurrentSpawns`. Putting `OpenCodeRoutingWorkerRunner` outermost
///    would let its opencode branch bypass `GatedWorkerRunner` entirely (it returns
///    straight from its own HTTP client, never calling `inner`), silently ungating
///    opencode. `GatedWorkerRunner` wrapping the router (or the Claude-local wrapper
///    when OpenCode routing is omitted) gates BOTH routes uniformly.
/// 8. `StallDiagnosisEnrichingWorkerRunner` — on `.timedOut`, replaces bare
///    `worker timed out` with a named stall cause from `stall_diagnosis.json`
///    when ProcessGroupCommandRunner diagnosed an auth-prompt / frozen child.
/// 9. A thin `defaultWorkingDirectory` fill-in (OUTERMOST, not a public decorator type)
///    — mirrors `WorkerRunner`'s stored `defaultWorkingDirectory` field: when a caller
///    leaves `WorkerInvocation.workingDirectory` nil, it resolves through
///    `WorkerInvocationCWD.resolve(override:default:)` (the neutral-scratch rule)
///    before reaching the stack above, so callers built around one long-lived factory
///    instance (e.g. `RunService`'s per-run `defaultWorkingDirectory: root`) don't have
///    to repeat that resolution at every call site.
public enum WorkerInvokerFactory {
    public static func makeWorkerInvoker(
        commandRunner: (any StreamingCommandRunner)? = nil,
        invocations: [String: ToolInvocation] = [:],
        defaultWorkingDirectory: String? = nil,
        shellPath: String? = nil,
        now: @escaping @Sendable () -> Date = Date.init,
        routeOpenCodeToServe: Bool = true,
        openCodeServeReclaim: OpenCodeLeftoverServeReclaim.Table? = nil
    ) -> any WorkerInvoking {
        let base = commandRunner
            ?? SubprocessCommandRunner(environmentPolicy: AllnighterSpawnEnvironmentPolicy())
        let spawnResolved = SpawnResolvingCommandRunner(
            inner: base, invocations: invocations, shellPath: shellPath)
        let defaultRunner = DefaultWorkerRunner(streamingRunner: spawnResolved, now: now)
        let stamped = InvocationKindStampingWorkerRunner(inner: defaultRunner, invocations: invocations)
        let agyAware = AntigravityAwareWorkerRunner(inner: stamped)
        let claudeLocal = ClaudeLocalIsolatingWorkerRunner(
            inner: agyAware,
            servedContextWindow: { model in
                ClaudeLocalIsolation.observedServedContextWindow(for: model)
            }
        )
        let gated: GatedWorkerRunner
        if routeOpenCodeToServe {
            let openCodeRouted = OpenCodeRoutingWorkerRunner(inner: claudeLocal, now: now)
            let refreshed = OpenCodeStaleModelServeRefreshingWorkerRunner(
                inner: openCodeRouted,
                table: OpenCodeLeftoverServeReclaim.resolvedTable(override: openCodeServeReclaim)
            )
            gated = GatedWorkerRunner(inner: refreshed, now: now)
        } else {
            gated = GatedWorkerRunner(inner: claudeLocal, now: now)
        }
        let enriched = StallDiagnosisEnrichingWorkerRunner(inner: gated)
        return DefaultWorkingDirectoryWorkerRunner(inner: enriched, defaultWorkingDirectory: defaultWorkingDirectory)
    }
}

/// Fills `WorkerInvocation.workingDirectory` in with the neutral-scratch rule
/// (`WorkerInvocationCWD.resolve`) when a caller leaves it nil. See
/// `WorkerInvokerFactory.makeWorkerInvoker` step 7.
private struct DefaultWorkingDirectoryWorkerRunner: WorkerInvoking {
    let inner: any WorkerInvoking
    let defaultWorkingDirectory: String?

    func invoke(_ invocation: WorkerInvocation) -> AsyncThrowingStream<WorkerStreamEvent, Error> {
        var invocation = invocation
        invocation.workingDirectory = WorkerInvocationCWD.resolve(
            override: invocation.workingDirectory, default: defaultWorkingDirectory)
        return inner.invoke(invocation)
    }
}
