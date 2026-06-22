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
    /// Suspended callers per key, in arrival order. The holder hands ownership to the head of
    /// this queue on `release` (ownership transfer — `held` is never cleared mid-handoff).
    private var waiters: [String: [CheckedContinuation<Void, Never>]] = [:]

    public init() {}

    /// Non-blocking try-acquire: takes the key if free, else returns `false` immediately.
    /// Kept for callers that must not wait; the run path uses `waitToAcquire` instead.
    @discardableResult
    public func acquire(_ key: String) -> Bool {
        held.insert(key).inserted
    }

    /// FIFO acquire: returns immediately if the key is free, otherwise suspends until it is
    /// this caller's turn. On return, the caller owns the key and MUST call `release(key)`
    /// exactly once (the run path does so in a `defer`). The mutating-run path uses this so a
    /// second run on the same repo waits its turn rather than being refused.
    ///
    /// Cancellation note: a caller suspended here is resumed when ownership is handed to it on
    /// the holder's `release`; a cancelled task then proceeds past the await, does its
    /// (cancelled, fast-returning) work, and releases in its `defer`, so the queue drains.
    public func waitToAcquire(_ key: String) async {
        if held.insert(key).inserted { return }
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            waiters[key, default: []].append(continuation)
        }
    }

    public func release(_ key: String) {
        if var queue = waiters[key], !queue.isEmpty {
            let next = queue.removeFirst()
            waiters[key] = queue.isEmpty ? nil : queue
            // Ownership transfers to `next`; `held` stays set so no one else can slip in.
            next.resume()
        } else {
            held.remove(key)
        }
    }

    public func isHeld(_ key: String) -> Bool {
        held.contains(key)
    }
}
