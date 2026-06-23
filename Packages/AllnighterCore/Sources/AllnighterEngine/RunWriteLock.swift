import Foundation

/// At most one mutating run *executing* per canonical repo root at a time — the
/// inviolable one-writer-per-repo invariant. Read/answer runs never take the lock and
/// stay fully parallel. A second mutating run on the same root WAITS its turn (FIFO) and
/// then runs automatically — it is not refused. "One writer at a time" is the safety rule;
/// a queue enforces it structurally, which is also how the execution-lane dispatch path
/// already behaves. (Earlier this path hard-refused the second run, which leaked a
/// filesystem-safety guard up into ordinary back-to-back chat — see the Grok-Build
/// "already editing" false alarm.)
public enum RunWriteLock {

    /// Canonical key for a repo root. Blank paths collapse to a shared conservative lane.
    public static func key(repoRoot: String?) -> String {
        "v1:" + fnv1a(normalize(repoRoot) ?? "unknown-root")
    }

    static func normalize(_ path: String?) -> String? {
        guard let path else { return nil }
        let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        var std = (trimmed as NSString).standardizingPath
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

/// Process-wide mutating-run gate keyed by normalized repo root. FIFO: while a key is held,
/// further `waitToAcquire` callers suspend in arrival order and are granted one at a time as
/// the holder releases. Exactly one owner per key at any instant — the one-writer invariant.
public actor RunWriteLockRegistry {
    public static let shared = RunWriteLockRegistry()

    private var held: Set<String> = []
    /// One suspended caller: its FIFO id + the continuation to resume with `true` (granted,
    /// ownership transferred) or `false` (timed out / cancelled before its turn).
    private struct Waiter {
        let id: UInt64
        let continuation: CheckedContinuation<Bool, Never>
    }
    /// Suspended callers per key, in arrival order. The holder hands ownership to the head on
    /// `release` (ownership transfer — `held` is never cleared mid-handoff).
    private var waiters: [String: [Waiter]] = [:]
    private var nextWaiterId: UInt64 = 0

    public init() {}

    /// Non-blocking try-acquire: takes the key if free, else returns `false` immediately.
    /// Kept for callers that must not wait; the run path uses `waitToAcquire` instead.
    @discardableResult
    public func acquire(_ key: String) -> Bool {
        held.insert(key).inserted
    }

    /// FIFO acquire, bounded by `timeout`. Returns `true` with ownership (caller MUST call
    /// `release(key)` exactly once), or `false` if the wait timed out OR the caller's task was
    /// cancelled before its turn — in which case NO ownership was taken and the caller must NOT
    /// release. The mutating-run path uses this so a second run on the same repo waits its turn
    /// rather than being refused; the timeout is the safety valve so a wedged holder (one that
    /// outlives even its own worker timeout/watchdog) can't hang every later run forever.
    ///
    /// Resumed exactly once: by `release` (head waiter → `true`) or by `expire` (timeout or
    /// cancellation → `false`). Each path removes the waiter from `waiters` under actor
    /// isolation before resuming, so there is no double-resume and no leak.
    public func waitToAcquire(_ key: String, timeout: Duration) async -> Bool {
        if held.insert(key).inserted { return true }
        let id = nextWaiterId
        nextWaiterId &+= 1
        // Bound the wait: if still queued at the deadline, resume `false`.
        let timeoutTask = Task { [weak self] in
            try? await Task.sleep(for: timeout)
            await self?.expire(key: key, id: id)
        }
        let granted = await withTaskCancellationHandler {
            await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
                waiters[key, default: []].append(Waiter(id: id, continuation: continuation))
            }
        } onCancel: {
            // Caller's task was cancelled while queued — drop the waiter and resume `false`.
            Task { await self.expire(key: key, id: id) }
        }
        timeoutTask.cancel()
        return granted
    }

    /// Resume a still-queued waiter with `false` (timed out / cancelled), exactly once. A no-op
    /// if it was already granted by `release` or already expired.
    private func expire(key: String, id: UInt64) {
        guard var queue = waiters[key], let idx = queue.firstIndex(where: { $0.id == id }) else { return }
        let waiter = queue.remove(at: idx)
        waiters[key] = queue.isEmpty ? nil : queue
        waiter.continuation.resume(returning: false)
    }

    public func release(_ key: String) {
        if var queue = waiters[key], !queue.isEmpty {
            let next = queue.removeFirst()
            waiters[key] = queue.isEmpty ? nil : queue
            // Ownership transfers to `next`; `held` stays set so no one else can slip in.
            next.continuation.resume(returning: true)
        } else {
            held.remove(key)
        }
    }

    public func isHeld(_ key: String) -> Bool {
        held.contains(key)
    }
}
