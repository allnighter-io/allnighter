import Foundation

/// The execution lane is the safety boundary for Execute (dispatch) orders.
/// Allnighter submits at most ONE Execute order at a time per lane — concurrent
/// Execute orders writing the same place are catastrophic. This is INVIOLABLE
/// (docs/phases/Pending_Work_And_Drain.md §execution lane; founder memory
/// "pending-execute-lane-safety"). Never weaken it.
///
/// Canonical key (spec):
///   v1:hash(workerId, normalizedWorkingDir||"unknown-dir", sessionBinding||"unknown-session")
/// where unknown values make the key MORE conservative (shared), never more
/// permissive.
///
/// Until Allnighter manages worktrees/branches, the only real-world boundary is
/// the working DIRECTORY: two agents editing one repo dir concurrently corrupts
/// work regardless of which worker or session issued them. So this derivation
/// keys the lane on the normalized directory ALONE — strictly more conservative
/// than the full formula (it can only serialize MORE, never less). When worktree
/// isolation ships, the key may safely subdivide by (worker, session). Folding
/// worker/session in now would only *narrow* lanes (more permissive) — banned.
public enum ExecutionLane {

    /// The lane key for an Execute order in `workingDirectory`. A nil/blank dir
    /// collapses to a single shared "unknown-dir" lane (maximally conservative).
    public static func key(workingDirectory: String?) -> String {
        "v1:" + fnv1a(normalize(workingDirectory) ?? "unknown-dir")
    }

    /// Canonical path normalization so `/repo`, `/repo/`, and `/repo/sub/..` map
    /// to one lane. Standardizes and strips a trailing slash; blank → nil.
    static func normalize(_ path: String?) -> String? {
        guard let path else { return nil }
        let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        var std = (trimmed as NSString).standardizingPath
        while std.count > 1, std.hasSuffix("/") { std.removeLast() }
        return std
    }

    /// Deterministic (cross-process-stable) FNV-1a 64-bit hex. A collision can
    /// only over-merge two lanes — which serializes unrelated work (safe), never
    /// runs two orders in one real lane (unsafe).
    static func fnv1a(_ s: String) -> String {
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in s.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x0000_0100_0000_01b3
        }
        return String(hash, radix: 16)
    }
}

/// One-Running-per-lane gate. `acquire` succeeds (and marks the lane busy) only
/// when the lane was free; a concurrent acquire on a busy lane fails. The caller
/// MUST `release` when the order settles.
///
/// FIFO auto-drain of waiting orders is the deferred Pending phase. Refusing a
/// concurrent same-lane order — never running two at once — is the conservative
/// behavior shipped now; it cannot violate the one-at-a-time invariant. The
/// shared instance is process-wide so every dispatch path consults one truth.
public actor ExecutionLaneRegistry {
    public static let shared = ExecutionLaneRegistry()

    private var busy: Set<String> = []

    public init() {}

    /// True if the lane was free and is now held; false if already busy.
    @discardableResult
    public func acquire(_ key: String) -> Bool {
        busy.insert(key).inserted
    }

    public func release(_ key: String) {
        busy.remove(key)
    }

    public func isBusy(_ key: String) -> Bool {
        busy.contains(key)
    }
}
