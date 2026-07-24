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
    public var owner: String
    public var pollSeconds: TimeInterval

    public init(
        spool: SandboxHandoffSpool = SandboxHandoffSpool(),
        runService: RunService,
        owner: String = "mac-app",
        pollSeconds: TimeInterval = 2
    ) {
        self.spool = spool
        self.runService = runService
        self.owner = owner
        self.pollSeconds = pollSeconds
    }

    /// Claims and runs everything currently waiting. Returns the run ids it
    /// started, so a caller (or a test) can assert what happened.
    @discardableResult
    public func drainOnce() async -> [String] {
        guard let waiting = try? spool.unclaimed(), !waiting.isEmpty else { return [] }
        var started: [String] = []
        for request in waiting {
            guard let claimed = try? spool.claim(id: request.id, by: owner), claimed != nil else { continue }
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
            // The journal is the record either way — a failed run is still an
            // answer the waiting caller must be able to read.
            if case .success = result { started.append(request.runId) }
            spool.remove(id: request.id)
        }
        return started
    }

    /// Watches the mailbox until cancelled. Cheap: a directory listing per tick.
    public func run(isCancelled: @escaping @Sendable () -> Bool) async {
        while !isCancelled() {
            await drainOnce()
            try? await Task.sleep(for: .seconds(pollSeconds))
        }
    }
}
