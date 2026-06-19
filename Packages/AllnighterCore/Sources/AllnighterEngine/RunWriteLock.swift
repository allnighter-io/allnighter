import Foundation

/// At most one mutating run per canonical repo root. Read/answer runs never take
/// the lock; a second mutating run on the same root is refused with one honest
/// line — no queue, no approval gate (Unified Run Model).
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

/// Process-wide mutating-run gate keyed by normalized repo root.
public actor RunWriteLockRegistry {
    public static let shared = RunWriteLockRegistry()

    private var held: Set<String> = []

    public init() {}

    @discardableResult
    public func acquire(_ key: String) -> Bool {
        held.insert(key).inserted
    }

    public func release(_ key: String) {
        held.remove(key)
    }

    public func isHeld(_ key: String) -> Bool {
        held.contains(key)
    }
}
