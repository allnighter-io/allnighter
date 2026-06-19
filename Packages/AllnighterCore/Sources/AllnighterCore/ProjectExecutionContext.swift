import Foundation

// MARK: - PRJ-S06: Project-scoped mutating runs

/// The resolved roots a Project-scoped run must use. Worker cwd, proof cwd, and
/// the attachment mirror all derive from ONE Project root — never an ad hoc
/// `workingDir`. When the root is unavailable the run roots are `nil`, so a
/// missing root structurally blocks mutating runs.
public struct ProjectExecutionScope: Equatable, Sendable {
    public var projectId: ProjectID
    /// The display Project root (expanded `~`, standardized).
    public var rootPath: String
    public var rootState: RootState
    public var kind: ProjectKind
    /// Where the worker subprocess runs. `nil` when a mutating run is not allowed.
    public var workerCwd: String?
    /// Where declared proof commands run. Same root as the worker. `nil` when blocked.
    public var proofCwd: String?
    /// Root the attachment mirror stages under. `nil` when blocked.
    public var attachmentMirrorRoot: String?

    public init(projectId: ProjectID, rootPath: String, rootState: RootState, kind: ProjectKind,
                workerCwd: String?, proofCwd: String?, attachmentMirrorRoot: String?) {
        self.projectId = projectId
        self.rootPath = rootPath
        self.rootState = rootState
        self.kind = kind
        self.workerCwd = workerCwd
        self.proofCwd = proofCwd
        self.attachmentMirrorRoot = attachmentMirrorRoot
    }

    public var allowsMutatingRun: Bool { workerCwd != nil }

    /// Build from a freshly-observed root state (the resolver supplies `rootState`).
    public init(project: Project, observedRootState: RootState) {
        let runnable = observedRootState == .available && !project.archived
        let root = project.localRootPath
        self.init(
            projectId: project.id,
            rootPath: root,
            rootState: observedRootState,
            kind: project.kind,
            workerCwd: runnable ? root : nil,
            proofCwd: runnable ? root : nil,
            attachmentMirrorRoot: runnable ? root : nil
        )
    }
}

/// Deterministic gate decision for a mutating Project-scoped run. Never a
/// judgement call — the same inputs always yield the same decision. Acknowledging
/// dirt is the user's explicit action; Allnighter never cleans, resets, stashes,
/// or deletes user changes.
public enum ProjectMutationGate: Equatable, Sendable {
    /// May run. `warnings` are dirty files outside the likely scope — shown,
    /// never blocking.
    case allowed(warnings: [String])
    /// No usable Project root (missing/permission-denied/archived). No mutating run.
    case blockedNoProjectRoot
    /// Dirty files overlap the proposal's likely scope. Block until the user
    /// approves including them as preexisting context (`dirtyAcknowledged`).
    case blockedDirtyScopeOverlap(files: [String])
    /// No likely scope was declared, so overlap cannot be computed; the dirty tree
    /// must be explicitly acknowledged before a mutating run.
    case needsDirtyAcknowledgement(files: [String])

    public var allowsRun: Bool {
        if case .allowed = self { return true }
        return false
    }
}

/// Evaluates the deterministic dirty-state mutation gate (PRJ-S06). Pure — no git,
/// no filesystem — so the safety rule is unit-testable in isolation. The resolver
/// supplies observed `dirtyFiles` (root-relative) and the freshly-observed
/// `rootState`.
public enum ProjectMutationGateEvaluator {
    public static func evaluate(
        project: Project,
        observedRootState: RootState,
        likelyFilesOrAreas: [String],
        dirtyFiles: [String],
        dirtyAcknowledged: Bool
    ) -> ProjectMutationGate {
        guard observedRootState == .available && !project.archived else {
            return .blockedNoProjectRoot
        }

        let scopeEntries = likelyFilesOrAreas.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        let dirty = dirtyFiles.filter { !$0.isEmpty }

        // No declared scope: overlap is undefined. Surface the whole dirty tree and
        // require explicit acknowledgement (warnings, not a hard block).
        guard !scopeEntries.isEmpty else {
            if dirty.isEmpty { return .allowed(warnings: []) }
            return dirtyAcknowledged ? .allowed(warnings: dirty) : .needsDirtyAcknowledgement(files: dirty)
        }

        let overlap = dirty.filter { file in
            scopeEntries.contains { PathScopeMatcher.matches(file: file, scopeEntry: $0) }
        }
        if overlap.isEmpty {
            return .allowed(warnings: dirty)   // dirty files outside scope are warnings only
        }
        return dirtyAcknowledged ? .allowed(warnings: dirty) : .blockedDirtyScopeOverlap(files: overlap)
    }
}

/// Deterministic match between a dirty file path and a scope entry, on normalized
/// root-relative paths: exact path, directory-prefix (`area/` matches `area/...`),
/// or a declared glob (`*`, `**`, `?`). PRJ-S06 §"Dirty state policy for v1".
public enum PathScopeMatcher {
    public static func matches(file: String, scopeEntry: String) -> Bool {
        let f = normalize(file)
        let entry = normalize(scopeEntry)
        guard !f.isEmpty, !entry.isEmpty else { return false }

        // Glob entry.
        if entry.contains("*") || entry.contains("?") {
            return globMatches(pattern: entry, path: f)
        }
        // Exact path.
        if f == entry { return true }
        // Directory-prefix: `area/` (or `area`) matches `area/...`.
        let dir = entry.hasSuffix("/") ? entry : entry + "/"
        return f.hasPrefix(dir)
    }

    /// Strip a leading `./` and any leading `/`, collapse `\` (defensive). Paths are
    /// already expected to be root-relative.
    private static func normalize(_ path: String) -> String {
        var p = path.trimmingCharacters(in: .whitespaces)
        if p.hasPrefix("./") { p.removeFirst(2) }
        while p.hasPrefix("/") { p.removeFirst() }
        return p
    }

    /// Minimal glob: `**` matches across `/`, `*` matches within a segment, `?`
    /// matches one non-`/` char. Everything else is literal.
    private static func globMatches(pattern: String, path: String) -> Bool {
        var regex = "^"
        var chars = Array(pattern)
        var i = 0
        while i < chars.count {
            let c = chars[i]
            switch c {
            case "*":
                if i + 1 < chars.count && chars[i + 1] == "*" {
                    regex += ".*"        // ** crosses path separators
                    i += 2
                    if i < chars.count && chars[i] == "/" { i += 1 }   // **/ absorbs the slash
                    continue
                }
                regex += "[^/]*"
            case "?":
                regex += "[^/]"
            default:
                regex += NSRegularExpression.escapedPattern(for: String(c))
            }
            i += 1
        }
        regex += "$"
        guard let re = try? NSRegularExpression(pattern: regex) else { return false }
        let range = NSRange(path.startIndex..<path.endIndex, in: path)
        return re.firstMatch(in: path, range: range) != nil
    }
}
