import Foundation
import AllnighterCore

/// RLR-L8 clock fire → KillSettlement + `timedOut` terminal (S05).
///
/// Operator-vs-clock asymmetry: an operator kill/cancel stamps terminal only on
/// verified stop; a clock firing stamps `timedOut` **regardless** of reap
/// outcome. Survivors are recorded via `killOutcome` and surface as
/// `contradiction: terminalWithLiveOwnership` until reaped.
///
/// Does not invent a second idle timer — the existing stall/watchdog paths
/// (ProcessGroupCommandRunner / worker `timedOut`) call into this enforcer to
/// settle the journal. Pure `evaluate` lets tests + status reason about budgets
/// without sleeping.
public enum RunClockEnforcer {

    public struct FireResult: Sendable, Equatable {
        public var outcome: KillOutcome
        public var survivors: [String]
        public var signalled: Bool
        public var clock: RunClockKind

        public init(outcome: KillOutcome, survivors: [String], signalled: Bool, clock: RunClockKind) {
            self.outcome = outcome
            self.survivors = survivors
            self.signalled = signalled
            self.clock = clock
        }
    }

    /// Pure: which clock (if any) has exceeded its budget. Prefers the earliest
    /// deadline when several would fire. `idleBudgetSeconds` is the effective
    /// idle bound (CLI override or manifest); `nil` skips the idle check.
    public static func evaluate(
        budgets: RunClockBudgets,
        createdAt: Date,
        lastActivityAt: Date?,
        now: Date,
        lifecycle: RunLifecycle,
        phase: RunPhase?,
        idleBudgetSeconds: Double? = nil
    ) -> RunClockKind? {
        guard !lifecycle.isTerminal else { return nil }

        var candidates: [(RunClockKind, Date)] = []

        let wallDeadline = createdAt.addingTimeInterval(budgets.wallTimeoutSeconds)
        if now >= wallDeadline {
            candidates.append((.wall, wallDeadline))
        }

        // Handshake: still queued waiting to spawn / accept a runner.
        if lifecycle == .queued,
           phase == .spawningWorker || phase == .waitingForWriteLock || phase == .waitingForVendor {
            let hs = createdAt.addingTimeInterval(budgets.handshakeTimeoutSeconds)
            if now >= hs { candidates.append((.handshake, hs)) }
        }

        // First post-spawn activity: running, never advanced lastActivityAt.
        if lifecycle == .running, lastActivityAt == nil {
            let fa = createdAt.addingTimeInterval(budgets.firstActivityTimeoutSeconds)
            if now >= fa { candidates.append((.firstActivity, fa)) }
        }

        // Rolling idle: only after first L6 activity.
        let idle = idleBudgetSeconds ?? budgets.idleTimeoutSeconds
        if let idle, idle > 0, let last = lastActivityAt {
            let idleDeadline = last.addingTimeInterval(idle)
            if now >= idleDeadline { candidates.append((.idle, idleDeadline)) }
        }

        return candidates.min(by: { $0.1 < $1.1 })?.0
    }

    /// Settle the kill tree, then stamp `timedOut` terminal **even on partial**.
    /// Idempotent when the journal is already terminal.
    @discardableResult
    public static func fire(
        clock: RunClockKind,
        runDirectory: URL,
        runStore: RunStore,
        graceMicrosOverride: useconds_t? = nil
    ) -> FireResult? {
        ProcessOwnership.withRunLock(in: runDirectory) {
            guard let data = try? Data(contentsOf: runDirectory.appendingPathComponent("run.json")),
                  var current = try? CoreJSON.decode(TeamRun.self, from: data) else {
                return nil
            }
            if current.status.isTerminal {
                return FireResult(
                    outcome: current.killOutcome ?? .stopped,
                    survivors: [],
                    signalled: false,
                    clock: clock
                )
            }

            let settlement = KillSettlement.settle(
                runDirectory: runDirectory,
                mode: .kill,
                run: current,
                graceMicrosOverride: graceMicrosOverride
            )

            // Clock asymmetry: ALWAYS stamp timedOut terminal, regardless of reap.
            current.status = .timedOut
            current.endReason = .timedOut
            current.killOutcome = settlement.outcome
            current.phase = nil
            for i in current.answers.indices where !current.answers[i].result.status.isTerminal {
                current.answers[i].result.status = .timedOut
            }
            let wasBlocked = current.blocker != nil
            current.blocker = nil
            if wasBlocked {
                ExecutionLaneFlock.withdrawWaiter(
                    laneKey: ExecutionLane.key(repoRoot: current.repoRoot), claimId: current.id)
            }
            _ = try? runStore.save(current, models: [])

            return FireResult(
                outcome: settlement.outcome,
                survivors: settlement.survivors,
                signalled: settlement.signalled,
                clock: clock
            )
        }
    }
}
