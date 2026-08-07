import Foundation
import AgentOSCLI

/// CT-08 — which write-lock roots an OpenCode `WorkerInvocation` may cite for
/// sibling `external_directory` auto-approve.
///
/// Mutating runs that hold the per-root lane publish that normalized root.
/// Answer-only / non-mutating publishes none — siblings stay fail-closed unless
/// an explicit cross-root grant is added later.
public enum OpenCodeHeldWriteLockRoots {
    public static func forInvoke(repoRoot: String, mutating: Bool) -> Set<String> {
        guard mutating else { return [] }
        guard let normalized = RunWriteLock.normalize(repoRoot) else { return [] }
        return [normalized]
    }
}
