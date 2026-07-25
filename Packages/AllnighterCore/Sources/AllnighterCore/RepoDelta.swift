import Foundation

/// Observed git delta for a mutating run — HEAD before/after, commits in range, and a
/// changed-files summary (Field_Reports_1.md §FR3). Allnighter reads only; workers own git.
public struct RepoDelta: Codable, Equatable, Sendable {
    public struct CommitInfo: Codable, Equatable, Sendable {
        public var sha: String
        public var subject: String

        public init(sha: String, subject: String) {
            self.sha = sha
            self.subject = subject
        }
    }

    public var changed: Bool
    public var baseline: String?
    public var head: String?
    public var commits: [CommitInfo]
    public var filesChanged: Int
    public var files: [String]
    /// `true` when `filesChanged` exceeds the surfaced `files` cap.
    public var truncated: Bool

    public init(
        changed: Bool,
        baseline: String? = nil,
        head: String? = nil,
        commits: [CommitInfo] = [],
        filesChanged: Int = 0,
        files: [String] = [],
        truncated: Bool = false
    ) {
        self.changed = changed
        self.baseline = baseline
        self.head = head
        self.commits = commits
        self.filesChanged = filesChanged
        self.files = files
        self.truncated = truncated
    }
}

/// CR-S02 — bounded pre/post Git observation for a research (read-only) run.
///
/// An observational Team (`mutating == false`) is not mechanically
/// read-only: Allnighter captures the canonical repository's exact Git state
/// before dispatch and after terminal settlement, then compares against the
/// PRE-EXISTING state (a repo that was already dirty is not a violation).
/// `changed == true` is a surfaced research-write violation — a read-only Team
/// was observed to alter tracked or untracked Git state. Allnighter reads only;
/// it never resets, deletes, or "repairs" the user's files.
public struct ResearchGitObservation: Codable, Equatable, Sendable {
    /// True when the observed Git state changed across the run window (violation).
    public var changed: Bool
    /// Exact HEAD captured before dispatch.
    public var baselineHead: String?
    /// Exact HEAD captured after terminal settlement.
    public var head: String?
    /// Root-relative paths whose Git status differs pre/post (bounded), when changed.
    public var changedPaths: [String]
    /// True when more paths changed than the surfaced `changedPaths` cap.
    public var truncated: Bool

    public init(
        changed: Bool,
        baselineHead: String? = nil,
        head: String? = nil,
        changedPaths: [String] = [],
        truncated: Bool = false
    ) {
        self.changed = changed
        self.baselineHead = baselineHead
        self.head = head
        self.changedPaths = changedPaths
        self.truncated = truncated
    }
}
