import Foundation
import Darwin
import AllnighterCore

/// OS-level per-root execution-lane mutual exclusion (PO-S03b).
///
/// Layout under `AllnighterPaths.lanes` (honors `ALLNIGHTER_SUPPORT_DIR`):
/// ```
/// Lanes/<root-key-hash>/
///   lane.lock       # flock(LOCK_EX) target; kernel releases on process death
///   holder.json     # identity/kind/id/acquiredAt written under the flock
///   waiters/        # timestamped waiter files for best-effort cross-process rank
/// ```
///
/// The flock is the mutual-exclusion mechanism **across processes**. Within one
/// process, a refcounted handle table lets multiple `ExecutionLaneRegistry`
/// instances (relay `.shared` + RunService inject) share one OS hold — nested
/// re-entry must not block on our own flock.
///
/// Identity-based release in the in-process actor is metadata/local-handoff
/// cleanup only; dead holders free the flock via the kernel.
public enum ExecutionLaneFlock {
    public static let lockFileName = "lane.lock"
    public static let holderFileName = "holder.json"
    public static let waitersDirectoryName = "waiters"

    /// Holder metadata written next to the lock so a blocked process can mint
    /// the same `ExecutionLaneTicket` shape across process boundaries.
    public struct HolderMetadata: Codable, Sendable, Equatable {
        public var identity: ProcessOwnership.OwnerIdentity
        public var kind: String
        public var id: String
        public var acquiredAt: Date

        public init(
            identity: ProcessOwnership.OwnerIdentity,
            kind: String,
            id: String,
            acquiredAt: Date
        ) {
            self.identity = identity
            self.kind = kind
            self.id = id
            self.acquiredAt = acquiredAt
        }

        public init(claim: ExecutionLane.Claim, acquiredAt: Date) {
            self.identity = claim.identity
            self.kind = claim.kind
            self.id = claim.id
            self.acquiredAt = acquiredAt
        }

        public var ticketHolder: ExecutionLaneTicket.Holder {
            ExecutionLaneTicket.Holder(
                identity: identity.asRecord(),
                kind: kind,
                id: id
            )
        }
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

    /// Non-blocking exclusive flock for this process. If this process already
    /// holds the flock (another registry / nested path), returns another
    /// refcounted receipt without contending. Returns nil only when **another
    /// process** holds the lock.
    public static func tryAcquireExclusive(laneKey: String) -> Handle? {
        ProcessLaneFlockTable.shared.tryAcquire(laneKey: laneKey)
    }

    /// Write holder metadata. Caller must hold a receipt for `laneKey`.
    public static func writeHolder(laneKey: String, metadata: HolderMetadata) throws {
        let dir = directory(forLaneKey: laneKey)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try CoreJSON.encode(metadata).write(to: holderURL(forLaneKey: laneKey), options: .atomic)
    }

    public static func writeHolder(laneKey: String, claim: ExecutionLane.Claim, acquiredAt: Date) throws {
        try writeHolder(
            laneKey: laneKey,
            metadata: HolderMetadata(claim: claim, acquiredAt: acquiredAt)
        )
    }

    public static func readHolder(laneKey: String) -> HolderMetadata? {
        let url = holderURL(forLaneKey: laneKey)
        guard let data = try? Data(contentsOf: url),
              let meta = try? CoreJSON.decode(HolderMetadata.self, from: data) else {
            return nil
        }
        return meta
    }

    /// Drop holder metadata (cleanup path; flock unlock is via Handle release).
    public static func clearHolder(laneKey: String) {
        // Only clear when this process no longer holds the flock — otherwise a
        // nested release would erase the outer holder's ticket metadata.
        guard !ProcessLaneFlockTable.shared.isHeldLocally(laneKey: laneKey) else { return }
        try? FileManager.default.removeItem(at: holderURL(forLaneKey: laneKey))
    }

    /// True when another process holds the exclusive flock (or when we hold it).
    /// Prefer `isHeldLocally` for same-process queries.
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

    // MARK: - Tickets from on-disk holder

    /// Mint a ticket from holder.json + waiter ranking. `position` is 1-based.
    public static func ticketIfBusy(
        laneKey: String,
        position: Int,
        now: Date = Date()
    ) -> ExecutionLaneTicket? {
        guard let meta = readHolder(laneKey: laneKey) else {
            if isLocked(laneKey: laneKey) {
                return ExecutionLaneTicket(
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
            return nil
        }
        let heldSince = max(0, now.timeIntervalSince(meta.acquiredAt))
        return ExecutionLaneTicket(
            position: max(1, position),
            holder: meta.ticketHolder,
            heldSinceSeconds: heldSince
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
        lock.lock()
        defer { lock.unlock() }

        if var existing = entries[laneKey], existing.refCount > 0 {
            existing.refCount += 1
            entries[laneKey] = existing
            return ExecutionLaneFlock.Handle(laneKey: laneKey)
        }

        let dir = ExecutionLaneFlock.directory(forLaneKey: laneKey)
        do {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        } catch {
            return nil
        }
        let path = ExecutionLaneFlock.lockURL(forLaneKey: laneKey).path
        let fd = open(path, O_CREAT | O_RDWR, 0o600)
        guard fd >= 0 else { return nil }
        if flock(fd, LOCK_EX | LOCK_NB) != 0 {
            close(fd)
            return nil
        }
        entries[laneKey] = Entry(fd: fd, refCount: 1)
        return ExecutionLaneFlock.Handle(laneKey: laneKey)
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
