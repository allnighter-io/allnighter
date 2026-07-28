import Foundation
import AllnighterCore
#if canImport(CryptoKit)
import CryptoKit
#else
import Crypto
#endif

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

    // MARK: - RSC-S02: start-time lock (root + doc, no relay id exists yet)

    /// Canonical doc identity for duplicate-start matching: strips a leading `./` and
    /// collapses `//` so `docs/spec.md` and `./docs/spec.md` share the same start key.
    public static func normalizeDocPath(_ docPath: String) -> String {
        var normalized = docPath
        while normalized.hasPrefix("./") {
            normalized.removeFirst(2)
        }
        while normalized.contains("//") {
            normalized = normalized.replacingOccurrences(of: "//", with: "/")
        }
        return normalized
    }

    /// `RelayCoordinator.run`'s duplicate-scan → persist window has no relay id to key a
    /// lock on until AFTER that window (the id is minted inside it) — so this lock is
    /// keyed on the START key instead: `sha256(RootNormalization.normalize(root).key +
    /// "|" + normalizeDocPath(docPath))`. A different lock FILE than `lockURL(relayId:)`
    /// above (own `.locks` filename), so a start racing a resume/adopt on some unrelated
    /// relay id never contends with either.
    public static func startKey(projectRoot: String, docPath: String) -> String {
        let normalizedRoot = RootNormalization.normalize(projectRoot).key
        let normalizedDoc = normalizeDocPath(docPath)
        let digest = SHA256.hash(data: Data("\(normalizedRoot)|\(normalizedDoc)".utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    public static func startLockURL(startKey: String, relaysRoot: URL = AllnighterPaths.relays) -> URL {
        relaysRoot
            .appendingPathComponent(".locks", isDirectory: true)
            .appendingPathComponent("start-\(startKey).start.lock")
    }

    /// Blocking exclusive acquire (unlike `tryAcquire` above): the critical section this
    /// guards is a quick scan of `RelayStateStore.list()` plus one `save` — not a
    /// long-lived round loop — so a brief wait for a concurrent start on the SAME
    /// root+doc to clear its identical window is correct, not a hang risk. Still a real
    /// `flock(2)`, released by the kernel if the holder dies, so a crashed starter can
    /// never wedge a later start.
    public static func acquireStart(startKey: String, relaysRoot: URL = AllnighterPaths.relays) -> ThreadFlockLock.Handle? {
        let url = startLockURL(startKey: startKey, relaysRoot: relaysRoot)
        do {
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(), withIntermediateDirectories: true
            )
        } catch {
            return nil
        }
        return try? ThreadFlockLock.acquire(lockURL: url)
    }
}
