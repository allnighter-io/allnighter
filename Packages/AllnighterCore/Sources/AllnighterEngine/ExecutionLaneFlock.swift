import Foundation
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif
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
/// must not block on our own flock. Meta RMW also takes a per-lane in-process
/// recursive mutex so same-process threads cannot lost-update `holder.json`
/// (PO-F9); the flock still serializes cross-process writers.
public enum ExecutionLaneFlock {
    public static let lockFileName = "lane.lock"
    public static let metaLockFileName = "meta.lock"
    public static let holderFileName = "holder.json"
    public static let waitersDirectoryName = "waiters"

    /// Distinct outcomes for an exclusive flock attempt (PO-F9): contention vs
    /// open/flock hard failures (EMFILE, ENOLCK, unsupported FS, …).
    public enum AcquireOutcome: Sendable, Equatable {
        case acquired
        case busy
        case unavailable(errno: Int32)
    }

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
    /// PO-F9: `v1:abc` must not collide with a raw key `abc` — non-`v1:` keys get an
    /// escape-proof `k_` prefix so they never equal a stripped hex component.
    public static func sanitizedDirectoryName(for key: String) -> String {
        if key.hasPrefix("v1:"), key.count > 3 {
            return String(key.dropFirst(3))
        }
        return "k_" + key
            .replacingOccurrences(of: ":", with: "_")
            .replacingOccurrences(of: "/", with: "_")
    }

    /// Reconstruct the lane key that would produce `directoryName` via
    /// `sanitizedDirectoryName`, or nil when the name is not round-trippable.
    public static func laneKey(fromDirectoryName directoryName: String) -> String? {
        if directoryName.hasPrefix("k_") {
            // Non-v1 keys are escape-sanitized irreversibly; only accept when the
            // sanitized form of the reconstructed candidate matches (rare in practice).
            return nil
        }
        let key = "v1:" + directoryName
        guard sanitizedDirectoryName(for: key) == directoryName else { return nil }
        return key
    }

