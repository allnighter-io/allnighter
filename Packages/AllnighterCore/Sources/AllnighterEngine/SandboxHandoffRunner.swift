import Foundation
import AllnighterCore

/// Runs the requests a sandboxed caller dropped in `SandboxHandoffSpool`.
///
/// This is the half that lives OUTSIDE the sandbox (the Mac app hosts it). It
/// adds no run semantics of its own: it claims a request and hands it to the
/// same `RunService.run` the CLI and the GUI use, with the same canonical root,
/// so the result lands in the ordinary run journal the caller is already polling.
public struct SandboxHandoffRunner: Sendable {
    public var spool: SandboxHandoffSpool
    /// Built fresh for each claimed request rather than held for the app's
    /// lifetime. A host open all day would otherwise keep the roster, registry and
    /// invocation map it loaded at launch, and refuse work the moment any of them
    /// changed on disk — the failure that started this packet. Costs nothing while
    /// the mailbox is empty, because it is only called when there is work.
    public var makeRunService: @Sendable () -> RunService
    public var runStore: RunStore
    public var owner: String
    public var pollSeconds: TimeInterval

    public init(
        spool: SandboxHandoffSpool = SandboxHandoffSpool(),
        makeRunService: @escaping @Sendable () -> RunService,
        runStore: RunStore = RunStore(),
        owner: String = "mac-app",
        pollSeconds: TimeInterval = 2
    ) {
        self.spool = spool
        self.makeRunService = makeRunService
        self.runStore = runStore
        self.owner = owner
        self.pollSeconds = pollSeconds
    }

    /// Convenience for callers holding a service already — tests, mostly. Real
    /// hosts should pass the factory so a long-lived process never goes stale.
    public init(
        spool: SandboxHandoffSpool = SandboxHandoffSpool(),
        runService: RunService,
        runStore: RunStore = RunStore(),
        owner: String = "mac-app",
        pollSeconds: TimeInterval = 2
    ) {
        self.init(spool: spool, makeRunService: { runService }, runStore: runStore,
                  owner: owner, pollSeconds: pollSeconds)
    }

    /// Claims everything currently waiting and runs it. Returns the run ids that now
    /// have a TERMINAL journal the waiting caller can read — successes and
    /// refusals alike, because a caller cannot tell those apart from silence.
    @discardableResult
    public func drainOnce() async -> [String] {
        let claimed = reclaimOrphansAndClaimWaiting()
        guard !claimed.isEmpty else { return [] }
        return await withTaskGroup(of: String.self) { group in
            for request in claimed {
                group.addTask { await execute(request) }
            }
            var settled: [String] = []
            for await runId in group { settled.append(runId) }
            return settled.sorted()
        }
    }

    /// Claiming is serial and cheap; only execution is concurrent. Keeping the claim
    /// step in one place preserves exactly-once while letting a six-seat review and a
    /// liveness ping proceed at the same time — a serial drain made `alln doctor
    /// handoff` report "nothing is listening" while the host was demonstrably busy.
    private func reclaimOrphansAndClaimWaiting() -> [SandboxHandoffSpool.Request] {
        // A claim whose host died is not a claim. Nothing else ever releases these,
        // so without this pass the request is stranded and its caller is told,
        // wrongly, that nothing picked the work up.
        for stale in (try? spool.claimed()) ?? [] {
            // Finished work whose claimant never got to clean up — including hosts
            // older than this repair, which recorded no identity to check.
            if runStore.load(runId: stale.runId)?.status.isTerminal == true {
                spool.remove(id: stale.id)
                HandoffLog.event("swept run=\(stale.runId) — already terminal, claim left behind")
                continue
            }
            guard let pid = stale.claimantPid, let ticks = stale.claimantStartTimeTicks else { continue }
            let identity = ProcessOwnership.OwnerIdentity(
                pid: pid, pgid: nil, startTimeTicks: ticks, kind: .inProcess)
            guard !ProcessOwnership.isIdentityAlive(identity) else { continue }
            if spool.release(id: stale.id) {
                HandoffLog.event(
                    "reclaimed run=\(stale.runId) from dead host pid=\(pid) (\(stale.claimedBy ?? "?"))")
            }
        }

        guard let waiting = try? spool.unclaimed(), !waiting.isEmpty else { return [] }
        let identity = ProcessOwnership.OwnerIdentity.current(kind: .inProcess)
        var claimed: [SandboxHandoffSpool.Request] = []
        for request in waiting {
            guard let taken = try? spool.claim(
                id: request.id, by: owner,
                pid: identity?.pid, startTimeTicks: identity?.startTimeTicks),
                taken != nil
            else { continue }
            HandoffLog.event(
                "claimed run=\(request.runId) kind=\(request.kind.rawValue) "
                + "team=\(request.presetId ?? "-") root=\(request.repoRoot) by=\(owner)")
            claimed.append(request)
        }
        return claimed
    }

