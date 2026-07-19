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
        /// PO-S06: path prefixes + build-lane flag. Default = legacy full-scope exclusive.
        public var writeScope: TurnWriteScope

        public init(
            id: String,
            kind: String,
            identity: ProcessOwnership.OwnerIdentity,
            writeScope: TurnWriteScope = .legacyFullBuild
        ) {
            self.id = id
            self.kind = kind
            self.identity = identity
            self.writeScope = writeScope
        }

        /// Claim for the current process (lane held by the coordinating CLI/app).
        public static func current(
            id: String,
            kind: String,
            ownerKind: ProcessOwnership.OwnerKind = .inProcess,
            writeScope: TurnWriteScope = .legacyFullBuild
        ) -> Claim? {
            guard let identity = ProcessOwnership.OwnerIdentity.current(kind: ownerKind) else {
                return nil
            }
            return Claim(id: id, kind: kind, identity: identity, writeScope: writeScope)
        }

        /// Test / fallback claim with an explicit identity.
        public static func make(
            id: String,
            kind: String,
            identity: ProcessOwnership.OwnerIdentity,
            writeScope: TurnWriteScope = .legacyFullBuild
        ) -> Claim {
            Claim(id: id, kind: kind, identity: identity, writeScope: writeScope)
        }

        fileprivate var ticketHolder: ExecutionLaneTicket.Holder {
            ExecutionLaneTicket.Holder(
                identity: identity.asRecord(),
                kind: kind,
                id: id
            )
        }

        fileprivate var asScope: TurnWriteScope { writeScope }
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
/// exclusion is the OS flock under `ExecutionLaneFlock` (PO-S03b). PO-S06 allows
/// multiple simultaneous holders when write scopes are pairwise disjoint and at
/// most one needs the exclusive build flock.
public actor ExecutionLaneRegistry {
    public static let shared = ExecutionLaneRegistry()

    private struct HolderState {
        var token: ExecutionLane.Token
        var claim: ExecutionLane.Claim
        var heldAt: Date
        /// Same-process reentrancy (outer relay hold + inner RunService / proof).
        var depth: Int
        /// Open build flock fd — nil for docs-only (`needsBuildLane: false`) holds.
        var flockHandle: ExecutionLaneFlock.Handle?
    }

    private struct Waiter {
        let id: UInt64
        let claim: ExecutionLane.Claim
        let continuation: CheckedContinuation<ExecutionLane.Token?, Never>
        let enqueuedAt: Date
        /// Cross-process waiter file (cleaned on grant / abandon).
        let waiterFileURL: URL?
        /// RLR-S02a: ticket callback, re-fired when this waiter's FIFO position
        /// changes so a durable `ticketPosition` never goes stale (nil for callers
        /// that don't consume tickets — relay/pilot/proof).
        let onTicket: (@Sendable (ExecutionLaneTicket) -> Void)?
        /// Last position handed to `onTicket` (suppresses redundant re-fires).
        var lastNotifiedPosition: Int
    }

    /// Multi-holder per root key (PO-S06). Legacy exclusive = one full-scope build holder.
    private var holders: [String: [HolderState]] = [:]
    private var waiters: [String: [Waiter]] = [:]
    private var nextWaiterId: UInt64 = 0
    private var nextTokenId: UInt64 = 0

    /// Last release endReason per key (for tests / `alln ps` foreshadowing).
    private var lastEndReason: [String: String] = [:]

    /// Last wait-timeout endReason per key. Stamped `laneBusy` when a
    /// `waitToAcquire` waiter expires (PO-F2) so callers/tests can assert the
    /// timeout path without re-inferring from a nil token.
    private var lastWaitEndReason: [String: String] = [:]

    /// Last hard flock errno per key (SR-4 / Sol F14). Set by `issueToken` on a
    /// non-contention lock failure (EMFILE/ENOLCK/unsupported FS); consumed by the acquire
    /// paths so a genuine hard failure fails fast instead of masquerading as lane-busy for
    /// the full wait timeout.
    private var lastHardLockErrno: [String: Int32] = [:]

    public init() {}

    private func consumeHardLockErrno(_ key: String) -> Int32? {
        guard let code = lastHardLockErrno[key] else { return nil }
        lastHardLockErrno[key] = nil
        return code
    }

    // MARK: - Non-blocking / ticket

    /// Try to take the lane. On success returns a token; on busy returns a FIFO
    /// ticket for position 1 of a *would-be* waiter (does **not** enqueue — use
    /// `waitToAcquire` for fair queue membership). Same-process re-entry (matching
    /// identity) deepens the hold and returns the existing token.
    ///
    /// PO-S06: a docs-only claim with a disjoint writeScope may succeed while a
    /// build-lane holder is live. Overlapping scopes or dual build-lane claims fail
    /// with a ticket naming the conflicting holder.
    public func tryAcquire(
        _ key: String,
        claim: ExecutionLane.Claim,
        now: Date = Date()
    ) -> Result<ExecutionLane.Token, ExecutionLaneTicket> {
        _ = reconcileIfHolderDead(key, now: now)
        if let existing = findReenterable(key: key, claim: claim) {
            if let upgraded = upgradeHoldForReentry(key: key, existing: existing, incoming: claim) {
                deepen(key: key, token: upgraded.token)
                return .success(upgraded.token)
            }
            // SR-3: escalated to the build lane but the flock is foreign-held right now —
            // ticket instead of granting a flock-less build.
            return .failure(ticket(from: existing, position: 1, now: now))
        }
        if let conflict = firstConflictingLocal(key: key, claim: claim) {
            return .failure(ticket(from: conflict, position: 1, now: now))
        }
        // Cross-process: any conflicting on-disk holder (or exclusive build flock).
        if let diskConflict = ExecutionLaneFlock.ticketIfBusy(
            laneKey: key, position: ExecutionLaneFlock.wouldBePosition(laneKey: key),
            now: now, forClaim: claim
        ) {
            // If disk only reports a holder we already co-hold as non-conflicting,
            // ticketIfBusy returns nil — here a non-nil means real conflict.
            return .failure(diskConflict)
        }
        if let token = issueToken(for: key, claim: claim, now: now) {
            return .success(token)
        }
        // SR-4: this non-blocking path always returns a ticket on failure; clear any hard
        // errno issueToken recorded so it can't leak into a later waitToAcquire on this key.
        _ = consumeHardLockErrno(key)
        // Build flock race / meta lock timeout — mint a ticket so callers never spin.
        let position = ExecutionLaneFlock.wouldBePosition(laneKey: key)
        if let diskTicket = ExecutionLaneFlock.ticketIfBusy(
            laneKey: key, position: position, now: now, forClaim: claim
        ) {
            return .failure(diskTicket)
        }
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
    public func waitToAcquire(
        _ key: String,
        claim: ExecutionLane.Claim,
        timeout: Duration,
        now: @escaping @Sendable () -> Date = { Date() },
        onTicket: (@Sendable (ExecutionLaneTicket) -> Void)? = nil,
        shouldAbandon: (@Sendable (ExecutionLane.Claim) -> Bool)? = nil
    ) async -> ExecutionLane.Token? {
        let t0 = now()
        _ = reconcileIfHolderDead(key, now: t0)
        if let existing = findReenterable(key: key, claim: claim) {
            if let upgraded = upgradeHoldForReentry(key: key, existing: existing, incoming: claim) {
                deepen(key: key, token: upgraded.token)
                return upgraded.token
            }
            // SR-3: escalated build reentry blocked by a foreign build flock — fall through
            // to the FIFO waiter path and acquire it for real when it frees, never run a
            // flock-less build.
        }
        if firstConflictingLocal(key: key, claim: claim) == nil,
           let token = issueToken(for: key, claim: claim, now: t0) {
            return token
        }
        // SR-4: a hard flock errno (not contention) must not park for the full timeout.
        if let code = consumeHardLockErrno(key) {
            lastWaitEndReason[key] = "lockError:\(code)"
            return nil
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
        onTicket?(busyTicket(for: key, claim: claim, position: position, now: t0))

        let enqueuePosition = position
        let reconcileTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(200))
                if Task.isCancelled { return }
                // RLR-S02c: the parked run may have been stamped terminal by ANOTHER
                // process (cross-process cancel/kill of a blocked run), which cannot
                // reach this in-memory continuation. Self-abandon — withdraw our own
                // waiter and resume `nil` — so the caller stops queueing instead of
                // parking to the full timeout. The killer has already withdrawn our
                // on-disk waiter file, so the remaining waiters' positions have already
                // collapsed; this only resolves the parked continuation.
                if let shouldAbandon, shouldAbandon(claim) {
                    await self.expire(key: key, id: waiterId, endReason: "withdrawn")
                    return
                }
                await self.reconcile(key)
                await self.tryGrantWaiters(key)
            }
        }

        let timeoutTask = Task {
            do {
                try await Task.sleep(for: timeout, clock: ContinuousClock())
            } catch {
                return
            }
            guard !Task.isCancelled else { return }
            await self.expire(key: key, id: waiterId, endReason: "laneBusy")
        }

        let granted = await withTaskCancellationHandler {
            await withCheckedContinuation { (continuation: CheckedContinuation<ExecutionLane.Token?, Never>) in
                waiters[key, default: []].append(
                    Waiter(
                        id: waiterId,
                        claim: claim,
                        continuation: continuation,
                        enqueuedAt: t0,
                        waiterFileURL: waiterFile,
                        onTicket: onTicket,
                        lastNotifiedPosition: enqueuePosition
                    )
                )
            }
        } onCancel: {
            Task { await self.expire(key: key, id: waiterId, endReason: "cancelled") }
        }
        timeoutTask.cancel()
        reconcileTask.cancel()
        if granted == nil {
            ExecutionLaneFlock.unregisterWaiter(waiterFile)
        }
        return granted
    }

    /// Legacy non-blocking try (no claim metadata). Prefer claim-bearing APIs.
    /// Unique claim id so two concurrent callers never same-id reenter each other
    /// (exclusive mutual exclusion); intentional same-id reuse is for claim-bearing
    /// APIs that pass a stable work id (relay/turn).
    @discardableResult
    public func acquire(_ key: String) -> ExecutionLane.Token? {
        guard let claim = anonymousClaim(id: "anonymous-\(UUID().uuidString)") else { return nil }
        if case .success(let token) = tryAcquire(key, claim: claim) {
            return token
        }
        return nil
    }

    /// Legacy FIFO wait without ticket callback (RunService write-lock path).
    /// Unique claim id per wait so concurrent mutating runs queue FIFO; nesting
    /// under an outer relay/pilot hold still re-enters via the kind chain.
    public func waitToAcquire(_ key: String, timeout: Duration) async -> ExecutionLane.Token? {
        guard let claim = anonymousClaim(id: "mutatingRun-\(UUID().uuidString)") else { return nil }
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
        guard var list = holders[key],
              let idx = list.firstIndex(where: { $0.token == token }) else { return }
        if list[idx].depth > 1 {
            list[idx].depth -= 1
            holders[key] = list
            return
        }
        let old = list.remove(at: idx)
        holders[key] = list.isEmpty ? nil : list
        lastEndReason[key] = endReason
        ExecutionLaneFlock.removeHolder(laneKey: key, id: old.claim.id)
        old.flockHandle?.unlockAndClose()
        // After release, try to grant waiters that no longer conflict.
        grantCompatibleWaiters(key: key, now: Date())
    }

    /// If any holder identity is dead, drop it immediately with `reconciledOrphan`
    /// and try to grant waiters. No staleness timer.
    @discardableResult
    public func reconcile(_ key: String, now: Date = Date()) -> Bool {
        reconcileIfHolderDead(key, now: now)
    }

    public func isHeld(_ key: String) -> Bool {
        if let list = holders[key], !list.isEmpty { return true }
        if !ExecutionLaneFlock.readHolders(laneKey: key).isEmpty { return true }
        return ExecutionLaneFlock.isLocked(laneKey: key)
    }

    public func isBusy(_ key: String) -> Bool {
        isHeld(key)
    }

    /// Local multi-holder count (tests / status).
    public func localHolderCount(for key: String) -> Int {
        holders[key]?.count ?? 0
    }

    /// Current ticket for a would-be waiter at `position` (1 = next to run).
    public func currentTicket(
        _ key: String,
        position: Int = 1,
        now: Date = Date(),
        forClaim: ExecutionLane.Claim? = nil
    ) -> ExecutionLaneTicket? {
        if let forClaim, let conflict = firstConflictingLocal(key: key, claim: forClaim) {
            return ticket(from: conflict, position: max(1, position), now: now)
        }
        if forClaim == nil, let first = holders[key]?.first {
            return ticket(from: first, position: max(1, position), now: now)
        }
        return ExecutionLaneFlock.ticketIfBusy(
            laneKey: key, position: max(1, position), now: now, forClaim: forClaim
        )
    }

    public func lastReleaseEndReason(for key: String) -> String? {
        lastEndReason[key]
    }

    /// Why the most recent `waitToAcquire` on `key` returned nil without a grant
    /// (`laneBusy` on timeout, `cancelled` on task cancel). Nil if no wait has
    /// expired on this key yet (PO-F2).
    public func lastWaitEndReason(for key: String) -> String? {
        lastWaitEndReason[key]
    }

    /// Waiter count currently enqueued for `key` (tests / status).
    public func waiterCount(for key: String) -> Int {
        waiters[key]?.count ?? 0
    }

    // MARK: - Private

    /// SR-15 (Sol F15): fail closed. When the process can't read its own start-ticks we
    /// return nil rather than fabricating a `startTimeTicks: 0` identity — a live holder with
    /// zero ticks reads as dead on the next reconcile, which would release its own flock while
    /// the caller is still running (double-run). Refusing the lane is strictly safer than a
    /// self-defeating identity. (The trigger — self-`sysctl(KERN_PROC)` failure — is
    /// near-unreachable on macOS, but fail-closed is the correct posture.)
    private func anonymousClaim(id: String) -> ExecutionLane.Claim? {
        ExecutionLane.Claim.current(id: id, kind: "mutatingRun")
    }

    @discardableResult
    private func reconcileIfHolderDead(_ key: String, now: Date) -> Bool {
        // Drop identity-dead disk holders (docs-only strays; torn build metadata).
        pruneDeadDiskHolders(laneKey: key)

        guard var list = holders[key], !list.isEmpty else {
            return false
        }
        var released = false
        list = list.filter { state in
            if ProcessOwnership.isIdentityAlive(state.claim.identity) {
                return true
            }
            released = true
            ExecutionLaneFlock.removeHolder(laneKey: key, id: state.claim.id)
            state.flockHandle?.unlockAndClose()
            return false
        }
        holders[key] = list.isEmpty ? nil : list
        if released {
            lastEndReason[key] = "reconciledOrphan"
            grantCompatibleWaiters(key: key, now: now)
        }
        return released
    }

    private func pruneDeadDiskHolders(laneKey: String) {
        _ = ExecutionLaneFlock.withMetaLockSpinning(laneKey: laneKey) { () -> Bool in
            let all = ExecutionLaneFlock.readHolders(laneKey: laneKey)
            let live = all.filter {
                ExecutionLaneFlock.isHolderEffectivelyLive($0, laneKey: laneKey)
            }
            guard live.count != all.count else { return false }
            if live.isEmpty {
                try? FileManager.default.removeItem(
                    at: ExecutionLaneFlock.holderURL(forLaneKey: laneKey)
                )
            } else {
                try? ExecutionLaneFlock.writeHolders(laneKey: laneKey, holders: live)
            }
            return true
        }
    }

    /// Grant every waiter that no longer conflicts (FIFO order, multi-grant for disjoint scopes).
    private func grantCompatibleWaiters(key: String, now: Date) {
        guard var queue = waiters[key], !queue.isEmpty else {
            waiters[key] = nil
            return
        }
        var remaining: [Waiter] = []
        for waiter in queue {
            if firstConflictingLocal(key: key, claim: waiter.claim) != nil {
                remaining.append(waiter)
                continue
            }
            if let token = issueToken(for: key, claim: waiter.claim, now: now) {
                ExecutionLaneFlock.unregisterWaiter(waiter.waiterFileURL)
                waiter.continuation.resume(returning: token)
            } else {
                remaining.append(waiter)
            }
        }
        waiters[key] = remaining.isEmpty ? nil : remaining
        // RLR-S02a: the queue just shifted — re-fire tickets whose position changed
        // so blocked runs' durable `ticketPosition` tracks the draining line.
        renotifyWaitersOnPositionChange(key: key, now: now)
    }

    /// Re-fire each still-blocked waiter's `onTicket` when its FIFO position changed
    /// (RLR-S02a). Only ticket-consuming waiters (RunService's mutating wait) are
    /// notified; position is re-ranked from the same source as enqueue (cross-process
    /// waiter file when present, else in-process index).
    private func renotifyWaitersOnPositionChange(key: String, now: Date) {
        guard var queue = waiters[key], !queue.isEmpty else { return }
        for idx in queue.indices {
            guard let onTicket = queue[idx].onTicket else { continue }
            let position: Int = {
                if let url = queue[idx].waiterFileURL {
                    return ExecutionLaneFlock.waiterPosition(laneKey: key, waiterURL: url)
                }
                return idx + 1
            }()
            guard position != queue[idx].lastNotifiedPosition else { continue }
            queue[idx].lastNotifiedPosition = position
            onTicket(busyTicket(for: key, claim: queue[idx].claim, position: position, now: now))
        }
        waiters[key] = queue
    }

    /// Cross-process / periodic: try granting waiters after reconcile.
    private func tryGrantWaiters(_ key: String) {
        grantCompatibleWaiters(key: key, now: Date())
    }

    private func expire(key: String, id: UInt64, endReason: String = "laneBusy") {
        guard var queue = waiters[key], let idx = queue.firstIndex(where: { $0.id == id }) else {
            return
        }
        let waiter = queue.remove(at: idx)
        waiters[key] = queue.isEmpty ? nil : queue
        ExecutionLaneFlock.unregisterWaiter(waiter.waiterFileURL)
        lastWaitEndReason[key] = endReason
        waiter.continuation.resume(returning: nil)
    }

    /// Issue a local hold: exclusive build flock when `needsBuildLane`, else
    /// docs-only metadata registration under meta lock (PO-S06).
    private func issueToken(
        for key: String,
        claim: ExecutionLane.Claim,
        now: Date
    ) -> ExecutionLane.Token? {
        // Foreign (other-process) disk conflicts block. Same-process disk
        // holders are not foreign — nested registry instances share one OS
        // flock via refcount (PO-S03b); local multi-holder policy is owned by
        // firstConflictingLocal, not by disk metadata.
        if let disk = ExecutionLaneFlock.ticketIfBusy(
            laneKey: key, position: 1, now: now, forClaim: claim
        ) {
            let localIds = Set((holders[key] ?? []).map(\.claim.id))
            if !localIds.contains(disk.holder.id) {
                return nil
            }
        }

        let meta = ExecutionLaneFlock.HolderMetadata(claim: claim, acquiredAt: now)
        var flockHandle: ExecutionLaneFlock.Handle?
        if claim.writeScope.needsBuildLane {
            // Process-wide refcount: nested same-process re-entry returns another receipt
            // without contending on our own flock. SR-4: keep the errno distinction so a
            // hard lock failure (EMFILE/ENOLCK/unsupported FS) fails fast rather than reading
            // as contention and waiting out the full timeout.
            let (outcome, handle) = ExecutionLaneFlock.tryAcquireExclusiveOrError(laneKey: key)
            switch outcome {
            case .acquired:
                flockHandle = handle
            case .busy:
                return nil
            case .unavailable(let code):
                lastHardLockErrno[key] = code
                return nil
            }
            guard ExecutionLaneFlock.upsertHolder(laneKey: key, metadata: meta) else {
                flockHandle?.unlockAndClose()
                return nil
            }
        } else {
            // SR-6: docs-only admission re-checks scope conflict and appends atomically under
            // the meta lock — closes the two-overlapping-docs-claims TOCTOU where each reads
            // "no conflict" before either registers.
            guard ExecutionLaneFlock.admitHolderIfClear(laneKey: key, claim: claim, metadata: meta) else {
                return nil
            }
        }

        let token = ExecutionLane.Token(id: nextTokenId)
        nextTokenId &+= 1
        let state = HolderState(
            token: token,
            claim: claim,
            heldAt: now,
            depth: 1,
            flockHandle: flockHandle
        )
        holders[key, default: []].append(state)
        return token
    }

    private func identitiesMatch(
        _ a: ProcessOwnership.OwnerIdentity,
        _ b: ProcessOwnership.OwnerIdentity
    ) -> Bool {
        a.pid == b.pid && a.startTimeTicks == b.startTimeTicks
    }

    private func findReenterable(key: String, claim: ExecutionLane.Claim) -> HolderState? {
        guard let list = holders[key] else { return nil }
        return list.first { canReenter(existing: $0.claim, incoming: claim) }
    }

    /// SR-3 (Sol F4): a dev-turn hold that does not own the build flock must NOT let a nested
    /// claim run build work on the strength of the metadata-only token. When a reentrant claim
    /// escalates to the build lane (`needsBuildLane`) and the existing hold has no flock,
    /// acquire the real flock and attach it to that hold before granting reentry. Returns the
    /// (possibly upgraded) hold, or nil when the build flock is foreign-held right now — the
    /// caller then tickets/waits and acquires it for real, never granting a flock-less build.
    private func upgradeHoldForReentry(
        key: String,
        existing: HolderState,
        incoming: ExecutionLane.Claim
    ) -> HolderState? {
        guard incoming.writeScope.needsBuildLane, existing.flockHandle == nil else {
            return existing   // no build escalation, or the hold already owns the flock
        }
        let (outcome, handle) = ExecutionLaneFlock.tryAcquireExclusiveOrError(laneKey: key)
        switch outcome {
        case .acquired:
            guard var list = holders[key],
                  let idx = list.firstIndex(where: { $0.token == existing.token }) else {
                handle?.unlockAndClose()
                return nil
            }
            list[idx].flockHandle = handle
            holders[key] = list
            return list[idx]
        case .busy:
            return nil
        case .unavailable(let code):
            lastHardLockErrno[key] = code
            return nil
        }
    }

    private func deepen(key: String, token: ExecutionLane.Token) {
        guard var list = holders[key],
              let idx = list.firstIndex(where: { $0.token == token }) else { return }
        list[idx].depth += 1
        holders[key] = list
    }

    private func firstConflictingLocal(key: String, claim: ExecutionLane.Claim) -> HolderState? {
        guard let list = holders[key] else { return nil }
        return list.first { state in
            // Nested re-entry is not a conflict.
            if canReenter(existing: state.claim, incoming: claim) { return false }
            return TurnWriteScope.conflicts(state.claim.writeScope, claim.writeScope)
        }
    }

    /// Nested re-entry: reuse an existing local hold (depth bump) instead of
    /// queueing behind ourselves. Same-id is never a conflict with itself
    /// (stall-retry / nested same-turn re-acquire — PO-S06 self-deadlock fix).
    /// Kind chain: outer relay/pilot admits mutating/harness; mutating admits
    /// harness. Peer claims with different ids never re-enter.
    private func canReenter(existing: ExecutionLane.Claim, incoming: ExecutionLane.Claim) -> Bool {
        guard identitiesMatch(existing.identity, incoming.identity) else { return false }
        // Same claim id = the same relay/turn re-acquiring while still held.
        // Must refcount-bump and return the existing token — never park in waiters.
        if existing.id == incoming.id {
            return true
        }
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

    private func ticket(from holder: HolderState, position: Int, now: Date) -> ExecutionLaneTicket {
        let heldSince = max(0, now.timeIntervalSince(holder.heldAt))
        return ExecutionLaneTicket(
            position: position,
            holder: holder.claim.ticketHolder,
            heldSinceSeconds: heldSince
        )
    }

    private func busyTicket(
        for key: String,
        claim: ExecutionLane.Claim,
        position: Int,
        now: Date
    ) -> ExecutionLaneTicket {
        if let conflict = firstConflictingLocal(key: key, claim: claim) {
            return ticket(from: conflict, position: position, now: now)
        }
        if let disk = ExecutionLaneFlock.ticketIfBusy(
            laneKey: key, position: position, now: now, forClaim: claim
        ) {
            return disk
        }
        if let first = holders[key]?.first {
            return ticket(from: first, position: position, now: now)
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
