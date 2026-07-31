import Foundation
import AllnighterCore

/// Persists `LoopState` to disk as one folder per relay — `relays/<id>/relay.json` —
/// mirroring `RunStore`'s per-id folder + atomic-write pattern (PM_Relay.md §6 R-S04).
/// `LoopCoordinator` saves after every round-level state change, so a relay is resumable
/// from disk at any point mid-round, never only in memory.
public struct LoopStateStore: Sendable {
    public enum RelayLoadFailure: Sendable, Equatable, Error {
        case notFound(id: String)
        case decodeFailed(DecodeFailed)

        public struct DecodeFailed: Sendable, Equatable {
            public var id: String
            public var path: String
            /// True when `relay.json` still carries WTA-retired `devWorkerId`/`pmWorkerId` keys.
            public var retiredWorkerKeys: Bool

            public var agentMessage: String {
                if retiredWorkerKeys {
                    return "relay state at \(path) uses retired devWorkerId/pmWorkerId keys — rebuild alln from the current branch (`swift build` + `alln install-cli`); a stale on-PATH binary wrote or cannot read this relay"
                }
                return "relay state at \(path) could not be decoded — inspect relay.json or delete the relay folder"
            }
        }
    }

    public let rootDirectory: URL

    public init(rootDirectory: URL? = nil) {
        self.rootDirectory = rootDirectory ?? AllnighterPaths.loops
    }

    private func relayJSONURL(id: String) -> URL {
        rootDirectory.appendingPathComponent(id, isDirectory: true).appendingPathComponent("relay.json")
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
    /// save) — the signal `LoopCoordinator.reconcileIfOrphaned` reads to detect a
    /// relay whose process died mid-round (works-test hazard #1).
    ///
    /// Pilot's `awaitingPM` (`docs/phases/Pilot_Relay.md` §2) is a PARKED, UNOWNED
    /// state, not `.running` — this `if` only ever fires for `.running`, so an
    /// `awaitingPM` save never writes (and always clears, same as any other
    /// terminal-shaped save) `owner.pid`. A pilot relay can sit parked for days with
    /// no process behind it; that is by design, not an oversight.
    @discardableResult
    public func save(_ state: LoopState) throws -> URL {
        let directory = try relayDirectory(id: state.id)
        let ownerURL = directory.appendingPathComponent("owner.pid")
        if state.status == .running {
            try Data("\(LoopStateStore.currentPID)".utf8).write(to: ownerURL, options: .atomic)
        }
        try CoreJSON.encode(state).write(to: directory.appendingPathComponent("relay.json"), options: .atomic)
        if state.status != .running {
            try? FileManager.default.removeItem(at: ownerURL)
        }
        return directory
    }

    /// Distinguishes a missing relay from a present-but-unreadable `relay.json`.
    public func loadResult(id: String) -> Result<LoopState, RelayLoadFailure> {
        let url = relayJSONURL(id: id)
        guard FileManager.default.fileExists(atPath: url.path) else {
            return .failure(.notFound(id: id))
        }
        guard let data = try? Data(contentsOf: url) else {
            return .failure(.decodeFailed(.init(id: id, path: url.path, retiredWorkerKeys: false)))
        }
        do {
            return .success(try CoreJSON.decode(LoopState.self, from: data))
        } catch {
            let raw = String(data: data, encoding: .utf8) ?? ""
            let retired = Self.containsRetiredWorkerKeys(in: raw)
            return .failure(.decodeFailed(.init(id: id, path: url.path, retiredWorkerKeys: retired)))
        }
    }

    public func load(id: String) -> LoopState? {
        switch loadResult(id: id) {
        case .success(let state): return state
        case .failure: return nil
        }
    }

    /// True when `id`'s `owner.pid` marker is missing/unparsable, or names a process
    /// that is no longer alive. Missing counts as dead — a relay whose folder predates
    /// this marker (or was hand-edited) is never assumed alive without proof, matching
    /// `RunStore`'s "never falsely running" rule. Pure read, no side effects; the
    /// caller (`LoopCoordinator.reconcileIfOrphaned`) owns the write-back.
    public func isOwnerDead(id: String) -> Bool {
        let ownerURL = rootDirectory.appendingPathComponent(id, isDirectory: true).appendingPathComponent("owner.pid")
        guard let raw = try? String(contentsOf: ownerURL, encoding: .utf8),
              let pid = Int32(raw.trimmingCharacters(in: .whitespacesAndNewlines)) else { return true }
        return !RunStore.processAlive(pid)
    }

    private static var currentPID: Int32 { ProcessInfo.processInfo.processIdentifier }

    /// All relays, newest first. Skips folders whose `relay.json` fails to decode;
    /// use `loadResult` or `LoopPersistenceDoctorCheck` to surface those rows.
    public func list() -> [LoopState] {
        guard let entries = try? FileManager.default.contentsOfDirectory(
            at: rootDirectory, includingPropertiesForKeys: nil
        ) else {
            return []
        }
        return entries
            .compactMap { load(id: $0.lastPathComponent) }
            .sorted { $0.createdAt > $1.createdAt }
    }

    /// Detects WTA-retired persisted seat keys at the JSON-object level (not prose in
    /// handover text). Used by load failures and `alln doctor`.
    public static func containsRetiredWorkerKeys(in jsonText: String) -> Bool {
        jsonText.contains(#""devWorkerId""#) || jsonText.contains(#""pmWorkerId""#)
    }
}
