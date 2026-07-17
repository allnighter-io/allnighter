import Foundation
import AllnighterCore

/// Per-root execution / build lane (`docs/phases/Process_Ownership.md` PO-S03 / S03b).
///
/// One holder per canonical repo root. Same key derivation as the historical
/// `ExecutionLane` / current `RunWriteLock` — **no second lane system**. Busy
/// callers receive a **FIFO ticket** (position, holder identity/kind/id,
/// heldSinceSeconds); silent 0%-CPU queueing without a ticket is forbidden.
///
/// **PO-S03b:** mutual exclusion is an OS-level per-root `flock` held by the
/// owning process for the lane duration. Kernel releases on process death.
/// Identity-based release remains a metadata/local-handoff cleanup path.
/// Death of the holder's identity releases the in-process hold immediately
/// (no staleness timer) with `endReason: reconciledOrphan`.
public enum ExecutionLane {
    /// Ownership receipt. Required for `release` so stray/double release cannot
    /// free the lane under the real holder.
    public struct Token: Sendable, Equatable, Hashable {
        fileprivate let id: UInt64
    }

    /// Who is claiming the lane and for what work.
    public struct Claim: Sendable, Equatable {
        public var id: String
        public var kind: String
        public var identity: ProcessOwnership.OwnerIdentity

        public init(id: String, kind: String, identity: ProcessOwnership.OwnerIdentity) {
            self.id = id
            self.kind = kind
            self.identity = identity
        }

        /// Claim for the current process (lane held by the coordinating CLI/app).
        public static func current(
            id: String,
            kind: String,
            ownerKind: ProcessOwnership.OwnerKind = .inProcess
        ) -> Claim? {
            guard let identity = ProcessOwnership.OwnerIdentity.current(kind: ownerKind) else {
                return nil
            }
            return Claim(id: id, kind: kind, identity: identity)
        }

        /// Test / fallback claim with an explicit identity.
        public static func make(
            id: String,
            kind: String,
            identity: ProcessOwnership.OwnerIdentity
        ) -> Claim {
            Claim(id: id, kind: kind, identity: identity)
        }

        fileprivate var ticketHolder: ExecutionLaneTicket.Holder {
            ExecutionLaneTicket.Holder(
                identity: identity.asRecord(),
                kind: kind,
                id: id
            )
        }
    }

    /// Canonical key — identical to `RunWriteLock.key` (one system, one key).
    public static func key(repoRoot: String?) -> String {
        RunWriteLock.key(repoRoot: repoRoot)
    }

    /// Historical name used by Execute-lane call sites.
    public static func key(workingDirectory: String?) -> String {
        key(repoRoot: workingDirectory)
    }

    public static func normalize(_ path: String?) -> String? {
        RunWriteLock.normalize(path)
    }
}

