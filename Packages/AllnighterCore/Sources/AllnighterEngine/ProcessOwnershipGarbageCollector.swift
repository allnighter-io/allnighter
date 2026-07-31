import Foundation
import AllnighterCore

/// Prunes old, dead, terminal ownership records while preserving durable run
/// truth referenced by threads. This is the Runs/Relays analogue of stale-lane
/// GC, with stricter record-level retention and reference checks.
public struct ProcessOwnershipGarbageCollector: Sendable {
    /// Applied independently to Runs and Relays/Pilots.
    public static let defaultRetentionCount = 100
    /// An unreadable (missing/undecodable `run.json`) dir is pruned only once its mtime is
    /// older than this — a recent unreadable dir could be a mid-write / in-flight run. Old +
    /// undecodable = provably dead cruft (schema-drifted or aborted runs).
    public static let defaultUnreadableMinAgeSeconds: TimeInterval = 24 * 60 * 60

    public var runStore: RunStore
    public var loopStore: LoopStateStore
    public var threadStore: ThreadStore
    public var retentionCount: Int
    /// When true, classify exactly as a real run would (including the under-lock re-check)
    /// but never delete — `pruned` reports what WOULD be removed. For `alln gc --dry-run`.
    public var dryRun: Bool
    /// Minimum mtime age before an unreadable dir is prunable (see the static default).
    public var unreadableMinAgeSeconds: TimeInterval

    public init(
        runStore: RunStore = RunStore(),
        loopStore: LoopStateStore? = nil,
        threadStore: ThreadStore? = nil,
        retentionCount: Int = ProcessOwnershipGarbageCollector.defaultRetentionCount,
        dryRun: Bool = false,
        unreadableMinAgeSeconds: TimeInterval = ProcessOwnershipGarbageCollector.defaultUnreadableMinAgeSeconds
    ) {
        let supportRoot = runStore.rootDirectory.deletingLastPathComponent()
        self.runStore = runStore
        self.loopStore = loopStore ?? LoopStateStore(
            rootDirectory: supportRoot.appendingPathComponent("Loops", isDirectory: true)
        )
        self.threadStore = threadStore ?? ThreadStore(
            rootDirectory: supportRoot.appendingPathComponent("Threads", isDirectory: true)
        )
        self.retentionCount = max(0, retentionCount)
        self.dryRun = dryRun
        self.unreadableMinAgeSeconds = unreadableMinAgeSeconds
    }

    /// An unreadable dir (missing/undecodable `run.json`) whose mtime is older than
    /// `unreadableMinAgeSeconds` is provably-dead cruft → prune (respecting `dryRun`);
    /// otherwise keep (could be a mid-write / in-flight run). Shared by run + relay sweeps.
    private func classifyUnreadable(
        _ directory: URL, id: String, kind: String, into result: inout MutableResult
    ) {
        let row = OwnershipGarbageCollectionRecordJSON(
            id: id, kind: kind, detail: "\(kind).json missing or unreadable")
        let mtime = try? directory.resourceValues(
            forKeys: [.contentModificationDateKey]).contentModificationDate
        let old = mtime.map { Date().timeIntervalSince($0) > unreadableMinAgeSeconds } ?? false
        guard old else { result.keptUnreadable.append(row); return }
        if dryRun { result.pruned.append(row); return }
        do {
            try FileManager.default.removeItem(at: directory)
            result.pruned.append(row)
        } catch {
            result.keptRemovalFailed.append(.init(
                id: id, kind: kind, detail: error.localizedDescription))
        }
    }

    @discardableResult
    public func collect() -> OwnershipGarbageCollectionJSON {
        var result = MutableResult(retentionCount: retentionCount)
        collectRuns(into: &result)
        collectRelays(into: &result)
        return result.json
    }

    private func collectRuns(into result: inout MutableResult) {
        let snapshots = runSnapshots(into: &result)
        let retained = retainedIds(snapshots.filter(\.terminal))
        let threadRunIds = referencedRunIds()

        for snapshot in snapshots {
            let row = snapshot.row
            // RLR-S06: before run-dir prune decisions, drop identity-dead
            // ownership receipts past the contradiction retention window.
            if snapshot.terminal {
                _ = ProcessOwnership.reapExpiredOwnershipReceipts(
                    in: snapshot.directory, isTerminal: true)
            }
            if snapshot.identityAlive {
                result.keptAlive.append(row)
            } else if !snapshot.terminal {
                result.keptNonTerminal.append(row)
            } else if snapshot.threadLinked || threadRunIds.contains(snapshot.id) {
                result.keptThreadReferenced.append(row)
            } else if retained.contains(snapshot.id) {
                result.keptWithinRetention.append(row)
            } else {
                pruneRun(snapshot, threadRunIds: threadRunIds, into: &result)
            }
        }
    }

