import Foundation
import AllnighterCore

/// RSC-S01 (`docs/phases/Round_Survives_The_Caller.md`): cross-process mutual exclusion
/// for `RelayCoordinator.resume`/`.adopt`'s load → check-status → flip-`.running` →
/// persist window. Without this, two separate OS processes — two `alln` CLI
/// invocations, or a CLI racing the Mac app (`RelayGUIRuntime.makeCoordinator` builds a
/// coordinator field-for-field identical to the CLI's) — can both load the same
/// pre-mutation `RelayState`, both pass the eligibility check, and both dispatch a dev
/// turn against the same relay id. Actor isolation would not fix this: the racing
/// parties are separate processes, not separate tasks in one process.
///
/// A thin wrapper over `ThreadFlockLock.tryAcquire` — a real, non-blocking, `O_CLOEXEC`
/// `flock(2)` released automatically by the kernel when the holding process dies, so a
/// crashed lock-holder can never wedge a relay. This lock covers ONLY the
/// read-check-write window described above; liveness for the (possibly long) round
/// loop that follows remains owned by `owner.pid` + `RelayCoordinator.reconcileOrphan`,
/// unchanged — this type does not duplicate that mechanism.
public enum RelayDispatchLock {
    /// One lock file per relay id, under a `.locks` sibling of the relay state
    /// directory. `relaysRoot` defaults to production (`AllnighterPaths.relays`), but
    /// callers pass `RelayStateStore.rootDirectory` so a test-injected store root gets
    /// an isolated, collision-free lock path for free — the same store override
    /// already used to sandbox `RelayCoordinatorTests`/`RelayAdoptTests`.
    public static func lockURL(relayId: String, relaysRoot: URL = AllnighterPaths.relays) -> URL {
        relaysRoot
            .appendingPathComponent(".locks", isDirectory: true)
            .appendingPathComponent("\(relayId).dispatch.lock")
    }

    /// Non-blocking try. `nil` means another process currently holds the dispatch lock
    /// for this relay id — the caller (`RelayCoordinator.resume`/`.adopt`) maps that to
    /// `.roundInFlight`, surfaced at the CLI layer as the existing `RELAY_ROUND_IN_FLIGHT`.
    public static func tryAcquire(relayId: String, relaysRoot: URL = AllnighterPaths.relays) -> ThreadFlockLock.Handle? {
        let url = lockURL(relayId: relayId, relaysRoot: relaysRoot)
        do {
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(), withIntermediateDirectories: true
            )
        } catch {
            return nil
        }
        return ThreadFlockLock.tryAcquire(lockURL: url)
    }
}