/// Process-wide per-root lane registry. Shared instance is the only holder of
/// truth for build-class work on a root **within this process**. Cross-process
/// exclusion is the OS flock under `ExecutionLaneFlock` (PO-S03b).
public actor ExecutionLaneRegistry {
    public static let shared = ExecutionLaneRegistry()

    private struct HolderState {
        var token: ExecutionLane.Token
        var claim: ExecutionLane.Claim
        var heldAt: Date
        /// Same-process reentrancy (outer relay hold + inner RunService / proof).
        var depth: Int
        /// Open flock fd — must stay alive for the hold duration.
        var flockHandle: ExecutionLaneFlock.Handle
    }

    private struct Waiter {
        let id: UInt64
        let claim: ExecutionLane.Claim
        let continuation: CheckedContinuation<ExecutionLane.Token?, Never>
        let enqueuedAt: Date
        /// Cross-process waiter file (cleaned on grant / abandon).
        let waiterFileURL: URL?
    }

    private var holders: [String: HolderState] = [:]
    private var waiters: [String: [Waiter]] = [:]
    private var nextWaiterId: UInt64 = 0
    private var nextTokenId: UInt64 = 0

    /// Last release endReason per key (for tests / `alln ps` foreshadowing).
    private var lastEndReason: [String: String] = [:]

    public init() {}

    // MARK: - Non-blocking / ticket

    /// Try to take the lane. On success returns a token; on busy returns a FIFO
    /// ticket for position 1 of a *would-be* waiter (does **not** enqueue — use
    /// `waitToAcquire` for fair queue membership). Same-process re-entry (matching
    /// identity) deepens the hold and returns the existing token.
    ///
    /// Cross-process: contending processes fail the non-blocking flock and mint
    /// a ticket from on-disk holder metadata.
    public func tryAcquire(
        _ key: String,
        claim: ExecutionLane.Claim,
        now: Date = Date()
    ) -> Result<ExecutionLane.Token, ExecutionLaneTicket> {
        _ = reconcileIfHolderDead(key, now: now)
        if let existing = holders[key], canReenter(existing: existing.claim, incoming: claim) {
            holders[key]?.depth += 1
            return .success(existing.token)
        }
        if holders[key] != nil {
            return .failure(ticket(for: key, position: 1, now: now))
        }
        if let token = issueTokenWithFlock(for: key, claim: claim, now: now) {
            return .success(token)
        }
        // Flock held by another process (or race). Ticket from disk metadata.
        let position = ExecutionLaneFlock.wouldBePosition(laneKey: key)
        if let diskTicket = ExecutionLaneFlock.ticketIfBusy(
            laneKey: key, position: position, now: now
        ) {
            return .failure(diskTicket)
        }
        // Flock failed but no metadata and not locked — treat as transient fail
        // with a minimal ticket so callers never spin without a name.
        return .failure(
            ExecutionLaneTicket(
                position: position,
                holder: ExecutionLaneTicket.Holder(
                    identity: ProcessOwnerRecord(
                        pid: 0, pgid: nil, startTimeTicks: 0, kind: "unknown"
                    ),
                    kind: "unknown",
                    id: "unknown"
                ),
                heldSinceSeconds: 0
            )
        )
    }

    /// FIFO acquire with visible tickets. Invokes `onTicket` while queued so the
    /// harness can project `laneBlocked` on status. Returns a token (caller MUST
    /// `release`) or `nil` on timeout/cancel (no ownership taken).
    ///
    /// In-process waiters preserve actor FIFO; cross-process waiters register
    /// timestamped files and contend on the flock.
    public func waitToAcquire(
        _ key: String,
        claim: ExecutionLane.Claim,
        timeout: Duration,
        now: @escaping @Sendable () -> Date = { Date() },
        onTicket: (@Sendable (ExecutionLaneTicket) -> Void)? = nil
    ) async -> ExecutionLane.Token? {
        let t0 = now()
        _ = reconcileIfHolderDead(key, now: t0)
        if let existing = holders[key], canReenter(existing: existing.claim, incoming: claim) {
            holders[key]?.depth += 1
            return existing.token
        }
        if holders[key] == nil, let token = issueTokenWithFlock(for: key, claim: claim, now: t0) {
            return token
        }

        let waiterId = nextWaiterId
        nextWaiterId &+= 1
        let waiterFile = ExecutionLaneFlock.registerWaiter(
            laneKey: key, claim: claim, enqueuedAt: t0
        )
        let position: Int = {
            if let waiterFile {
                return ExecutionLaneFlock.waiterPosition(laneKey: key, waiterURL: waiterFile)
            }
            return (waiters[key]?.count ?? 0) + 1
        }()
        onTicket?(busyTicket(for: key, position: position, now: t0))

        // While queued, periodically reconcile a dead local holder and retry
        // the flock (cross-process holder death is kernel-released).
        let reconcileTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(200))
                await self?.reconcile(key)
                // Cross-process: if no local holder, try to grant head waiter via flock.
                await self?.tryGrantCrossProcessWaiters(key)
            }
        }

        let timeoutTask = Task { [weak self] in
            try? await Task.sleep(for: timeout)
            await self?.expire(key: key, id: waiterId)
        }

        let granted = await withTaskCancellationHandler {
            await withCheckedContinuation { (continuation: CheckedContinuation<ExecutionLane.Token?, Never>) in
                waiters[key, default: []].append(
                    Waiter(
                        id: waiterId,
                        claim: claim,
                        continuation: continuation,
                        enqueuedAt: t0,
                        waiterFileURL: waiterFile
                    )
                )
            }
        } onCancel: {
            Task { await self.expire(key: key, id: waiterId) }
        }
        timeoutTask.cancel()
        reconcileTask.cancel()
        // Clean waiter file if still present (expire/grant paths also clean).
        if granted == nil {
            ExecutionLaneFlock.unregisterWaiter(waiterFile)
        }
        return granted
    }

    /// Legacy non-blocking try (no claim metadata). Prefer claim-bearing APIs.
    @discardableResult
    public func acquire(_ key: String) -> ExecutionLane.Token? {
        let claim = anonymousClaim(id: "anonymous")
        if case .success(let token) = tryAcquire(key, claim: claim) {
            return token
        }
        return nil
    }

    /// Legacy FIFO wait without ticket callback (RunService write-lock path).
    /// Still reconciles dead holders before waiting.
    public func waitToAcquire(_ key: String, timeout: Duration) async -> ExecutionLane.Token? {
        let claim = anonymousClaim(id: "mutatingRun")
        return await waitToAcquire(key, claim: claim, timeout: timeout, now: { Date() }, onTicket: nil)
    }

    // MARK: - Release / reconcile

    /// Release ownership. Token must match; stray/double release is a no-op.
    /// Nested same-process holds only decrement depth until the outermost release.
    public func release(
        _ key: String,
        token: ExecutionLane.Token,
        endReason: String = "completed"
    ) {
        guard var holder = holders[key], holder.token == token else { return }
        if holder.depth > 1 {
            holder.depth -= 1
            holders[key] = holder
            return
        }
        lastEndReason[key] = endReason
        handOffOrClear(key: key)
    }

    /// If the current holder identity is dead, release immediately with
    /// `reconciledOrphan` and hand off to the next waiter. No staleness timer.
    /// Drops the flock handle so the kernel-visible lock frees for other processes.
    @discardableResult
    public func reconcile(_ key: String, now: Date = Date()) -> Bool {
        reconcileIfHolderDead(key, now: now)
    }

    public func isHeld(_ key: String) -> Bool {
        if holders[key] != nil { return true }
        return ExecutionLaneFlock.isLocked(laneKey: key)
    }

    public func isBusy(_ key: String) -> Bool {
        isHeld(key)
    }

    /// Current ticket for a would-be waiter at `position` (1 = next to run).
    public func currentTicket(
        _ key: String,
        position: Int = 1,
        now: Date = Date()
    ) -> ExecutionLaneTicket? {
        if holders[key] != nil {
            return ticket(for: key, position: max(1, position), now: now)
        }
        return ExecutionLaneFlock.ticketIfBusy(
            laneKey: key, position: max(1, position), now: now
        )
    }

    public func lastReleaseEndReason(for key: String) -> String? {
        lastEndReason[key]
    }

    /// Waiter count currently enqueued for `key` (tests / status).
    /// Includes in-process queue; disk waiter files are best-effort extras.
    public func waiterCount(for key: String) -> Int {
        waiters[key]?.count ?? 0
    }

    // MARK: - Private

    private func anonymousClaim(id: String) -> ExecutionLane.Claim {
        if let claim = ExecutionLane.Claim.current(id: id, kind: "mutatingRun") {
            return claim
        }
        // Fallback when start-time ticks unavailable (extremely rare).
        return ExecutionLane.Claim(
            id: id,
            kind: "mutatingRun",
            identity: ProcessOwnership.OwnerIdentity(
                pid: ProcessInfo.processInfo.processIdentifier,
                pgid: nil,
                startTimeTicks: 0,
                kind: .inProcess
            )
        )
    }

    @discardableResult
    private func reconcileIfHolderDead(_ key: String, now: Date) -> Bool {
        guard let holder = holders[key] else { return false }
        if ProcessOwnership.isIdentityAlive(holder.claim.identity) {
            return false
        }
        lastEndReason[key] = "reconciledOrphan"
        // Full drop of flock (handle deinit unlocks) + metadata; then hand off.
        forceReleaseFlockAndMetadata(key: key)
        grantNextWaiter(key: key, now: now)
        return true
    }

    /// Outermost release: transfer flock to next in-process waiter, or unlock.
    private func handOffOrClear(key: String) {
        guard let old = holders.removeValue(forKey: key) else { return }
        guard var queue = waiters[key], !queue.isEmpty else {
            waiters[key] = nil
            ExecutionLaneFlock.clearHolder(laneKey: key)
            // Drop handle last so flock stays held through metadata clear.
            old.flockHandle.unlockAndClose()
            return
        }
        // Grant head waiter; transfer the same flock handle (no unlock).
        let next = queue.removeFirst()
        waiters[key] = queue.isEmpty ? nil : queue
        let grantNow = Date()
        let token = ExecutionLane.Token(id: nextTokenId)
        nextTokenId &+= 1
        try? ExecutionLaneFlock.writeHolder(
            laneKey: key, claim: next.claim, acquiredAt: grantNow
        )
        holders[key] = HolderState(
            token: token,
            claim: next.claim,
            heldAt: grantNow,
            depth: 1,
            flockHandle: old.flockHandle
        )
        ExecutionLaneFlock.unregisterWaiter(next.waiterFileURL)
        next.continuation.resume(returning: token)
    }

    /// After flock fully released, grant next waiter by re-acquiring flock.
    private func grantNextWaiter(key: String, now: Date) {
        guard var queue = waiters[key], !queue.isEmpty else {
            waiters[key] = nil
            return
        }
        let next = queue.removeFirst()
        waiters[key] = queue.isEmpty ? nil : queue
        if let token = issueTokenWithFlock(for: key, claim: next.claim, now: now) {
            ExecutionLaneFlock.unregisterWaiter(next.waiterFileURL)
            next.continuation.resume(returning: token)
            return
        }
        // Flock still not available (another process won) — re-queue at head.
        queue.insert(next, at: 0)
        waiters[key] = queue
    }

    /// When no local holder, try to promote the head in-process waiter via flock.
    private func tryGrantCrossProcessWaiters(_ key: String) {
        guard holders[key] == nil else { return }
        guard let queue = waiters[key], let head = queue.first else { return }
        if let token = issueTokenWithFlock(for: key, claim: head.claim, now: Date()) {
            var rest = queue
            let granted = rest.removeFirst()
            waiters[key] = rest.isEmpty ? nil : rest
            ExecutionLaneFlock.unregisterWaiter(granted.waiterFileURL)
            granted.continuation.resume(returning: token)
        }
    }

    private func forceReleaseFlockAndMetadata(key: String) {
        if let old = holders.removeValue(forKey: key) {
            ExecutionLaneFlock.clearHolder(laneKey: key)
            old.flockHandle.unlockAndClose()
        } else {
            ExecutionLaneFlock.clearHolder(laneKey: key)
        }
    }

    private func expire(key: String, id: UInt64) {
        guard var queue = waiters[key], let idx = queue.firstIndex(where: { $0.id == id }) else {
            return
        }
        let waiter = queue.remove(at: idx)
        waiters[key] = queue.isEmpty ? nil : queue
        ExecutionLaneFlock.unregisterWaiter(waiter.waiterFileURL)
        waiter.continuation.resume(returning: nil)
    }

    /// Acquire OS flock + write holder metadata + record local HolderState.
    private func issueTokenWithFlock(
        for key: String,
        claim: ExecutionLane.Claim,
        now: Date
    ) -> ExecutionLane.Token? {
        guard let handle = ExecutionLaneFlock.tryAcquireExclusive(laneKey: key) else {
            return nil
        }
        do {
            try ExecutionLaneFlock.writeHolder(laneKey: key, claim: claim, acquiredAt: now)
        } catch {
            // Still hold the flock; metadata write failure must not leave lock free
            // without a local holder — keep handle and record what we can.
            try? ExecutionLaneFlock.writeHolder(
                laneKey: key,
                metadata: .init(claim: claim, acquiredAt: now)
            )
        }
        let token = ExecutionLane.Token(id: nextTokenId)
        nextTokenId &+= 1
        holders[key] = HolderState(
            token: token,
            claim: claim,
            heldAt: now,
            depth: 1,
            flockHandle: handle
        )
        return token
    }

    private func identitiesMatch(
        _ a: ProcessOwnership.OwnerIdentity,
        _ b: ProcessOwnership.OwnerIdentity
    ) -> Bool {
        a.pid == b.pid && a.startTimeTicks == b.startTimeTicks
    }

    /// Nested re-entry only: outer relay/pilot may admit mutating/harness holds from
    /// the same process; mutating may admit harness. Peer claims (two relays, two
    /// mutating runs) never re-enter — they take a FIFO ticket.
    private func canReenter(existing: ExecutionLane.Claim, incoming: ExecutionLane.Claim) -> Bool {
        guard identitiesMatch(existing.identity, incoming.identity) else { return false }
        let outer = existing.kind
        let inner = incoming.kind
        if outer == ExecutionLaneSite.relayDevTurn.rawValue
            || outer == ExecutionLaneSite.pilotDevTurn.rawValue
        {
            return inner == ExecutionLaneSite.mutatingRun.rawValue
                || inner == ExecutionLaneSite.harnessProof.rawValue
        }
        if outer == ExecutionLaneSite.mutatingRun.rawValue {
            return inner == ExecutionLaneSite.harnessProof.rawValue
        }
        return false
    }

    private func ticket(for key: String, position: Int, now: Date) -> ExecutionLaneTicket {
        let holder = holders[key]!
        let heldSince = max(0, now.timeIntervalSince(holder.heldAt))
        return ExecutionLaneTicket(
            position: position,
            holder: holder.claim.ticketHolder,
            heldSinceSeconds: heldSince
        )
    }

    /// Ticket when busy: prefer local holder, else disk metadata.
    private func busyTicket(for key: String, position: Int, now: Date) -> ExecutionLaneTicket {
        if holders[key] != nil {
            return ticket(for: key, position: position, now: now)
        }
        if let disk = ExecutionLaneFlock.ticketIfBusy(laneKey: key, position: position, now: now) {
            return disk
        }
        return ExecutionLaneTicket(
            position: position,
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
}

// MARK: - RunWriteLock façade (one system, one key)

/// Historical name for the per-root mutating / build lane key helpers.
/// Delegates to `ExecutionLane` — do not invent a parallel key or registry.
public enum RunWriteLock {
    public typealias Token = ExecutionLane.Token

    public static func key(repoRoot: String?) -> String {
        // Keep the exact prior key formula here so ExecutionLane.key and all
        // historical RunWriteLock keys stay byte-identical.
        "v1:" + fnv1a(normalize(repoRoot) ?? "unknown-root")
    }

    static func normalize(_ path: String?) -> String? {
        guard let path else { return nil }
        let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        var std = (trimmed as NSString).standardizingPath
        while std.count > 1, std.hasSuffix("/") { std.removeLast() }
        std = URL(fileURLWithPath: std, isDirectory: true).resolvingSymlinksInPath().path
        while std.count > 1, std.hasSuffix("/") { std.removeLast() }
        return std
    }

    static func fnv1a(_ s: String) -> String {
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in s.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x0000_0100_0000_01b3
        }
        return String(hash, radix: 16)
    }
}

/// Process-wide registry — **the** execution lane. Alias kept so existing
/// `RunWriteLockRegistry` call sites stay one system with `ExecutionLaneRegistry`.
public typealias RunWriteLockRegistry = ExecutionLaneRegistry