    /// PO-F10: remove `Lanes/<key>` dirs whose holders are ALL identity-dead and
    /// whose `lane.lock` flock is unheld. Never removes a live or held lane.
    /// Called opportunistically from a fresh run start and `alln doctor`.
    /// Returns the directory names that were removed.
    @discardableResult
    public static func garbageCollectStaleLanes(
        lanesRoot: URL = AllnighterPaths.lanes
    ) -> [String] {
        let fm = FileManager.default
        guard let names = try? fm.contentsOfDirectory(atPath: lanesRoot.path) else {
            return []
        }
        var removed: [String] = []
        for name in names {
            let dir = lanesRoot.appendingPathComponent(name, isDirectory: true)
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: dir.path, isDirectory: &isDir), isDir.boolValue else {
                continue
            }
            guard let key = laneKey(fromDirectoryName: name) else { continue }
            let holders = readHolders(laneKey: key)
            let anyIdentityLive = holders.contains {
                ProcessOwnership.isIdentityAlive($0.identity)
            }
            if anyIdentityLive { continue }
            // A live hold by THIS process → keep (we're using it).
            if isHeldLocally(laneKey: key) { continue }
            // SR-5 (Sol F1): acquire and HOLD the exclusive flock across the delete so no
            // other-process acquirer can be mid-flock on the inode we remove. A `nil` means
            // another process holds it → skip. Re-read holders under the flock before
            // unlinking; the acquirer-side st_nlink guard closes the residual window.
            guard let handle = tryAcquireExclusive(laneKey: key) else { continue }
            let stillDead = readHolders(laneKey: key).allSatisfy {
                !ProcessOwnership.isIdentityAlive($0.identity)
            }
            guard stillDead else { handle.release(); continue }
            do {
                try fm.removeItem(at: dir)
                removed.append(name)
            } catch {
                // Best-effort; leave the dir for a later pass.
            }
            handle.release()
        }
        return removed
    }

    // MARK: - Acquire / release

    /// Non-blocking exclusive flock for this process (build-lane duration hold).
    /// If this process already holds the flock (another registry / nested path),
    /// returns another refcounted receipt without contending. Returns nil only
    /// when **another process** holds the lock (after a few busy retries — PO-F9
    /// `#9` so a racing `isLocked` probe does not permanently starve an acquirer).
    /// Hard open/flock failures are not treated as contention.
    public static func tryAcquireExclusive(laneKey: String) -> Handle? {
        tryAcquireExclusiveOrError(laneKey: laneKey).1
    }

    /// Retrying acquire that preserves the errno distinction (SR-4 / Sol F14). Same brief
    /// busy-retry as `tryAcquireExclusive` (`isLocked` may steal the flock for a microsecond),
    /// but returns `.unavailable(errno)` for a hard open/flock failure (EMFILE, ENOLCK,
    /// unsupported FS) instead of collapsing it into a `nil` that reads as contention — so
    /// the caller can fail fast rather than wait out the full lane timeout.
    public static func tryAcquireExclusiveOrError(laneKey: String) -> (AcquireOutcome, Handle?) {
        for attempt in 0..<5 {
            switch ProcessLaneFlockTable.shared.tryAcquireDetailed(laneKey: laneKey) {
            case .acquired(let handle):
                return (.acquired, handle)
            case .busy:
                if attempt < 4 { usleep(1_000) }
            case .unavailable(let code):
                return (.unavailable(errno: code), nil)
            }
        }
        return (.busy, nil)
    }

    /// Detailed acquire for tests / callers that must distinguish errno failures
    /// from contention (PO-F9 `#5`).
    public static func tryAcquireExclusiveDetailed(laneKey: String) -> (AcquireOutcome, Handle?) {
        switch ProcessLaneFlockTable.shared.tryAcquireDetailed(laneKey: laneKey) {
        case .acquired(let handle):
            return (.acquired, handle)
        case .busy:
            return (.busy, nil)
        case .unavailable(let code):
            return (.unavailable(errno: code), nil)
        }
    }

    /// Brief exclusive meta lock for holders.json read-modify-write (PO-S06).
    /// Never held for a turn's duration — only while mutating the holder list.
    /// Per-lane in-process recursive mutex serializes same-process threads; the
    /// `meta.lock` flock still serializes cross-process writers (PO-F9 `#2`).
    public static func withMetaLock<T>(laneKey: String, _ body: () throws -> T) rethrows -> T? {
        let mutex = MetaLockMutexTable.shared.mutex(for: laneKey)
        mutex.lock()
        defer { mutex.unlock() }
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
    static func writeHolders(laneKey: String, holders: [HolderMetadata]) throws {
        let dir = directory(forLaneKey: laneKey)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try CoreJSON.encode(HoldersFile(holders: holders))
            .write(to: holderURL(forLaneKey: laneKey), options: .atomic)
    }

    /// Write a single holder as the sole entry (legacy call sites / exclusive grant).
    static func writeHolder(laneKey: String, metadata: HolderMetadata) throws {
        try writeHolders(laneKey: laneKey, holders: [metadata])
    }

    static func writeHolder(laneKey: String, claim: ExecutionLane.Claim, acquiredAt: Date) throws {
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

    /// Drop this process's holder metadata when we no longer hold the build flock.
    /// Takes meta lock, re-reads, removes only this process's identities, deletes
    /// the file only when empty (PO-F9 `#3` — never wipe foreign docs-only holders).
    public static func clearHolder(laneKey: String) {
        // Only clear when this process no longer holds the flock — otherwise a
        // nested release would erase the outer holder's ticket metadata.
        guard !ProcessLaneFlockTable.shared.isHeldLocally(laneKey: laneKey) else { return }
        guard let me = ProcessOwnership.OwnerIdentity.current(kind: .inProcess) else { return }
        _ = withMetaLockSpinning(laneKey: laneKey) { () -> Bool in
            var holders = readHolders(laneKey: laneKey)
            holders.removeAll { identitiesMatch($0.identity, me) }
            if holders.isEmpty {
                try? FileManager.default.removeItem(at: holderURL(forLaneKey: laneKey))
            } else {
                do {
                    try writeHolders(laneKey: laneKey, holders: holders)
                } catch {
                    return false
                }
            }
            return true
        }
    }

    /// Remove one holder by id **and** identity under meta lock (PO-F9 `#10`).
    public static func removeHolder(
        laneKey: String,
        id: String,
        identity: ProcessOwnership.OwnerIdentity
    ) {
        _ = withMetaLockSpinning(laneKey: laneKey) { () -> Bool in
            var holders = readHolders(laneKey: laneKey).filter {
                !($0.id == id && identitiesMatch($0.identity, identity))
            }
            // Drop identity-dead strays, but keep build holders whose flock is still
            // held by another process (kernel truth — do not wipe foreign metadata).
            holders = holders.filter { isHolderEffectivelyLive($0, laneKey: laneKey) }
            if holders.isEmpty {
                try? FileManager.default.removeItem(at: holderURL(forLaneKey: laneKey))
            } else {
                do {
                    try writeHolders(laneKey: laneKey, holders: holders)
                } catch {
                    return false
                }
            }
            return true
        }
    }

    /// Convenience: remove by id for this process's live identity, or any
    /// identity-dead entry with that id (reconcile without an explicit identity).
    public static func removeHolder(laneKey: String, id: String) {
        _ = withMetaLockSpinning(laneKey: laneKey) { () -> Bool in
            let me = ProcessOwnership.OwnerIdentity.current(kind: .inProcess)
            var holders = readHolders(laneKey: laneKey).filter { meta in
                guard meta.id == id else { return true }
                if let me, identitiesMatch(meta.identity, me) { return false }
                // Reconcile: drop identity-dead entries that are not flock-kept.
                if !isHolderEffectivelyLive(meta, laneKey: laneKey) { return false }
                // Live foreign holder with the same id — keep (PO-F9 `#10`).
                return true
            }
            holders = holders.filter { isHolderEffectivelyLive($0, laneKey: laneKey) }
            if holders.isEmpty {
                try? FileManager.default.removeItem(at: holderURL(forLaneKey: laneKey))
            } else {
                do {
                    try writeHolders(laneKey: laneKey, holders: holders)
                } catch {
                    return false
                }
            }
            return true
        }
    }

    /// Append or replace a holder under meta lock. Returns false if meta lock
    /// timed out **or** the disk write failed (PO-F9 `#4`).
    @discardableResult
    public static func upsertHolder(laneKey: String, metadata: HolderMetadata) -> Bool {
        withMetaLockSpinning(laneKey: laneKey) { () -> Bool in
            var holders = readHolders(laneKey: laneKey)
                .filter { isHolderEffectivelyLive($0, laneKey: laneKey) }
            holders.removeAll {
                $0.id == metadata.id && identitiesMatch($0.identity, metadata.identity)
            }
            holders.append(metadata)
            do {
                try writeHolders(laneKey: laneKey, holders: holders)
                return true
            } catch {
                return false
            }
        } == true
    }

    /// Atomically admit a docs-only holder only if no live holder currently conflicts with
    /// its write scope — the read→conflict-check→append all happen under one `meta.lock`
    /// hold. Closes the SR-6 (Sol F2) TOCTOU where two overlapping docs-only claims each
    /// observe "no conflict" before either appends. Returns false on conflict OR meta-lock
    /// timeout OR write failure (caller mints a busy ticket either way).
    @discardableResult
    public static func admitHolderIfClear(
        laneKey: String,
        claim: ExecutionLane.Claim,
        metadata: HolderMetadata
    ) -> Bool {
        withMetaLockSpinning(laneKey: laneKey) { () -> Bool in
            var holders = readHolders(laneKey: laneKey)
                .filter { isHolderEffectivelyLive($0, laneKey: laneKey) }
            let conflict = holders.contains { meta in
                if identitiesMatch(meta.identity, claim.identity) { return false }
                return TurnWriteScope.conflicts(meta.asTurnWriteScope, claim.writeScope)
            }
            if conflict { return false }
            holders.removeAll {
                $0.id == metadata.id && identitiesMatch($0.identity, metadata.identity)
            }
            holders.append(metadata)
            do {
                try writeHolders(laneKey: laneKey, holders: holders)
                return true
            } catch {
                return false
            }
        } == true
    }

    /// True when another process holds the exclusive **build** flock (or when we hold it).
    public static func isLocked(laneKey: String) -> Bool {
        if ProcessLaneFlockTable.shared.isHeldLocally(laneKey: laneKey) {
            return true
        }
        // Probe: try acquire; if we get it, we were free — release immediately.
        // Real acquirers retry on busy (see `tryAcquireExclusive`) so this
        // microsecond steal does not permanently starve them (PO-F9 `#9`).
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
    ///
    /// PO-F9 `#6`: when the exclusive flock is foreign-held but no conflicting
    /// holder is visible (torn/missing `holder.json`), conservatively treat an
    /// overlapping claim as conflicting with a presumed full-build foreign holder.
    public static func conflictingHolders(
        laneKey: String,
        claim: ExecutionLane.Claim
    ) -> [HolderMetadata] {
        let scope = claim.writeScope
        let visible = readHolders(laneKey: laneKey).filter { meta in
            guard isHolderEffectivelyLive(meta, laneKey: laneKey) else { return false }
            if identitiesMatch(meta.identity, claim.identity) { return false }
            return TurnWriteScope.conflicts(meta.asTurnWriteScope, scope)
        }
        if !visible.isEmpty { return visible }
        // Foreign flock + no visible conflict → if no build holder is registered
        // either, presume a full-build foreign holder (TOCTOU / torn metadata).
        // Do NOT fire when a visible non-conflicting build holder exists (S06).
        if isLocked(laneKey: laneKey) && !isHeldLocally(laneKey: laneKey) {
            let live = readHolders(laneKey: laneKey).filter {
                isHolderEffectivelyLive($0, laneKey: laneKey)
            }
            let visibleBuild = live.contains(where: \.needsBuildLane)
            if !visibleBuild && TurnWriteScope.conflicts(scope, .legacyFullBuild) {
                return [
                    HolderMetadata(
                        identity: ProcessOwnership.OwnerIdentity(
                            pid: 0, pgid: nil, startTimeTicks: 0, kind: .inProcess
                        ),
                        kind: "unknown",
                        id: "unknown",
                        acquiredAt: Date(timeIntervalSince1970: 0),
                        writeScope: [],
                        needsBuildLane: true
                    )
                ]
            }
        }
        return []
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
            // No conflicting holder: still busy when a foreign exclusive flock is held
            // for a build claim (PO-F9 `#8` — drop `holders.isEmpty`). Docs-only stays
            // admitted when a visible non-conflicting build holder exists (S06 disjoint
            // scopes); only torn/missing build metadata trips the `#6` TOCTOU guard.
            if meta == nil {
                if isLocked(laneKey: laneKey) && !isHeldLocally(laneKey: laneKey) {
                    if forClaim.writeScope.needsBuildLane {
                        return unknownTicket(position: position)
                    }
                    let visibleBuild = holders.contains(where: \.needsBuildLane)
                    if !visibleBuild
                        && TurnWriteScope.conflicts(forClaim.writeScope, .legacyFullBuild)
                    {
                        return unknownTicket(position: position)
                    }
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

    /// On-disk waiter record. Embeds owner identity so crashed waiters can be
    /// filtered out and do not inflate FIFO positions (PO-F9 `#7`).
    struct WaiterFile: Codable, Equatable {
        var id: String
        var kind: String
        var enqueuedAt: Date
        var identity: ProcessOwnership.OwnerIdentity?
    }

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
        let body = WaiterFile(
            id: claim.id,
            kind: claim.kind,
            enqueuedAt: enqueuedAt,
            identity: claim.identity
        )
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

    /// RLR-S02c: withdraw a specific run's FIFO waiter from **any** process by its
    /// canonical claim id. The killer of a blocked run lives in a *different*
    /// process than the parked waiter and cannot reach its in-memory continuation;
    /// it removes the on-disk waiter file(s) whose `id` matches the cancelled/killed
    /// run so the remaining waiters' positions collapse immediately, even though the
    /// owning process only self-abandons its parked wait on its next reconcile tick.
    /// Additive over the existing `WaiterFile` schema (no format change). Returns the
    /// number of waiter files removed.
    @discardableResult
    public static func withdrawWaiter(laneKey: String, claimId: String) -> Int {
        let dir = waitersDirectory(forLaneKey: laneKey)
        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: dir, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]
        ) else { return 0 }
        var removed = 0
        for url in contents where url.pathExtension == "json" {
            guard let data = try? Data(contentsOf: url),
                  let waiter = try? CoreJSON.decode(WaiterFile.self, from: data),
                  waiter.id == claimId else { continue }
            if (try? FileManager.default.removeItem(at: url)) != nil { removed += 1 }
        }
        return removed
    }

    /// 1-based rank of `waiterURL` among live waiter files sorted by filename.
    public static func waiterPosition(laneKey: String, waiterURL: URL) -> Int {
        let names = waiterFileNames(laneKey: laneKey)
        guard let idx = names.firstIndex(of: waiterURL.lastPathComponent) else {
            // Missing file → would-be position among remaining live waiters (PO-F9 `#13`).
            return max(1, names.count + 1)
        }
        return idx + 1
    }

    /// Count of registered live waiter files (best-effort; dead waiters filtered).
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
            .filter { $0.pathExtension == "json" }
            .filter { url in
                guard let data = try? Data(contentsOf: url),
                      let waiter = try? CoreJSON.decode(WaiterFile.self, from: data)
                else {
                    // Unreadable / legacy without identity — keep for rank stability.
                    return true
                }
                guard let identity = waiter.identity else { return true }
                return ProcessOwnership.isIdentityAlive(identity)
            }
            .map(\.lastPathComponent)
            .sorted()
    }
}

// MARK: - Per-lane in-process meta mutex (PO-F9 #2)

/// Recursive per-lane mutex so same-process threads cannot interleave
/// `holder.json` RMW while still allowing same-thread nested `withMetaLock`.
/// Cross-process exclusion remains the `meta.lock` flock.
fileprivate final class MetaLockMutexTable: @unchecked Sendable {
    static let shared = MetaLockMutexTable()

    private let lock = NSLock()
    private var mutexes: [String: NSRecursiveLock] = [:]

    private init() {}

    func mutex(for laneKey: String) -> NSRecursiveLock {
        lock.lock()
        defer { lock.unlock() }
        if let existing = mutexes[laneKey] { return existing }
        let created = NSRecursiveLock()
        mutexes[laneKey] = created
        return created
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

    enum DetailedAcquire {
        case acquired(ExecutionLaneFlock.Handle)
        case busy
        case unavailable(Int32)
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
        switch tryAcquireDetailed(laneKey: laneKey) {
        case .acquired(let handle): return handle
        case .busy, .unavailable: return nil
        }
    }

    func tryAcquireDetailed(laneKey: String) -> DetailedAcquire {
        tryAcquireFile(
            tableKey: laneKey,
            fileURL: ExecutionLaneFlock.lockURL(forLaneKey: laneKey),
            laneKey: laneKey
        )
    }

    /// Brief exclusive hold on `meta.lock` (not the build `lane.lock`).
    func tryAcquireMeta(laneKey: String) -> ExecutionLaneFlock.Handle? {
        let tableKey = "meta:" + laneKey
        let url = ExecutionLaneFlock.directory(forLaneKey: laneKey)
            .appendingPathComponent(ExecutionLaneFlock.metaLockFileName)
        switch tryAcquireFile(tableKey: tableKey, fileURL: url, laneKey: tableKey) {
        case .acquired(let handle): return handle
        case .busy, .unavailable: return nil
        }
    }

    private func tryAcquireFile(
        tableKey: String,
        fileURL: URL,
        laneKey handleKey: String
    ) -> DetailedAcquire {
        // PO-F9 `#14`: pre-create the directory outside the table NSLock so
        // mkdir/syscalls do not serialize unrelated lane acquires.
        let dir = fileURL.deletingLastPathComponent()
        do {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        } catch {
            return .unavailable(errno)
        }

        lock.lock()
        defer { lock.unlock() }

        if var existing = entries[tableKey], existing.refCount > 0 {
            existing.refCount += 1
            entries[tableKey] = existing
            return .acquired(ExecutionLaneFlock.Handle(laneKey: handleKey))
        }

        let path = fileURL.path
        // PO-F9 `#1`: O_CLOEXEC so spawned workers do not inherit the flock fd
        // (parent death must release the lane).
        let fd = open(path, O_CREAT | O_RDWR | O_CLOEXEC, 0o600)
        guard fd >= 0 else {
            return .unavailable(errno)
        }
        if flock(fd, LOCK_EX | LOCK_NB) != 0 {
            let lockErrno = errno
            close(fd)
            // PO-F9 `#5`: only EWOULDBLOCK/EAGAIN is contention.
            if lockErrno == EWOULDBLOCK || lockErrno == EAGAIN {
                return .busy
            }
            return .unavailable(lockErrno)
        }
        // SR-5 (Sol F1): stale-lane GC may have unlinked this lock file between our open()
        // and flock(). flock binds to the inode, so holding an already-unlinked inode while
        // a fresh acquirer locks a newly-created one at the same path yields two "exclusive"
        // holders. If st_nlink == 0 the file is gone — drop it and report busy so the
        // caller's retry loop reopens the live inode (or recreates it).
        var st = stat()
        if fstat(fd, &st) == 0 && st.st_nlink == 0 {
            _ = flock(fd, LOCK_UN)
            close(fd)
            return .busy
        }
        entries[tableKey] = Entry(fd: fd, refCount: 1)
        return .acquired(ExecutionLaneFlock.Handle(laneKey: handleKey))
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
