import Foundation
import AllnighterCore

/// Persists `RelayState` to disk as one folder per relay — `relays/<id>/relay.json` —
/// mirroring `RunStore`'s per-id folder + atomic-write pattern (PM_Relay.md §6 R-S04).
/// `RelayCoordinator` saves after every round-level state change, so a relay is resumable
/// from disk at any point mid-round, never only in memory.
public struct RelayStateStore: Sendable {
    public let rootDirectory: URL

    public init(rootDirectory: URL? = nil) {
        self.rootDirectory = rootDirectory ?? AllnighterPaths.relays
    }

    private func relayDirectory(id: String) throws -> URL {
        let directory = rootDirectory.appendingPathComponent(id, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    /// Public directory for a relay id (creates it). Used by PO-S02 to record the
    /// in-flight dev-turn owner under the same folder as `relay.json`.
    public func directory(for id: String) throws -> URL {
        try relayDirectory(id: id)
    }

    /// Atomic write (temp + rename) so a concurrent reader never sees a torn file.
    /// Also records/clears an `owner.pid` liveness marker — the SAME convention
    /// `RunStore.save` uses (owner.pid written FIRST for a non-terminal `.running`
    /// state so a reader can never see `relay.json` without it, removed on a terminal
    /// save) — the signal `RelayCoordinator.reconcileIfOrphaned` reads to detect a
    /// relay whose process died mid-round (works-test hazard #1).
    ///
    /// Pilot's `awaitingPM` (`docs/phases/Pilot_Relay.md` §2) is a PARKED, UNOWNED
    /// state, not `.running` — this `if` only ever fires for `.running`, so an
    /// `awaitingPM` save never writes (and always clears, same as any other
    /// terminal-shaped save) `owner.pid`. A pilot relay can sit parked for days with
    /// no process behind it; that is by design, not an oversight.
    @discardableResult
    public func save(_ state: RelayState) throws -> URL {
        let directory = try relayDirectory(id: state.id)
        let ownerURL = directory.appendingPathComponent("owner.pid")
        if state.status == .running {
            try Data("\(RelayStateStore.currentPID)".utf8).write(to: ownerURL, options: .atomic)
        }
        try CoreJSON.encode(state).write(to: directory.appendingPathComponent("relay.json"), options: .atomic)
        if state.status != .running {
            try? FileManager.default.removeItem(at: ownerURL)
        }
        return directory
    }

    /// RSC-S03 hot-fix (`docs/phases/Round_Survives_The_Caller.md`, "second gap"):
    /// re-stamps `owner.pid` alone to `pid` — never touches `relay.json`. `--no-wait`
    /// resume/adopt's guard step (`RelayCoordinator.resumeGuard`/`adoptGuard`) flips
    /// `status` to `.running` and calls `save`, which self-stamps `owner.pid` with the
    /// FOREGROUND process's own pid (it is the calling process at that point — it
    /// hasn't spawned the detached child yet). The foreground then calls
    /// `DetachedDispatch.launch`, which returns the child's real `Process`
    /// synchronously (`.processIdentifier` is available right after `.run()`, no
    /// async wait) — so the foreground calls this immediately after, BEFORE it exits,
    /// to correct `owner.pid` to the child's real pid. Without this, `owner.pid` names
    /// a process that is either already dead (foreground exited) or about to be, for
    /// the whole window until the child reaches its own `continueRound` persist —
    /// long enough (real I/O in `ServeAutoLaunchCLI.ensureRunning`) for a concurrent
    /// `reconcileOrphan` read (`pair relay-status`, unlocked) to see a dead-owner
    /// `.running` relay and kill a legitimately in-flight continuation.
    ///
    /// A no-op (never writes) unless `id`'s current durable status is still
    /// `.running` — mirrors `save`'s own discipline that `owner.pid` only ever exists
    /// for a `.running` relay, so this can never resurrect a stale owner.pid file for
    /// a relay that already went terminal between the guard's persist and this call
    /// (e.g. immediately reconciled by an unrelated concurrent reader — see the doc
    /// comment on `save` for why that path only fires while an owner is still
    /// provably alive, which the foreground still is at this exact point).
    public func restampOwner(id: String, pid: Int32) {
        guard let current = load(id: id), current.status == .running else { return }
        let directory = (try? relayDirectory(id: id)) ?? rootDirectory.appendingPathComponent(id, isDirectory: true)
        let ownerURL = directory.appendingPathComponent("owner.pid")
        try? Data("\(pid)".utf8).write(to: ownerURL, options: .atomic)
    }

    public func load(id: String) -> RelayState? {
        let url = rootDirectory.appendingPathComponent(id, isDirectory: true).appendingPathComponent("relay.json")
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? CoreJSON.decode(RelayState.self, from: data)
    }

    /// True when `id`'s `owner.pid` marker is missing/unparsable, or names a process
    /// that is no longer alive. Missing counts as dead — a relay whose folder predates
    /// this marker (or was hand-edited) is never assumed alive without proof, matching
    /// `RunStore`'s "never falsely running" rule. Pure read, no side effects; the
    /// caller (`RelayCoordinator.reconcileIfOrphaned`) owns the write-back.
    public func isOwnerDead(id: String) -> Bool {
        let ownerURL = rootDirectory.appendingPathComponent(id, isDirectory: true).appendingPathComponent("owner.pid")
        guard let raw = try? String(contentsOf: ownerURL, encoding: .utf8),
              let pid = Int32(raw.trimmingCharacters(in: .whitespacesAndNewlines)) else { return true }
        return !RunStore.processAlive(pid)
    }

    private static var currentPID: Int32 { ProcessInfo.processInfo.processIdentifier }

    /// All relays, newest first. Skips any folder whose `relay.json` fails to decode rather
    /// than failing the whole listing.
    public func list() -> [RelayState] {
        guard let entries = try? FileManager.default.contentsOfDirectory(
            at: rootDirectory, includingPropertiesForKeys: nil
        ) else {
            return []
        }
        return entries
            .compactMap { load(id: $0.lastPathComponent) }
            .sorted { $0.createdAt > $1.createdAt }
    }
}
