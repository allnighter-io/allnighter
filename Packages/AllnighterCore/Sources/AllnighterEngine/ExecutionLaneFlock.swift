import Foundation
import Darwin
import AllnighterCore

/// OS-level per-root execution-lane mutual exclusion (PO-S03b) with scoped
/// multi-holder metadata (PO-S06).
///
/// Layout under `AllnighterPaths.lanes` (honors `ALLNIGHTER_SUPPORT_DIR`):
/// ```
/// Lanes/<root-key-hash>/
///   lane.lock       # exclusive flock for build-lane holders (duration hold)
///   meta.lock       # brief exclusive flock for holders.json RMW (PO-S06)
///   holder.json     # multi-holder list (+ scopes); ticket mint source
///   waiters/        # timestamped waiter files for best-effort cross-process rank
/// ```
///
/// Build-lane claims hold `lane.lock` for the turn/proof duration (kernel releases
/// on process death). Docs-only scoped claims (`needsBuildLane: false`) only
/// register in `holder.json` under a brief `meta.lock` and may run concurrently
/// when write scopes are pairwise disjoint with live holders.
///
/// Within one process, a refcounted handle table lets multiple
/// `ExecutionLaneRegistry` instances share one OS build flock — nested re-entry
/// must not block on our own flock.
public enum ExecutionLaneFlock {
    public static let lockFileName = "lane.lock"
    public static let metaLockFileName = "meta.lock"
    public static let holderFileName = "holder.json"
    public static let waitersDirectoryName = "waiters"

    /// One holder's metadata in `holder.json` so a blocked process can mint the
    /// same `ExecutionLaneTicket` shape across process boundaries (PO-S03b/S06).
    public struct HolderMetadata: Codable, Sendable, Equatable {
        public var identity: ProcessOwnership.OwnerIdentity
        public var kind: String
        public var id: String
        public var acquiredAt: Date
        /// PO-S06: declared path prefixes (empty = full scope).
        public var writeScope: [String]
        /// PO-S06: whether this holder occupies the exclusive build flock slot.
        public var needsBuildLane: Bool

        public init(
            identity: ProcessOwnership.OwnerIdentity,
            kind: String,
            id: String,
            acquiredAt: Date,
            writeScope: [String] = [],
            needsBuildLane: Bool = true
        ) {
            self.identity = identity
            self.kind = kind
            self.id = id
            self.acquiredAt = acquiredAt
            self.writeScope = writeScope
            self.needsBuildLane = needsBuildLane
        }

        public init(claim: ExecutionLane.Claim, acquiredAt: Date) {
            self.identity = claim.identity
            self.kind = claim.kind
            self.id = claim.id
            self.acquiredAt = acquiredAt
            self.writeScope = claim.writeScope.pathPrefixes
            self.needsBuildLane = claim.writeScope.needsBuildLane
        }

        public var ticketHolder: ExecutionLaneTicket.Holder {
            ExecutionLaneTicket.Holder(
                identity: identity.asRecord(),
                kind: kind,
                id: id
            )
        }

        public var asTurnWriteScope: TurnWriteScope {
            TurnWriteScope(pathPrefixes: writeScope, needsBuildLane: needsBuildLane)
        }

