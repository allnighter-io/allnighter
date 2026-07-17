import Foundation

/// Declared write scope for a relay/pilot dev turn
/// (`docs/phases/Process_Ownership.md` PO-S06).
///
/// - **Absent declaration** (nil / legacy): full-scope + build lane — today's exclusive behavior.
/// - **Declared `writeScope`**: root-relative path prefixes the turn may commit under.
/// - **`needsBuildLane`**: when `false`, a docs-only turn may run concurrently with a
///   build-lane holder if scopes are pairwise disjoint; overlapping scopes still queue FIFO.
public struct TurnWriteScope: Codable, Sendable, Equatable {
    /// Root-relative path prefixes (e.g. `docs/`, `docs/phases/`). Empty means full scope
    /// for lane conflict (overlaps everyone) but **no** fail-closed path check (same as
    /// undeclared for enforcement — only non-empty prefixes activate commit-diff rejection).
    public var pathPrefixes: [String]
    /// When `true` (default), the turn takes the exclusive build-class flock slot.
    /// When `false`, only scope coordination applies (docs-only / non-build).
    public var needsBuildLane: Bool

    public init(pathPrefixes: [String] = [], needsBuildLane: Bool = true) {
        self.pathPrefixes = pathPrefixes
            .map { Self.normalizePrefix($0) }
            .filter { !$0.isEmpty }
        self.needsBuildLane = needsBuildLane
    }

    /// Legacy / undeclared: exclusive build lane, full write scope.
    public static let legacyFullBuild = TurnWriteScope(pathPrefixes: [], needsBuildLane: true)

    /// True when this declaration carries non-empty prefixes for fail-closed enforcement.
    public var hasDeclaredPrefixes: Bool { !pathPrefixes.isEmpty }

    /// Full-scope for conflict: no prefixes (undeclared or empty list).
    public var isFullScope: Bool { pathPrefixes.isEmpty }

    /// Normalize a path prefix for comparison (strip leading `./`, collapse //, optional trailing / kept logical).
    public static func normalizePrefix(_ raw: String) -> String {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        while s.hasPrefix("./") { s = String(s.dropFirst(2)) }
        while s.hasPrefix("/") { s = String(s.dropFirst()) }
        // Collapse internal duplicate slashes.
        while s.contains("//") { s = s.replacingOccurrences(of: "//", with: "/") }
        return s
    }

    /// True when `path` (repo-relative) falls under any declared prefix.
    public func contains(path: String) -> Bool {
        guard hasDeclaredPrefixes else { return true }
        let p = Self.normalizePrefix(path)
        return pathPrefixes.contains { prefix in
            Self.path(p, isUnderPrefix: prefix)
        }
    }

    /// Paths from a commit range that fall outside declared prefixes.
    public func outOfScopePaths(in changedPaths: [String]) -> [String] {
        guard hasDeclaredPrefixes else { return [] }
        return changedPaths.filter { !contains(path: $0) }
    }

    /// Two scopes conflict when their path sets can overlap **or** both need the build lane.
    public static func conflicts(_ a: TurnWriteScope, _ b: TurnWriteScope) -> Bool {
        if a.needsBuildLane && b.needsBuildLane { return true }
        return scopesOverlap(a.pathPrefixes, b.pathPrefixes)
    }

    /// Prefix sets overlap when either is empty (full) or any pair of prefixes nest/equal.
    public static func scopesOverlap(_ a: [String], _ b: [String]) -> Bool {
        if a.isEmpty || b.isEmpty { return true }
        for ap in a {
            for bp in b {
                if path(ap, isUnderPrefix: bp) || path(bp, isUnderPrefix: ap) {
                    return true
                }
            }
        }
        return false
    }

    public static func path(_ path: String, isUnderPrefix prefix: String) -> Bool {
        let p = normalizePrefix(path)
        let pre = normalizePrefix(prefix)
        if pre.isEmpty { return true }
        if p == pre { return true }
        let boundary = pre.hasSuffix("/") ? pre : pre + "/"
        return p.hasPrefix(boundary)
    }
}

/// Fail-closed write-scope violation (`docs/phases/Process_Ownership.md` PO-S06).
///
/// Stamped when the harness diffs the turn's commits (`baseline..head`) against the
/// declared `writeScope` and finds out-of-scope paths. `endReason` stays `reported`;
/// the PM decides what to do with the commits — Allnighter never auto-reverts.
public struct ScopeViolation: Codable, Sendable, Equatable {
    public static let errorCode = "WRITE_SCOPE_VIOLATION"

    /// Declared prefixes that were enforced.
    public var declaredScope: [String]
    /// Root-relative paths in the turn's commit range outside the declaration.
    public var outOfScopePaths: [String]
    /// Stable typed error code (registered in the contract catalog).
    public var code: String
    /// Human-readable summary for status / roundLog.
    public var message: String

    public init(
        declaredScope: [String],
        outOfScopePaths: [String],
        code: String = ScopeViolation.errorCode,
        message: String? = nil
    ) {
        self.declaredScope = declaredScope
        self.outOfScopePaths = outOfScopePaths
        self.code = code
        if let message {
            self.message = message
        } else {
            let sample = outOfScopePaths.prefix(5).joined(separator: ", ")
            let more = outOfScopePaths.count > 5 ? " (+\(outOfScopePaths.count - 5) more)" : ""
            self.message =
                "Dev turn committed paths outside declared writeScope [\(declaredScope.joined(separator: ", "))]: \(sample)\(more). Work is rejected; PM decides (no auto-revert)."
        }
    }
}
