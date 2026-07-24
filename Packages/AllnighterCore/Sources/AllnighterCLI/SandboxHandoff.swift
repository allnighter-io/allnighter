import Foundation
import AllnighterCore
import AllnighterEngine

/// The caller-side half of the sandbox hand-off.
///
/// When this process runs inside a host that sandboxes it (today: Codex), the
/// vendor CLIs cannot reach the Keychain, so every seat fails to start. Rather
/// than handing back an empty run, we drop the request in the shared mailbox,
/// wait for the Allnighter app to run it, and return the finished run — same run
/// id, same journal, same terminal. The user does not copy, paste, or restart
/// anything.
enum SandboxHandoff {
    /// How long to wait for the app to pick the request up before telling the
    /// user, honestly, that nothing is listening.
    static let waitSeconds = 180.0
    private static let pollSeconds = 1.0

    /// Returns the completed run when the app ran it, or nil when this was not a
    /// sandbox failure at all (the overwhelmingly common case, which must stay
    /// free of side effects).
    static func runInApp(
        failedRun run: TeamRun,
        request: RunRequest,
        spool: SandboxHandoffSpool = SandboxHandoffSpool(),
        runStore: RunStore = RunStore(),
        clock: @Sendable () -> Date = Date.init
    ) async -> TeamRun? {
        guard HostSandboxAdvice.detect(
            workerFailureText: run.workerAnswers.compactMap { $0.result.errorReason },
            prompt: run.prompt,
            projectReference: run.repoRoot,
            teamId: run.presetId
        ) != nil else { return nil }
        return await handOff(request: request, spool: spool, runStore: runStore, clock: clock)
    }

    /// Same hand-off, for callers that already hold the failed run (the
    /// `--stream` branch, whose result does not flow through `runInApp`).
    static func runInAppAfterStream(
        failedRun run: TeamRun,
        request: RunRequest,
        spool: SandboxHandoffSpool = SandboxHandoffSpool(),
        runStore: RunStore = RunStore(),
        clock: @Sendable () -> Date = Date.init
    ) async -> TeamRun? {
        await runInApp(failedRun: run, request: request, spool: spool,
                       runStore: runStore, clock: clock)
    }

    private static func handOff(
        request: RunRequest,
        spool: SandboxHandoffSpool,
        runStore: RunStore,
        clock: @Sendable () -> Date
    ) async -> TeamRun? {
        let handoffRunId = "handoff-\(UUID().uuidString)"
        do {
            try spool.enqueue(.init(
                runId: handoffRunId,
                message: request.message,
                repoRoot: request.repoRoot,
                presetId: request.presetId,
                workerId: request.workerId))
        } catch {
            return nil   // Cannot reach the mailbox — fall through to the advice.
        }

        FileHandle.standardError.write(Data(
            "[Allnighter is running this in the app — your terminal can't sign in to your AI tools]\n".utf8))

        let deadline = clock().addingTimeInterval(waitSeconds)
        while clock() < deadline {
            if let finished = runStore.load(runId: handoffRunId), finished.status.isTerminal {
                return finished
            }
            try? await Task.sleep(for: .seconds(pollSeconds))
        }

        FileHandle.standardError.write(Data(
            "[Allnighter isn't open, so nothing picked this up. Open Allnighter and run it again.]\n".utf8))
        return nil
    }
}

/// Carries the streamed run out of the stream closure so the sandbox hand-off can
/// see it. `@unchecked` is safe here: exactly one write, before any read.
final class StreamedRunBox: @unchecked Sendable {
    var value: TeamRun?
}