    private func collectRelays(into result: inout MutableResult) {
        let snapshots = relaySnapshots(into: &result)
        let retained = retainedIds(snapshots.filter(\.terminal))

        for snapshot in snapshots {
            let row = snapshot.row
            if snapshot.identityAlive {
                result.keptAlive.append(row)
            } else if !snapshot.terminal {
                result.keptNonTerminal.append(row)
            } else if retained.contains(snapshot.id) {
                result.keptWithinRetention.append(row)
            } else {
                pruneRelay(snapshot, into: &result)
            }
        }
    }

    private func runSnapshots(into result: inout MutableResult) -> [Snapshot] {
        guard let entries = try? FileManager.default.contentsOfDirectory(
            at: runStore.rootDirectory,
            includingPropertiesForKeys: nil
        ) else { return [] }

        return entries.compactMap { directory in
            guard directory.lastPathComponent.hasPrefix("run_") else { return nil }
            guard let data = try? Data(contentsOf: directory.appendingPathComponent("run.json")),
                  let run = try? CoreJSON.decode(TeamRun.self, from: data) else {
                classifyUnreadable(
                    directory,
                    id: String(directory.lastPathComponent.dropFirst("run_".count)),
                    kind: "run", into: &result)
                return nil
            }
            let alive = ProcessOwnership.readOwnerIdentity(in: directory)
                .map(ProcessOwnership.isIdentityAlive) ?? false
            return Snapshot(
                id: run.id,
                directory: directory,
                createdAt: run.createdAt,
                status: run.status.rawValue,
                kind: "run",
                terminal: run.status.isTerminal,
                identityAlive: alive,
                threadLinked: run.threadId != nil
            )
        }
    }

    private func relaySnapshots(into result: inout MutableResult) -> [Snapshot] {
        guard let entries = try? FileManager.default.contentsOfDirectory(
            at: loopStore.rootDirectory,
            includingPropertiesForKeys: nil
        ) else { return [] }

        return entries.compactMap { directory in
            guard let data = try? Data(contentsOf: directory.appendingPathComponent("relay.json")),
                  let relay = try? CoreJSON.decode(LoopState.self, from: data) else {
                classifyUnreadable(
                    directory, id: directory.lastPathComponent, kind: "relay", into: &result)
                return nil
            }
            let identity = ProcessOwnership.readTurnOwner(in: directory)
                ?? relay.rounds.last?.devTurnOwner.flatMap(ProcessOwnership.OwnerIdentity.fromRecord)
            let kind = "loop"
            return Snapshot(
                id: relay.id,
                directory: directory,
                createdAt: relay.createdAt,
                status: relay.status.rawValue,
                kind: kind,
                terminal: relay.isGarbageCollectionTerminal,
                identityAlive: identity.map(ProcessOwnership.isIdentityAlive) ?? false,
                threadLinked: false
            )
        }
    }

    private func retainedIds(_ terminal: [Snapshot]) -> Set<String> {
        Set(terminal.sorted { lhs, rhs in
            if lhs.createdAt != rhs.createdAt { return lhs.createdAt > rhs.createdAt }
            return lhs.id > rhs.id
        }.prefix(retentionCount).map(\.id))
    }

    private func pruneRun(
        _ snapshot: Snapshot,
        threadRunIds: Set<String>,
        into result: inout MutableResult
    ) {
        ProcessOwnership.withRunLock(in: snapshot.directory) {
            guard let data = try? Data(contentsOf: snapshot.directory.appendingPathComponent("run.json")),
                  let run = try? CoreJSON.decode(TeamRun.self, from: data) else {
                result.keptUnreadable.append(snapshot.row(detail: "run.json became unreadable"))
                return
            }
            let alive = ProcessOwnership.readOwnerIdentity(in: snapshot.directory)
                .map(ProcessOwnership.isIdentityAlive) ?? false
            guard !alive else { result.keptAlive.append(snapshot.row); return }
            guard run.status.isTerminal else { result.keptNonTerminal.append(snapshot.row); return }
            guard run.threadId == nil, !threadRunIds.contains(run.id) else {
                result.keptThreadReferenced.append(snapshot.row)
                return
            }
            remove(snapshot, into: &result)
        }
    }

