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

    /// How long the readiness ping waits for a host to answer before `alln run`
    /// refuses. Deliberately much shorter than `claimGraceSeconds`: the caller has
    /// already paid one failed local run, and the ping exists precisely to avoid a
    /// second long wait in front of a refusal.
    static let readinessWaitSeconds = 5.0

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
        clock: @escaping @Sendable () -> Date = Date.init
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
        clock: @escaping @Sendable () -> Date = Date.init
    ) async -> TeamRun? {
        await handOff(request: request, spool: spool, runStore: runStore, clock: clock)
    }

    static func handOff(
        request: RunRequest,
        spool: SandboxHandoffSpool,
        runStore: RunStore,
        clock: @escaping @Sendable () -> Date,
        readiness: (@Sendable () async -> HandoffDoctorJSON)? = nil
    ) async -> TeamRun? {
        // Prove a host will claim BEFORE queuing real work (CAR-S03a). The old
        // enqueue-then-wait order left the request runnable in the mailbox when
        // no host existed: the caller was told it failed, and opening the app
        // hours later still swept and executed it. One quota-free ping answers
        // the only question that matters. Anything but `.healthy` is a typed
        // terminal refusal and NOTHING is queued — there is no run id to print
        // and nothing to resume, which is the whole point.
        let check = readiness ?? {
            await HandoffDoctor(
                spool: spool, runStore: runStore,
                waitSeconds: readinessWaitSeconds
            ).check(
                contractVersion: ContractRegistry.contractVersion,
                repoRoot: request.repoRoot, clock: clock)
        }
        let report = await check()
        guard report.isHealthy else {
            let refusal = handoffRefusal(for: report)
            AllnighterCLI.emitFailure(code: refusal.code, message: refusal.message)
            return nil
        }

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
            explicitSeatModelIds: request.explicitSeatModelIds,
            readOnly: request.readOnly)
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

    // MARK: - Readiness refusal (CAR-S03a)

    #if os(macOS)
    static let currentPlatformIsMacOS = true
    #else
    static let currentPlatformIsMacOS = false
    #endif

    /// One typed refusal per failure class. The three non-healthy verdicts are
    /// different problems and must never share a sentence — one wrong sentence
    /// covering two problems is what made the original failure undiagnosable
    /// (see `HandoffDoctor.swift`). Emitted on the shared failure surface
    /// (`AllnighterCLI.emitFailure`), so a calling agent recovers from the
    /// structured code and the human reads the text.
    ///
    /// Message rules: every remediation must be an action that can actually
    /// change the outcome; never `alln doctor` (doctor reporting OK while the
    /// command refuses is a failure mode this project has already paid for);
    /// never a run id or `alln run resume` — nothing was queued, so there is
    /// nothing to resume.
    static func handoffRefusal(
        for report: HandoffDoctorJSON,
        isMacOS: Bool = currentPlatformIsMacOS,
        appPath: String? = installedAppPath()
    ) -> (code: String, message: String) {
        switch report.verdict {
        case .healthy:
            preconditionFailure("handoffRefusal called for a healthy readiness report")
        case .claimedButSilent:
            // Something is watching the mailbox but not completing work. The app
            // is already open — never tell the user to open it.
            return (
                "HANDOFF_CLAIMED_BUT_SILENT",
                """
                \(report.claimedBy ?? "A host") claimed the readiness check and never answered it — \
                something is watching the hand-off mailbox but is not completing work, so nothing \
                was queued. Restart the Allnighter app so its hand-off host recovers, then run \
                this again.
                """)
        case .mailboxUnwritable:
            // `report.detail` already names the mailbox path and the write error.
            return (
                "HANDOFF_MAILBOX_UNWRITABLE",
                "\(report.detail) Nothing was queued — make that mailbox writable, then run this again.")
        case .hostNotRunning:
            return (
                "HANDOFF_HOST_NOT_RUNNING",
                hostNotRunningMessage(isMacOS: isMacOS, appPath: appPath))
        }
    }

    static func hostNotRunningMessage(isMacOS: Bool, appPath: String?) -> String {
        guard isMacOS else {
            // There is no Mac app to open on this platform — never print an
            // "open/install Allnighter" instruction, and never fabricate a
            // Linux install path.
            return """
            Your terminal can't sign in to your AI tools, and the Allnighter hand-off receiver is \
            macOS-only, so this host cannot delegate and nothing was queued. The only route is a \
            per-session full-access terminal: codex --sandbox danger-full-access.
            """
        }
        if let appPath {
            return """
            Your terminal can't sign in to your AI tools, and the Allnighter app is not running, \
            so nothing was queued. Open the Allnighter app (\(appPath)) and run this again. \
            Or lift the restriction for this terminal session only: codex --sandbox danger-full-access.
            """
        }
        // Not "open" — you cannot open an app that does not exist.
        return """
        Your terminal can't sign in to your AI tools, and the Allnighter app is not installed on \
        this Mac, so nothing was queued. Install the Allnighter app, open it, and run this again. \
        Or lift the restriction for this terminal session only: codex --sandbox danger-full-access.
        """
    }

    /// Where the Allnighter app lives, if it exists. Deliberately a plain
    /// filesystem stat, NOT LaunchServices: CAR-S00b proved LaunchServices is
    /// exactly what the sandbox denies (`LSCopyApplicationURLsFor…` failure and
    /// `-10827 kLSNoExecutableErr`), while plain reads work fine — a direct
    /// spawn read and executed the bundle. Note this only runs when the
    /// readiness ping has already FAILED: when the app is actually running, the
    /// ping succeeds and its install location is irrelevant to the working path.
    static func installedAppPath(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        fileManager: FileManager = .default
    ) -> String? {
        // The founder runs a locally-built app, not an installed one — the
        // override keeps "install Allnighter" from being said to someone whose
        // own build simply lives elsewhere.
        if let override = environment["ALLNIGHTER_APP_PATH"], !override.isEmpty,
           fileManager.fileExists(atPath: override) {
            return override
        }
        let candidates = [
            "/Applications/Allnighter.app",
            NSHomeDirectory() + "/Applications/Allnighter.app",
        ]
        return candidates.first { fileManager.fileExists(atPath: $0) }
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
