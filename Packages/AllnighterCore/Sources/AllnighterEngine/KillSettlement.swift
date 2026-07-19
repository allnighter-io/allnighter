import Foundation
import Darwin
import AllnighterCore

/// The ONE identity-checked kill/cancel settlement (RLR-L5, RLR-S04b).
///
/// Both operator verbs — `alln kill` (immediate) and `alln team cancel`
/// (grace-then-escalate) — collapse into this routine. It replaces the two
/// unconditional terminal stampers (`ProcessOwnershipSurface.killRun` and
/// `AsyncTeamService.cancel`) with a verified settlement that returns a typed
/// `KillOutcome`. The caller stamps a terminal `endReason` **only** on
/// `.stopped`; `partial`/`refused`/`verificationUnavailable` leave the lifecycle
/// non-terminal (the operator-vs-clock asymmetry: an operator stop that cannot
/// be verified is honest partial/refused, never a `killed` lie over live work).
///
/// The 8-step RLR-L5 protocol, mapped to the existing primitives (RLR §1.6):
///  1. Snapshot recorded identities — the run-dir-root coordinator `owner.json`
///     plus every `workers/<id>.owner.json` receipt (`readWorkerOwners`).
///  2. Terminate WORKER groups first (not a responsive coordinator): a TERM-only
///     identity-guarded group signal (`signalOwnerGroupTermIfSafe`), then a
///     mode-specific grace. `cancel` waits a longer bounded grace than `kill`.
///  3. The caller (killer) stamps the terminal revision + `killOutcome` itself,
///     under `withRunLock`, ONLY when this routine returns `.stopped`.
///  4-5. A responsive coordinator (identity-alive, PG-killable) is left to emit
///     its own single terminal event — it is signalled ONLY when it is the sole
///     recorded execution tree (no worker receipts). It is never force-killed
///     while a recorded worker is being verified.
///  6. Concurrent killers are made idempotent by the caller's flock + terminal
///     guard — this routine is pure verify/signal and never writes the journal.
///  7. Verify identity-alive per recorded member (zombie-aware, S04a) AND the
///     recorded group is empty. A live/non-empty member ⇒ survivor ⇒ `.partial`.
///  8. Receipts are RETAINED (this routine never clears a worker owner), so the
///     S04c contradiction surface can read a still-alive recorded member.
public enum KillSettlement {

    /// `kill` is the immediate red button (short TERM grace); `cancel` is the
    /// graceful stop (longer bounded TERM grace). Neither force-SIGKILLs a
    /// recorded member that survives its TERM grace — a survivor settles
    /// `.partial` (RLR §2.4): the honest verdict, not a lie-free forced reap.
    /// Reconcile of identity-DEAD owners keeps the full TERM→KILL primitive.
    public enum Mode: Sendable, Equatable {
        case kill
        case cancel
    }

    public struct Result: Sendable, Equatable {
        public var outcome: KillOutcome
        /// Recorded members (worker ids, or `"coordinator"`) still alive/non-empty
        /// after the grace. Empty for `.stopped`/`.refused`/`.verificationUnavailable`.
        public var survivors: [String]
        /// True when the run settled `.stopped` only because the sole residual was
        /// a `<defunct>` zombie group member (RLR-L5 zombie-only cleanup warning).
        public var cleanupWarning: Bool
        /// True when at least one recorded member's group was actually signalled.
        public var signalled: Bool

        public init(outcome: KillOutcome, survivors: [String] = [], cleanupWarning: Bool = false, signalled: Bool = false) {
            self.outcome = outcome
            self.survivors = survivors
            self.cleanupWarning = cleanupWarning
            self.signalled = signalled
        }
    }

    /// Immediate TERM grace for `kill` (microseconds). Long enough for a
    /// compliant worker to exit; a member still alive after it settles `.partial`.
    public static let killGraceMicros: useconds_t = 200_000
    /// Bounded TERM grace for `cancel` before the verdict (microseconds).
    public static let cancelGraceMicros: useconds_t = 1_500_000

