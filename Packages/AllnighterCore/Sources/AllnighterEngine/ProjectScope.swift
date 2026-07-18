import Foundation

/// Project-root scope for aggregate ownership operations
/// (`docs/phases/Concurrent_Invocation_Isolation.md` F1/F3).
///
/// Scope IS the canonical project root (`TeamRun.repoRoot` /
/// `RelayState.projectRoot`), normalized through the one existing key system
/// (`RunWriteLock.normalize` — symlinks resolved, trailing slashes stripped).
/// No second registry, lane, or ownership system.
///
/// Law: **fail closed.** A record whose root cannot be resolved (nil / empty /
/// `unknown-root`) never matches a scope and is therefore skipped by a scoped
/// aggregate op — never swept, never killed. Exact run-id operations stay
/// explicit and may cross projects when named.
public enum ProjectScope {
    /// True when `recordRoot` resolves to the same canonical root as
    /// `scopeRoot`. Either side unresolvable → false (fail closed).
    public static func matches(scopeRoot: String, recordRoot: String?) -> Bool {
        guard let scope = RunWriteLock.normalize(scopeRoot) else { return false }
        guard let record = RunWriteLock.normalize(recordRoot) else { return false }
        return record == scope
    }
}
