import Foundation
import AllnighterCore

/// The deterministic rule that binds a legacy path (a thread/Pending `workingDir`
/// or run root) to a Project. Shared by thread migration (PRJ-S03) and Pending
/// migration (PRJ-S04) so both bind identically. No guessing: ambiguous cases
/// resolve to `.unassigned`, never to a wrong Project.
public enum ProjectBinding {
    public enum Resolution: Equatable, Sendable {
        /// Bind to this existing Project (exact root, or nearest ancestor root).
        case existing(ProjectID)
        /// Create/reuse a Project at this git repo top level, then bind.
        case repoRoot(path: String)
        /// No reliable Project — leave Unassigned (repair bucket), blocked from mutate.
        case unassigned
    }

    /// Resolve `rawPath` against existing Projects, then a containing git repo root.
    ///
    /// Order (deterministic): exact normalized-key match → nearest-ancestor Project
    /// root → the single containing git repo top level → `.unassigned`.
    public static func resolve(
        rawPath: String?,
        projects: [Project],
        git: GitObserver = GitObserver()
    ) -> Resolution {
        guard let rawPath, !rawPath.isEmpty else { return .unassigned }
        let key = RootNormalization.normalize(rawPath).key

        // 1. Exact root.
        if let exact = projects.first(where: { $0.normalizedRootPath == key }) {
            return .existing(exact.id)
        }
        // 2. Nearest-ancestor Project root (longest project key that is a path
        //    ancestor of `key`). Path-segment boundary so "/a/bc" is not an
        //    ancestor of "/a/bcd".
        let ancestors = projects
            .filter { isAncestorPath($0.normalizedRootPath, of: key) }
            .sorted { $0.normalizedRootPath.count > $1.normalizedRootPath.count }
        if let nearest = ancestors.first {
            return .existing(nearest.id)
        }
        // 3. The single containing git repo top level.
        if git.observe(rootPath: key).kind == .gitRepo {
            return .repoRoot(path: key)   // key IS a repo top level
        }
        if let top = git.repoTopLevel(forPath: key) {
            return .repoRoot(path: top)
        }
        // 4. No reliable Project.
        return .unassigned
    }

    /// True when `ancestor` is a strict path-ancestor of `path` on segment boundaries.
    static func isAncestorPath(_ ancestor: String, of path: String) -> Bool {
        guard ancestor != path else { return false }
        let a = ancestor.hasSuffix("/") ? ancestor : ancestor + "/"
        return path.hasPrefix(a)
    }
}