    /// Settle one run. `run` MUST be the fresh journal read under the caller's
    /// `withRunLock`. Pure verify/signal — never writes the journal.
    ///
    /// `graceMicrosOverride` lets tests pick a tiny grace; when
    /// `ProcessOwnership.terminateSignalHook` is set (unit tests) the real grace
    /// sleep is skipped entirely so no wall-clock time is spent.
    public static func settle(
        runDirectory: URL,
        mode: Mode,
        run: TeamRun,
        graceMicrosOverride: useconds_t? = nil
    ) -> Result {
        // Step 1 — snapshot recorded identities.
        let coordinator = ProcessOwnership.readOwnerIdentity(in: runDirectory)
        let workers = ProcessOwnership.readWorkerOwners(inRunDirectory: runDirectory)
        // Only a PG-killable coordinator is a settleable execution member; an
        // `inProcess` coordinator is a receipt, not a signal target.
        let killableCoordinator = coordinator.flatMap { $0.kind.isProcessGroupKillable ? $0 : nil }

        // No recorded WORKER receipt and no PG-killable coordinator.
        if workers.isEmpty, killableCoordinator == nil {
            // A run that never entered execution (queued/blocked/draft) has nothing
            // that can survive — a verified stop.
            if neverExecuted(run) {
                return Result(outcome: .stopped)
            }
            // A live cooperative in-process owner (Mac app / sync run) honours the
            // journal cancel — a verified cooperative stop (there is no separate OS
            // process to reap). Only a run that is executing with NO recorded owner
            // at ALL cannot be verified: the warm-driver exclusion seam (RLR §1.9) —
            // warm pools record nothing — never stamp `killed` unverified.
            if coordinator != nil {
                return Result(outcome: .stopped)
            }
            return Result(outcome: .verificationUnavailable)
        }

        // Step 2 — signal worker groups first (leave a responsive coordinator);
        // if there are NO worker receipts, the coordinator IS the execution tree.
        var signalledAny = false
        for (_, identity) in workers {
            if ProcessOwnership.signalOwnerGroupTermIfSafe(identity) { signalledAny = true }
        }
        if workers.isEmpty, let coordinator = killableCoordinator {
            if ProcessOwnership.signalOwnerGroupTermIfSafe(coordinator) { signalledAny = true }
        }

        // Recorded members exist but none could be signalled (all recycled /
        // non-PG-killable) — nothing was stopped.
        if !signalledAny {
            return Result(outcome: .refused, signalled: false)
        }

        // Mode-specific bounded grace before the verify (skipped under the test
        // signal hook so unit tests spend no wall-clock time).
        if ProcessOwnership.terminateSignalHook == nil {
            let grace = graceMicrosOverride ?? (mode == .kill ? killGraceMicros : cancelGraceMicros)
            if grace > 0 { usleep(grace) }
        }

        // Step 7 — verify identity-alive (zombie-aware) AND group-empty per
        // recorded member. A live-or-non-empty member is a survivor.
        var survivors: [String] = []
        var anyLiveNonZombie = false
        func inspect(_ label: String, _ identity: ProcessOwnership.OwnerIdentity) {
            let alive = ProcessOwnership.isIdentityAlive(identity)
            let groupNonEmpty = identity.pgid.map { !ProcessOwnership.isProcessGroupEmpty($0) } ?? false
            if alive || groupNonEmpty {
                survivors.append(label)
                if alive { anyLiveNonZombie = true }
            }
        }
        for (workerId, identity) in workers { inspect(workerId, identity) }
        if workers.isEmpty, let coordinator = killableCoordinator { inspect("coordinator", coordinator) }

        if survivors.isEmpty {
            return Result(outcome: .stopped, signalled: true)
        }
        // Zombie-only residual: no identity-alive member remains, only a
        // `<defunct>` group member — a verified stop with a cleanup warning.
        if !anyLiveNonZombie {
            return Result(outcome: .stopped, survivors: [], cleanupWarning: true, signalled: true)
        }
        return Result(outcome: .partial, survivors: survivors, signalled: true)
    }

    /// A run that has not entered execution: still `queued`/`draft`, or parked on
    /// a blocker (RLR-L4) — it demonstrably never spawned a worker, so a kill of
    /// it is a verified stop (there is nothing to survive).
    private static func neverExecuted(_ run: TeamRun) -> Bool {
        if run.status.isTerminal { return false }
        return run.status == .queued || run.status == .draft || run.blocker != nil
    }
}