    private func pruneRelay(_ snapshot: Snapshot, into result: inout MutableResult) {
        ProcessOwnership.withRunLock(in: snapshot.directory) {
            guard let data = try? Data(contentsOf: snapshot.directory.appendingPathComponent("relay.json")),
                  let relay = try? CoreJSON.decode(LoopState.self, from: data) else {
                result.keptUnreadable.append(snapshot.row(detail: "relay.json became unreadable"))
                return
            }
            let identity = ProcessOwnership.readTurnOwner(in: snapshot.directory)
                ?? relay.rounds.last?.devTurnOwner.flatMap(ProcessOwnership.OwnerIdentity.fromRecord)
            guard identity.map(ProcessOwnership.isIdentityAlive) != true else {
                result.keptAlive.append(snapshot.row)
                return
            }
            guard relay.isGarbageCollectionTerminal else {
                result.keptNonTerminal.append(snapshot.row)
                return
            }
            remove(snapshot, into: &result)
        }
    }

    private func remove(_ snapshot: Snapshot, into result: inout MutableResult) {
        if dryRun {
            // Passed every guard (incl. the under-lock re-check) — record what WOULD be pruned.
            result.pruned.append(snapshot.row)
            return
        }
        do {
            try FileManager.default.removeItem(at: snapshot.directory)
            result.pruned.append(snapshot.row)
        } catch {
            result.keptRemovalFailed.append(snapshot.row(detail: error.localizedDescription))
        }
    }

    private struct Snapshot: Sendable {
        var id: String
        var directory: URL
        var createdAt: Date
        var status: String
        var kind: String
        var terminal: Bool
        var identityAlive: Bool
        var threadLinked: Bool

        var row: OwnershipGarbageCollectionRecordJSON {
            row(detail: nil)
        }

        func row(detail: String?) -> OwnershipGarbageCollectionRecordJSON {
            .init(id: id, kind: kind, createdAt: createdAt, status: status, detail: detail)
        }
    }

    private func referencedRunIds() -> Set<String> {
        Set(threadStore.list().flatMap { thread in
            thread.turns.flatMap { turn in
                var ids = turn.artifactRefs.compactMap(\.runId)
                if let runId = turn.runId { ids.append(runId) }
                return ids
            }
        })
    }

    private struct MutableResult {
        var retentionCount: Int
        var pruned: [OwnershipGarbageCollectionRecordJSON] = []
        var keptAlive: [OwnershipGarbageCollectionRecordJSON] = []
        var keptNonTerminal: [OwnershipGarbageCollectionRecordJSON] = []
        var keptWithinRetention: [OwnershipGarbageCollectionRecordJSON] = []
        var keptThreadReferenced: [OwnershipGarbageCollectionRecordJSON] = []
        var keptUnreadable: [OwnershipGarbageCollectionRecordJSON] = []
        var keptRemovalFailed: [OwnershipGarbageCollectionRecordJSON] = []

        var json: OwnershipGarbageCollectionJSON {
            .init(
                retentionCount: retentionCount,
                pruned: pruned.sorted(by: Self.sortRows),
                keptAlive: keptAlive.sorted(by: Self.sortRows),
                keptNonTerminal: keptNonTerminal.sorted(by: Self.sortRows),
                keptWithinRetention: keptWithinRetention.sorted(by: Self.sortRows),
                keptThreadReferenced: keptThreadReferenced.sorted(by: Self.sortRows),
                keptUnreadable: keptUnreadable.sorted(by: Self.sortRows),
                keptRemovalFailed: keptRemovalFailed.sorted(by: Self.sortRows)
            )
        }

        private static func sortRows(
            _ lhs: OwnershipGarbageCollectionRecordJSON,
            _ rhs: OwnershipGarbageCollectionRecordJSON
        ) -> Bool {
            if lhs.kind != rhs.kind { return lhs.kind < rhs.kind }
            return lhs.id < rhs.id
        }
    }
}

private extension LoopState {
    /// Done and deliberate ceiling stops are terminal. Escalated/awaiting-PM and
    /// orphan-reconciled stops remain resumable and must survive GC.
    var isGarbageCollectionTerminal: Bool {
        switch status {
        case .done:
            return true
        case .stopped:
            return !isReconciledStopped
        case .running, .escalated, .awaitingPM:
            return false
        }
    }
}