        // Lenient decode: pre-S06 holder.json lacks writeScope/needsBuildLane.
        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            identity = try c.decode(ProcessOwnership.OwnerIdentity.self, forKey: .identity)
            kind = try c.decode(String.self, forKey: .kind)
            id = try c.decode(String.self, forKey: .id)
            acquiredAt = try c.decode(Date.self, forKey: .acquiredAt)
            writeScope = try c.decodeIfPresent([String].self, forKey: .writeScope) ?? []
            needsBuildLane = try c.decodeIfPresent(Bool.self, forKey: .needsBuildLane) ?? true
        }
    }

    /// On-disk multi-holder file (PO-S06). Also decodes the pre-S06 single-holder shape.
    public struct HoldersFile: Codable, Sendable, Equatable {
        public var holders: [HolderMetadata]

        public init(holders: [HolderMetadata]) {
            self.holders = holders
        }

        public init(from decoder: Decoder) throws {
            // Multi-holder: { "holders": [ ... ] }
            if let multi = try? decoder.container(keyedBy: CodingKeys.self),
               multi.contains(.holders) {
                holders = try multi.decode([HolderMetadata].self, forKey: .holders)
                return
            }
            // Legacy single-holder object at top level.
            let single = try HolderMetadata(from: decoder)
            holders = [single]
        }

        private enum CodingKeys: String, CodingKey { case holders }
    }

    /// Process-local receipt for one refcount on the process-wide flock hold.
    /// Dropping the last receipt (or calling `release`) unlocks the OS flock.
    public final class Handle: @unchecked Sendable {
        public let laneKey: String
        private var released = false
        private let lock = NSLock()

        fileprivate init(laneKey: String) {
            self.laneKey = laneKey
        }

        deinit {
            release()
        }

        /// Drop this receipt. The process-wide table unlocks only when the last
        /// receipt for `laneKey` is released.
        public func release() {
            lock.lock()
            defer { lock.unlock() }
            guard !released else { return }
            released = true
            ProcessLaneFlockTable.shared.release(laneKey: laneKey)
        }

        /// Alias for call sites that previously unlocked a raw fd.
        public func unlockAndClose() {
            release()
        }
    }

    // MARK: - Paths

    /// Directory for one lane key: `…/Lanes/<sanitized-key>/`.
    public static func directory(forLaneKey key: String) -> URL {
        let safe = sanitizedDirectoryName(for: key)
        return AllnighterPaths.lanes.appendingPathComponent(safe, isDirectory: true)
    }

    public static func lockURL(forLaneKey key: String) -> URL {
        directory(forLaneKey: key).appendingPathComponent(lockFileName)
    }

    public static func holderURL(forLaneKey key: String) -> URL {
        directory(forLaneKey: key).appendingPathComponent(holderFileName)
    }

    public static func waitersDirectory(forLaneKey key: String) -> URL {
        directory(forLaneKey: key).appendingPathComponent(waitersDirectoryName, isDirectory: true)
    }

    /// PO-S04: **one persistent scratch per root** under the lane key directory.
    /// Path: `~/Library/Application Support/Allnighter/Lanes/<key>/scratch/`.
    /// Harness proofs inject `--scratch-path` for `swift` commands. Not per-attempt
    /// (spec non-goal): total turn kill + the lane provide isolation; the cache stays warm.
    public static func scratchDirectory(forLaneKey key: String) -> URL {
        directory(forLaneKey: key).appendingPathComponent("scratch", isDirectory: true)
    }

    /// Ensures the persistent scratch exists and returns its path.
    public static func ensuredScratchPath(forLaneKey key: String) -> String {
        let dir = scratchDirectory(forLaneKey: key)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.path
    }

    /// Scratch path for a project root (derives the same lane key as the execution lane).
    public static func ensuredScratchPath(repoRoot: String) -> String {
        ensuredScratchPath(forLaneKey: ExecutionLane.key(repoRoot: repoRoot))
    }

    /// Sanitize lane key (`v1:hex`) for a single path component.
    public static func sanitizedDirectoryName(for key: String) -> String {
        if key.hasPrefix("v1:"), key.count > 3 {
            return String(key.dropFirst(3))
        }
        return key
            .replacingOccurrences(of: ":", with: "_")
            .replacingOccurrences(of: "/", with: "_")
    }

    // MARK: - Acquire / release

    /// Non-blocking exclusive flock for this process (build-lane duration hold).
    /// If this process already holds the flock (another registry / nested path),
    /// returns another refcounted receipt without contending. Returns nil only
    /// when **another process** holds the lock.
    public static func tryAcquireExclusive(laneKey: String) -> Handle? {
        ProcessLaneFlockTable.shared.tryAcquire(laneKey: laneKey)
    }

    /// Brief exclusive meta lock for holders.json read-modify-write (PO-S06).
    /// Never held for a turn's duration — only while mutating the holder list.
    public static func withMetaLock<T>(laneKey: String, _ body: () throws -> T) rethrows -> T? {
        guard let handle = ProcessLaneFlockTable.shared.tryAcquireMeta(laneKey: laneKey) else {
            return nil
        }
        defer { handle.release() }
        return try body()
    }

    /// Blocking meta lock with short spin (docs-only registration under contention).
    public static func withMetaLockSpinning<T>(
        laneKey: String,
        timeout: TimeInterval = 2.0,
        _ body: () throws -> T
    ) rethrows -> T? {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if let result = try withMetaLock(laneKey: laneKey, body) {
                return result
            }
            usleep(5_000)
        }
        return nil
    }

    /// Replace the entire multi-holder list (caller should hold meta lock).
    public static func writeHolders(laneKey: String, holders: [HolderMetadata]) throws {
        let dir = directory(forLaneKey: laneKey)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try CoreJSON.encode(HoldersFile(holders: holders))
            .write(to: holderURL(forLaneKey: laneKey), options: .atomic)
    }

    /// Write a single holder as the sole entry (legacy call sites / exclusive grant).
    public static func writeHolder(laneKey: String, metadata: HolderMetadata) throws {
        try writeHolders(laneKey: laneKey, holders: [metadata])
    }

    public static func writeHolder(laneKey: String, claim: ExecutionLane.Claim, acquiredAt: Date) throws {
        try writeHolder(
            laneKey: laneKey,
            metadata: HolderMetadata(claim: claim, acquiredAt: acquiredAt)
        )
    }

    /// All live holders from disk (multi-holder file, or legacy single object).
    public static func readHolders(laneKey: String) -> [HolderMetadata] {
        let url = holderURL(forLaneKey: laneKey)
        guard let data = try? Data(contentsOf: url) else { return [] }
        if let file = try? CoreJSON.decode(HoldersFile.self, from: data) {
            return file.holders
        }
        if let single = try? CoreJSON.decode(HolderMetadata.self, from: data) {
            return [single]
        }
        return []
    }

    /// First / primary holder (ticket mint default). Prefer build-lane holder when present.
    public static func readHolder(laneKey: String) -> HolderMetadata? {
        let all = readHolders(laneKey: laneKey)
        if let build = all.first(where: \.needsBuildLane) { return build }
        return all.first
    }

    /// Drop all holder metadata when this process no longer holds the build flock
    /// and is not coordinating docs-only holders. Prefer `removeHolder` for scoped release.
    public static func clearHolder(laneKey: String) {
        // Only clear when this process no longer holds the flock — otherwise a
        // nested release would erase the outer holder's ticket metadata.
        guard !ProcessLaneFlockTable.shared.isHeldLocally(laneKey: laneKey) else { return }
        try? FileManager.default.removeItem(at: holderURL(forLaneKey: laneKey))
    }

    /// Remove one holder by id under meta lock (PO-S06 multi-holder release).
    public static func removeHolder(laneKey: String, id: String) {
        _ = withMetaLockSpinning(laneKey: laneKey) { () -> Bool in
            var holders = readHolders(laneKey: laneKey).filter { $0.id != id }
            // Drop identity-dead strays, but keep build holders whose flock is still
            // held by another process (kernel truth — do not wipe foreign metadata).
            holders = holders.filter { isHolderEffectivelyLive($0, laneKey: laneKey) }
            if holders.isEmpty {
                try? FileManager.default.removeItem(at: holderURL(forLaneKey: laneKey))
            } else {
                try? writeHolders(laneKey: laneKey, holders: holders)
            }
            return true
        }
    }

    /// Append or replace a holder under meta lock. Returns false if meta lock timed out.
    @discardableResult
    public static func upsertHolder(laneKey: String, metadata: HolderMetadata) -> Bool {
        withMetaLockSpinning(laneKey: laneKey) { () -> Bool in
            var holders = readHolders(laneKey: laneKey)
                .filter { isHolderEffectivelyLive($0, laneKey: laneKey) }
            holders.removeAll { $0.id == metadata.id }
            holders.append(metadata)
            try? writeHolders(laneKey: laneKey, holders: holders)
            return true
        } == true
    }

    /// True when another process holds the exclusive **build** flock (or when we hold it).
    public static func isLocked(laneKey: String) -> Bool {
        if ProcessLaneFlockTable.shared.isHeldLocally(laneKey: laneKey) {
            return true
        }
        // Probe: try acquire; if we get it, we were free — release immediately.
        if let handle = tryAcquireExclusive(laneKey: laneKey) {
            handle.release()
            return false
        }
        return true
    }

    public static func isHeldLocally(laneKey: String) -> Bool {
        ProcessLaneFlockTable.shared.isHeldLocally(laneKey: laneKey)
    }

    /// Whether an on-disk holder should participate in conflict / ticket minting.
    /// Identity-alive holders always count. A build-lane holder whose exclusive
    /// flock is still held by **another** process also counts (kernel truth
    /// outranks a torn startTimeTicks in holder.json — PO-S03b/S06).
    public static func isHolderEffectivelyLive(_ meta: HolderMetadata, laneKey: String) -> Bool {
        if ProcessOwnership.isIdentityAlive(meta.identity) { return true }
        if meta.needsBuildLane && isLocked(laneKey: laneKey) && !isHeldLocally(laneKey: laneKey) {
            return true
        }
        return false
    }

    /// Live on-disk holders that conflict with `claim` (scope overlap or dual build).
    /// Same-process holders are never foreign conflicts: nested registry instances
    /// in one process share the OS flock via refcount (PO-S03b). Same-process
    /// multi-holder / exclusive policy is owned by `ExecutionLaneRegistry`.
    public static func conflictingHolders(
        laneKey: String,
        claim: ExecutionLane.Claim
    ) -> [HolderMetadata] {
        let scope = claim.writeScope
        return readHolders(laneKey: laneKey).filter { meta in
            guard isHolderEffectivelyLive(meta, laneKey: laneKey) else { return false }
            if identitiesMatch(meta.identity, claim.identity) { return false }
            return TurnWriteScope.conflicts(meta.asTurnWriteScope, scope)
        }
    }

    // MARK: - Tickets from on-disk holder

    /// Mint a ticket from holder.json + waiter ranking. `position` is 1-based.
    /// When `forClaim` is set, only a **conflicting** live holder mints a ticket
    /// (disjoint-scope docs-only holders do not block; same-process disk holders
    /// never mint a foreign ticket — nested re-entry uses flock refcount).
    public static func ticketIfBusy(
        laneKey: String,
        position: Int,
        now: Date = Date(),
        forClaim: ExecutionLane.Claim? = nil
    ) -> ExecutionLaneTicket? {
        let holders = readHolders(laneKey: laneKey).filter {
            isHolderEffectivelyLive($0, laneKey: laneKey)
        }
        let meta: HolderMetadata?
        if let forClaim {
            meta = holders.first {
                // Same process is not a foreign conflict (PO-S03b nested refcount).
                if identitiesMatch($0.identity, forClaim.identity) { return false }
                return TurnWriteScope.conflicts($0.asTurnWriteScope, forClaim.writeScope)
            }
            // No conflicting holder: not busy for this claim (even if others hold).
            if meta == nil {
                // Build flock held by a dead process with torn metadata — still busy.
                if forClaim.writeScope.needsBuildLane && isLocked(laneKey: laneKey)
                    && !isHeldLocally(laneKey: laneKey)
                    && holders.isEmpty
                {
                    return unknownTicket(position: position)
                }
                return nil
            }
        } else {
            meta = holders.first(where: \.needsBuildLane) ?? holders.first
            if meta == nil {
                if isLocked(laneKey: laneKey) {
                    return unknownTicket(position: position)
                }
                return nil
            }
        }
        guard let meta else { return nil }
        let heldSince = max(0, now.timeIntervalSince(meta.acquiredAt))
        return ExecutionLaneTicket(
            position: max(1, position),
            holder: meta.ticketHolder,
            heldSinceSeconds: heldSince
        )
    }

    /// Identity match used for same-process nested re-entry (pid + startTimeTicks).
    private static func identitiesMatch(
        _ a: ProcessOwnership.OwnerIdentity,
        _ b: ProcessOwnership.OwnerIdentity
    ) -> Bool {
        a.pid == b.pid && a.startTimeTicks == b.startTimeTicks
    }

    private static func unknownTicket(position: Int) -> ExecutionLaneTicket {
        ExecutionLaneTicket(
            position: max(1, position),
            holder: ExecutionLaneTicket.Holder(
                identity: ProcessOwnerRecord(
                    pid: 0, pgid: nil, startTimeTicks: 0, kind: "unknown"
                ),
                kind: "unknown",
                id: "unknown"
            ),
            heldSinceSeconds: 0
        )
    }

    // MARK: - Cross-process waiters

    /// Register a timestamped waiter file. Returns the file URL (clean on acquire/abandon).
    @discardableResult
    public static func registerWaiter(
        laneKey: String,
        claim: ExecutionLane.Claim,
        enqueuedAt: Date = Date()
    ) -> URL? {
        let dir = waitersDirectory(forLaneKey: laneKey)
        do {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        } catch {
            return nil
        }
        let nanos = Int64(enqueuedAt.timeIntervalSince1970 * 1_000_000_000)
        let name = String(format: "%020lld_", nanos) + UUID().uuidString + ".json"
        let url = dir.appendingPathComponent(name)
        struct WaiterFile: Codable {
            var id: String
            var kind: String
            var enqueuedAt: Date
        }
        let body = WaiterFile(id: claim.id, kind: claim.kind, enqueuedAt: enqueuedAt)
        guard let data = try? CoreJSON.encode(body) else { return nil }
        do {
            try data.write(to: url, options: .atomic)
            return url
        } catch {
            return nil
        }
    }

    public static func unregisterWaiter(_ url: URL?) {
        guard let url else { return }
        try? FileManager.default.removeItem(at: url)
    }

    /// 1-based rank of `waiterURL` among waiter files sorted by filename (timestamp).
    public static func waiterPosition(laneKey: String, waiterURL: URL) -> Int {
        let names = waiterFileNames(laneKey: laneKey)
        guard let idx = names.firstIndex(of: waiterURL.lastPathComponent) else {
            return max(1, names.count)
        }
        return idx + 1
    }

    /// Count of registered waiter files (best-effort; stale files possible).
    public static func waiterCount(laneKey: String) -> Int {
        waiterFileNames(laneKey: laneKey).count
    }

    /// Would-be position for a non-enqueued try (existing waiters + 1).
    public static func wouldBePosition(laneKey: String) -> Int {
        waiterCount(laneKey: laneKey) + 1
    }

    private static func waiterFileNames(laneKey: String) -> [String] {
        let dir = waitersDirectory(forLaneKey: laneKey)
        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: dir,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }
        return contents
            .map(\.lastPathComponent)
            .filter { $0.hasSuffix(".json") }
            .sorted()
    }
}

