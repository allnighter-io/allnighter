import Foundation
import AllnighterCore

/// Drops one `ping` in the hand-off mailbox and reports what happened to it.
///
/// This is the cheap answer to the only question that matters from inside a
/// sandboxed host: if I hand work off right now, will anything run it? Before this,
/// finding out cost a real multi-seat run — minutes and quota — to learn one bit,
/// and a failure could not be told apart from "the app isn't open".
public struct HandoffDoctor: Sendable {
    public var spool: SandboxHandoffSpool
    public var runStore: RunStore
    /// Short by design: a host polls every couple of seconds and a ping does no
    /// work, so anything alive answers well inside this.
    public var waitSeconds: TimeInterval
    public var pollSeconds: TimeInterval

    public init(
        spool: SandboxHandoffSpool = SandboxHandoffSpool(),
        runStore: RunStore = RunStore(),
        waitSeconds: TimeInterval = 10,
        pollSeconds: TimeInterval = 0.25
    ) {
        self.spool = spool
        self.runStore = runStore
        self.waitSeconds = waitSeconds
        self.pollSeconds = pollSeconds
    }

    public func check(
        contractVersion: String,
        repoRoot: String,
        clock: @Sendable () -> Date = Date.init
    ) async -> HandoffDoctorJSON {
        let startedAt = clock()
        let runId = "handoff-ping-\(UUID().uuidString)"
        let request = SandboxHandoffSpool.Request(
            runId: runId,
            message: "handoff liveness check",
            repoRoot: repoRoot,
            kind: .ping)

        func elapsedMs() -> Int { Int(clock().timeIntervalSince(startedAt) * 1000) }

        do {
            try spool.enqueue(request)
        } catch {
            return .init(
                contractVersion: contractVersion, verdict: .mailboxUnwritable,
                detail: "Could not write to the hand-off mailbox at \(spool.directory.path): "
                    + error.localizedDescription,
                runId: runId, waitedMs: elapsedMs())
        }

        let deadline = startedAt.addingTimeInterval(waitSeconds)
        while clock() < deadline {
            if let settled = runStore.load(runId: runId), settled.status.isTerminal {
                return .init(
                    contractVersion: contractVersion, verdict: .healthy,
                    detail: "A hand-off host claimed this check and answered it. "
                        + "Work handed off from this terminal will run.",
                    runId: runId, waitedMs: elapsedMs(),
                    claimedBy: settled.originAgent ?? spool.request(id: request.id)?.claimedBy)
            }
            try? await Task.sleep(for: .seconds(pollSeconds))
        }

        // Nothing settled. The mailbox itself says which of the two failures it is —
        // observed, not inferred.
        let pending = spool.request(id: request.id)
        spool.remove(id: request.id)
        if let claimedBy = pending?.claimedBy {
            return .init(
                contractVersion: contractVersion, verdict: .claimedButSilent,
                detail: "\(claimedBy) claimed this check \(elapsedMs())ms ago and never answered it. "
                    + "Something is watching the mailbox but is not completing work.",
                runId: runId, waitedMs: elapsedMs(), claimedBy: claimedBy)
        }
        return .init(
            contractVersion: contractVersion, verdict: .hostNotRunning,
            detail: "Nothing claimed this check. Open Allnighter — while it is closed, "
                + "nothing outside your terminal can start your AI tools.",
            runId: runId, waitedMs: elapsedMs())
    }
}