    /// Runs one already-claimed request to a terminal journal.
    private func execute(_ request: SandboxHandoffSpool.Request) async -> String {
        defer { spool.remove(id: request.id) }

        // A ping asks one question — is anything out there claiming requests and
        // writing journals? — and answering it must not start a worker. Settling
        // it here keeps `alln doctor handoff` free and fast, and makes it the one
        // check immune to detection drift, since it bypasses HostSandboxAdvice.
        if request.kind == .ping {
            answerPing(for: request)
            return request.runId
        }

        // Fresh per request: see `makeRunService`.
        let result = await makeRunService().run(
            request.runRequest,
            origin: .cli,
            runId: request.runId
        )
        switch result {
        case .success(let run):
            HandoffLog.event("settled run=\(request.runId) status=\(run.status.rawValue)")
        case .failure(let error):
            // A run that never started still owes the waiting caller an answer.
            // Without this the request evaporates: no journal, no error, and a
            // caller that cannot distinguish "refused" from "nobody listening".
            record(refusal: error, for: request)
        }
        return request.runId
    }

    /// Settles a liveness check: a terminal run in the ordinary journal, naming the
    /// host that answered. No `RunService`, no worker, no quota.
    private func answerPing(for request: SandboxHandoffSpool.Request) {
        let run = TeamRun(
            id: request.runId,
            prompt: request.message,
            status: .complete,
            origin: .cli,
            // Which host answered, on a typed field rather than parsed back out of
            // prose: the request is removed from the mailbox the moment it settles,
            // so the run itself is the only place the caller can still learn this.
            originAgent: owner,
            createdAt: Date(),
            warnings: ["HANDOFF_HOST_ALIVE: claimed and answered by \(owner)"],
            repoRoot: request.repoRoot,
            endReason: .completed
        )
        do {
            _ = try runStore.save(run, models: [])
            HandoffLog.event("pong run=\(request.runId) by=\(owner)")
        } catch let writeError {
            // The host is alive but cannot write the journal — which is itself the
            // answer the caller needs, and the only place left to say it.
            HandoffLog.event("pong run=\(request.runId) BUT the journal write failed: \(writeError)")
        }
    }

    /// Writes the refusal into the ordinary run journal under the id the caller is
    /// already polling, so it comes back through the same renderer as any other
    /// finished run. The failure text is the `RunServiceError`'s own words — this
    /// layer invents no diagnosis of its own.
    private func record(refusal error: RunServiceError, for request: SandboxHandoffSpool.Request) {
        let run = TeamRun(
            id: request.runId,
            prompt: request.message,
            status: .failed,
            origin: .cli,
            presetId: request.presetId,
            createdAt: Date(),
            warnings: ["\(error.code): \(error.description)"],
            repoRoot: request.repoRoot,
            endReason: .failed
        )
        do {
            _ = try runStore.save(run, models: [])
            HandoffLog.event("refused run=\(request.runId) code=\(error.code) reason=\(error.description)")
        } catch let writeError {
            // Nothing left to tell the caller with; say so where it can still be read.
            HandoffLog.event(
                "refused run=\(request.runId) code=\(error.code) "
                + "AND the journal write failed: \(writeError)")
        }
    }

    /// Watches the mailbox until cancelled. Cheap: a directory listing per tick.
    ///
    /// The tick NEVER waits for work it started. A drain that awaited its own runs
    /// stopped claiming for as long as the longest one took, so a six-seat review
    /// blocked every later request — including the liveness ping, which then made
    /// `alln doctor handoff` answer "nothing is listening" about a host that was
    /// visibly busy running a review.
    public func run(isCancelled: @escaping @Sendable () -> Bool) async {
        await withTaskGroup(of: Void.self) { group in
            while !isCancelled() {
                for request in reclaimOrphansAndClaimWaiting() {
                    group.addTask { _ = await execute(request) }
                }
                try? await Task.sleep(for: .seconds(pollSeconds))
            }
        }
    }
}

public extension SandboxHandoffSpool.Request {
    /// The caller's request, rebuilt on the host side.
    ///
    /// Deliberately NOT carried, with reasons, so the omissions are decisions
    /// rather than oversights:
    /// - `timing`: a caller-seeded clock ladder for the CALLER's process. The
    ///   host's run measures itself; importing another process's stamps would
    ///   report times that never happened here.
    /// - `idempotencyKey`: the local attempt that triggered this hand-off may
    ///   already hold it, and re-using it would make the host refuse its own
    ///   work as a duplicate of the run it is replacing.
    var runRequest: RunRequest {
        RunRequest(
            message: message,
            repoRoot: repoRoot,
            threadId: threadId,
            projectId: projectId,
            presetId: presetId,
            pinnedModelId: modelId,
            effort: effort,
            lane: lane,
            type: type,
            context: context,
            deliveries: deliveries,
            executorTeamId: executorTeamId,
            advisoryReview: advisoryReview,
            workerTimeoutSeconds: workerTimeoutSeconds,
            handshakeTimeoutSeconds: handshakeTimeoutSeconds,
            firstActivityTimeoutSeconds: firstActivityTimeoutSeconds,
            wallTimeoutSeconds: wallTimeoutSeconds,
            spawnConcurrencyLimit: spawnConcurrencyLimit,
            commitMessage: commitMessage,
            noCommit: noCommit,
            proofCommand: proofCommand,
            proofTimeoutSeconds: proofTimeoutSeconds,
            retryOf: retryOf,
            acceptSurvivors: acceptSurvivors,
            explicitSeatModelIds: explicitSeatModelIds)
    }
}