// MARK: - Process-wide flock table

/// One OS flock per lane key per process, refcounted across registry instances.
/// Kernel still releases the underlying fd on process death.
/// Separate `meta.lock` entries use keys prefixed with `meta:` so brief metadata
/// RMW never contends with a duration-held build flock (PO-S06).
fileprivate final class ProcessLaneFlockTable: @unchecked Sendable {
    static let shared = ProcessLaneFlockTable()

    private struct Entry {
        var fd: Int32
        var refCount: Int
    }

    private let lock = NSLock()
    private var entries: [String: Entry] = [:]

    private init() {}

    func isHeldLocally(laneKey: String) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return (entries[laneKey]?.refCount ?? 0) > 0
    }

    func tryAcquire(laneKey: String) -> ExecutionLaneFlock.Handle? {
        tryAcquireFile(tableKey: laneKey, fileURL: ExecutionLaneFlock.lockURL(forLaneKey: laneKey), laneKey: laneKey)
    }

    /// Brief exclusive hold on `meta.lock` (not the build `lane.lock`).
    func tryAcquireMeta(laneKey: String) -> ExecutionLaneFlock.Handle? {
        let tableKey = "meta:" + laneKey
        let url = ExecutionLaneFlock.directory(forLaneKey: laneKey)
            .appendingPathComponent(ExecutionLaneFlock.metaLockFileName)
        return tryAcquireFile(tableKey: tableKey, fileURL: url, laneKey: tableKey)
    }

    private func tryAcquireFile(
        tableKey: String,
        fileURL: URL,
        laneKey handleKey: String
    ) -> ExecutionLaneFlock.Handle? {
        lock.lock()
        defer { lock.unlock() }

        if var existing = entries[tableKey], existing.refCount > 0 {
            existing.refCount += 1
            entries[tableKey] = existing
            return ExecutionLaneFlock.Handle(laneKey: handleKey)
        }

        let dir = fileURL.deletingLastPathComponent()
        do {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        } catch {
            return nil
        }
        let path = fileURL.path
        let fd = open(path, O_CREAT | O_RDWR, 0o600)
        guard fd >= 0 else { return nil }
        if flock(fd, LOCK_EX | LOCK_NB) != 0 {
            close(fd)
            return nil
        }
        entries[tableKey] = Entry(fd: fd, refCount: 1)
        return ExecutionLaneFlock.Handle(laneKey: handleKey)
    }

    func release(laneKey: String) {
        lock.lock()
        defer { lock.unlock() }
        guard var entry = entries[laneKey] else { return }
        entry.refCount -= 1
        if entry.refCount > 0 {
            entries[laneKey] = entry
            return
        }
        entries.removeValue(forKey: laneKey)
        _ = flock(entry.fd, LOCK_UN)
        close(entry.fd)
    }
}
