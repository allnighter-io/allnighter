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
    public var runService: RunService
    public var runStore: RunStore
    public var owner: String
    public var pollSeconds: TimeInterval

    public init(
        spool: SandboxHandoffSpool = SandboxHandoffSpool(),
        runService: RunService,
        runStore: RunStore = RunStore(),
        owner: String = "mac-app",
        pollSeconds: TimeInterval = 2
    ) {
        self.spool = spool
        self.runService = runService
        self.runStore = runStore
        self.owner = owner
        self.pollSeconds = pollSeconds
    }

    /// Claims and runs everything currently waiting. Returns the run ids that now
    /// have a TERMINAL journal the waiting caller can read — successes and
    /// refusals alike, because a caller cannot tell those apart from silence.
    @discardableResult
    public func drainOnce() async -> [String] {
        guard let waiting = try? spool.unclaimed(), !waiting.isEmpty else { return [] }
        var settled: [String] = []
        for request in waiting {
            guard let claimed = try? spool.claim(id: request.id, by: owner), claimed != nil else { continue }
            HandoffLog.event(
                "claimed run=\(request.runId) kind=\(request.kind.rawValue) "
                + "team=\(request.presetId ?? "-") root=\(request.repoRoot) by=\(owner)")

            // A ping asks one question — is anything out there claiming requests and
            // writing journals? — and answering it must not start a worker. Settling
            // it here keeps `alln doctor handoff` free and fast, and makes it the one
            // check immune to detection drift, since it bypasses HostSandboxAdvice.
            if request.kind == .ping {
                answerPing(for: request)
                settled.append(request.runId)
                spool.remove(id: request.id)
                continue
            }

            let result = await runService.run(
                RunRequest(
                    message: request.message,
                    repoRoot: request.repoRoot,
                    presetId: request.presetId,
                    workerId: request.workerId
                ),
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
            settled.append(request.runId)
            spool.remove(id: request.id)
        }
        return settled
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
    public func run(isCancelled: @escaping @Sendable () -> Bool) async {
        while !isCancelled() {
            await drainOnce()
            try? await Task.sleep(for: .seconds(pollSeconds))
        }
    }
}
