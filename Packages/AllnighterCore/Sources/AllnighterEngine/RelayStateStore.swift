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
