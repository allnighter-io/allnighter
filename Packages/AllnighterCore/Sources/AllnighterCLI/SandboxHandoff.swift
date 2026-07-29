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
    /// How long to wait for SOMETHING to claim the request. A host polls its
    /// mailbox every couple of seconds, so anything alive claims well inside this;
    /// waiting longer only makes a closed app look like a slow one.
    static let claimGraceSeconds = 30.0

    /// Once claimed, there is deliberately NO work deadline: the run owns its own
    /// clocks, and the old 180s bound was shorter than the multi-seat reviews this
    /// exists to serve — it reported failure while the app was still working. This
    /// is only a backstop against a host that claimed and died, which cannot yet be
    /// detected directly (that needs owner identity on the claim).
    static let stalledAfterSeconds = 1_800.0

    /// How often to tell the user it is still alive, so a long run is not mistaken
    /// for a hang.
    static let heartbeatSeconds = 15.0

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
        // ANY seat lost to the sandbox is enough. A team where two of three seats
        // were killed still reports `partial / completed` and exits 0, so without
        // this the caller silently receives a fraction of the team it asked for and
        // has no way to know. What the app can run properly, it should.
        guard HostSandboxAdvice.detect(
            workerFailureText: run.answers.compactMap { $0.result.errorReason },
            prompt: run.prompt,
            projectReference: run.repoRoot,
            teamId: run.presetId,
            capacityAuthRequired: run.answers.contains {
                $0.result.capacityObservation?.kind == .authRequired
            }
        ) != nil else { return nil }
        return await handOff(request: request, spool: spool, runStore: runStore, clock: clock)
    }

    /// Hand off a run that never started, so had no worker failure to detect.
    /// The caller owns the decision (see `RunServiceError.retryOutsideRestrictedHost`);
    /// this just does it.
    static func runInAppAfterPreflightFailure(
        request: RunRequest,
        spool: SandboxHandoffSpool = SandboxHandoffSpool(),
        runStore: RunStore = RunStore(),
        clock: @Sendable () -> Date = Date.init
    ) async -> TeamRun? {
        await handOff(request: request, spool: spool, runStore: runStore, clock: clock)
    }

    private static func handOff(
        request: RunRequest,
        spool: SandboxHandoffSpool,
        runStore: RunStore,
        clock: @Sendable () -> Date
    ) async -> TeamRun? {
        let handoffRunId = "handoff-\(UUID().uuidString)"
        // Retained: the mailbox is keyed by request id, and without it the caller
        // cannot tell "nothing claimed this" from "something claimed it and went
        // quiet" — which is how one wrong sentence covered two different problems.
        let enqueued = SandboxHandoffSpool.Request(
            runId: handoffRunId,
            message: request.message,
            repoRoot: request.repoRoot,
            presetId: request.presetId,
            modelId: request.pinnedModelId,
            effort: request.effort,
            lane: request.lane,
            type: request.type,
            context: request.context,
            threadId: request.threadId,
            projectId: request.projectId,
            deliveries: request.deliveries,
            executorTeamId: request.executorTeamId,
            advisoryReview: request.advisoryReview,
            workerTimeoutSeconds: request.workerTimeoutSeconds,
            handshakeTimeoutSeconds: request.handshakeTimeoutSeconds,
            firstActivityTimeoutSeconds: request.firstActivityTimeoutSeconds,
            wallTimeoutSeconds: request.wallTimeoutSeconds,
            spawnConcurrencyLimit: request.spawnConcurrencyLimit,
            commitMessage: request.commitMessage,
            noCommit: request.noCommit,
            proofCommand: request.proofCommand,
            proofTimeoutSeconds: request.proofTimeoutSeconds,
            retryOf: request.retryOf,
            acceptSurvivors: request.acceptSurvivors,
            explicitSeatModelIds: request.explicitSeatModelIds)
        do {
            try spool.enqueue(enqueued)
        } catch {
            // Falling through to the advice is right, but doing it silently made a
            // broken mailbox look identical to "this was never a sandbox failure".
            FileHandle.standardError.write(Data(
                "[Allnighter could not reach its hand-off mailbox: \(error.localizedDescription)]\n".utf8))
            return nil
        }

        // Say only what has actually happened: the request is in the mailbox. Whether
        // anything picks it up is not known yet, and claiming otherwise here is what
        // put "Allnighter is running this in the app" in front of a founder while
        // nothing was running it at all.
        FileHandle.standardError.write(Data("""
        [Your terminal can't sign in to your AI tools, so Allnighter handed this to the app.
         Run id: \(handoffRunId) — if this terminal goes away, read it later with:
             alln show \(handoffRunId) --json]

        """.utf8))

        return await waitForHandoff(
            runId: handoffRunId, requestId: enqueued.id,
            spool: spool, runStore: runStore, clock: clock)
    }

    /// Waits for a handed-off run and reports only what it can observe.
    ///
    /// The bound this replaces was a flat 180 seconds, after which the caller
    /// printed "Allnighter isn't open" — without ever checking whether anything had
    /// claimed the request. It was wrong twice over: it gave up long before a real
    /// multi-seat review finishes, and it named a cause it had not looked at.
    static func waitForHandoff(
        runId: String,
        requestId: String?,
        spool: SandboxHandoffSpool,
        runStore: RunStore,
        clock: @Sendable () -> Date = Date.init,
        note: @Sendable (String) -> Void = { FileHandle.standardError.write(Data($0.utf8)) }
    ) async -> TeamRun? {
        let startedAt = clock()
        var claimedAt: Date?
        var lastHeartbeat = startedAt

        while true {
            if let finished = runStore.load(runId: runId), finished.status.isTerminal {
                // `load` PROJECTS a run whose owner process is gone as interrupted,
                // but says nothing — so an app killed mid-review returned a run the
                // caller printed as a bare status with no explanation of why the
                // work stopped. Name it, and make the projection durable so the
                // next reader sees the same thing.
                if finished.status == .interrupted {
                    note("""
                    [The Allnighter app stopped before finishing this run, so it is \
                    recorded as interrupted. Anything already written was kept.
                     Run id: \(runId)]

                    """)
                    _ = runStore.reconcileRun(runId: runId)
                }
                return finished
            }

            // Claim state is a fact on disk, not an inference.
            let pending = requestId.flatMap { spool.request(id: $0) }
            if claimedAt == nil, let claim = pending?.claimedAt {
                claimedAt = claim
                note("[\(pending?.claimedBy ?? "a host") picked this up — running it now]\n")
            }

            let now = clock()
            let waited = now.timeIntervalSince(startedAt)

            // Claim-state reasoning only applies while we are waiting for someone to
            // TAKE the request. A caller re-attaching to a run already in flight
            // (`requestId == nil`) skips it: the mailbox entry is long gone.
            if requestId != nil, claimedAt == nil, pending == nil, runStore.load(runId: runId) == nil {
                // Claimed, settled and removed between two polls without leaving a
                // journal. S1 makes the host always write one, so this means an old
                // or foreign host drained it.
                note("""
                [Something took this request and left no result. \
                It is not an Allnighter host built after the hand-off repair.
                 Run id: \(runId)]

                """)
                return nil
            }

            if requestId != nil, claimedAt == nil, waited >= claimGraceSeconds {
                note("""
                [Nothing picked this up in \(Int(waited))s, so Allnighter is not open \
                (or its hand-off host never started).
                 Open Allnighter, then collect this with:
                     alln run resume \(runId)]

                """)
                return nil
            }

            let workingSince = claimedAt ?? startedAt
            if now.timeIntervalSince(workingSince) >= stalledAfterSeconds {
                note("""
                [A host has held this for \(Int(now.timeIntervalSince(workingSince)))s \
                without finishing it. It is stuck or gone.
                 Run id: \(runId)]

                """)
                return nil
            }

            if now.timeIntervalSince(lastHeartbeat) >= heartbeatSeconds {
                lastHeartbeat = now
                note("[still running in the app — \(Int(waited))s]\n")
            }

            try? await Task.sleep(for: .seconds(pollSeconds))
        }
    }
}

/// Carries the streamed run out of the stream closure so the sandbox hand-off can
/// see it. `@unchecked` is safe here: exactly one write, before any read.
final class StreamedRunBox: @unchecked Sendable {
    var value: TeamRun?
}
