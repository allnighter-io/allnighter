import Foundation

/// Observed git delta for a mutating run — HEAD before/after, commits in range, and a
/// changed-files summary (Field_Reports_1.md §FR3). Allnighter reads only; workers own git.
///
/// `changed` is **commit-range** truth (baseline ≠ head). `worktreeDirty` is independent
/// porcelain truth (S122.3) — a mutator can leave a dirty tree with zero commits.
public struct RepoDelta: Equatable, Sendable {
    public struct CommitInfo: Codable, Equatable, Sendable {
        public var sha: String
        public var subject: String

        public init(sha: String, subject: String) {
            self.sha = sha
            self.subject = subject
        }
    }

    /// True when commits landed in the run window (`baseline != head`). Alias vocabulary:
    /// "commitsChanged" in phase docs — same field.
    public var changed: Bool
    public var baseline: String?
    public var head: String?
    public var commits: [CommitInfo]
    public var filesChanged: Int
    public var files: [String]
    /// `true` when `filesChanged` exceeds the surfaced `files` cap.
    public var truncated: Bool
    /// True when `git status --porcelain` reports any dirty/untracked path (S122.3).
    public var worktreeDirty: Bool

    /// Phase vocabulary alias for `changed` (commit-range).
    public var commitsChanged: Bool { changed }

    public init(
        changed: Bool,
        baseline: String? = nil,
        head: String? = nil,
        commits: [CommitInfo] = [],
        filesChanged: Int = 0,
        files: [String] = [],
        truncated: Bool = false,
        worktreeDirty: Bool = false
    ) {
        self.changed = changed
        self.baseline = baseline
        self.head = head
        self.commits = commits
        self.filesChanged = filesChanged
        self.files = files
        self.truncated = truncated
        self.worktreeDirty = worktreeDirty
    }
}

extension RepoDelta: Codable {
    enum CodingKeys: String, CodingKey {
        case changed, baseline, head, commits, filesChanged, files, truncated, worktreeDirty
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        changed = try c.decode(Bool.self, forKey: .changed)
        baseline = try c.decodeIfPresent(String.self, forKey: .baseline)
        head = try c.decodeIfPresent(String.self, forKey: .head)
        commits = try c.decodeIfPresent([CommitInfo].self, forKey: .commits) ?? []
        filesChanged = try c.decodeIfPresent(Int.self, forKey: .filesChanged) ?? 0
        files = try c.decodeIfPresent([String].self, forKey: .files) ?? []
        truncated = try c.decodeIfPresent(Bool.self, forKey: .truncated) ?? false
        // Legacy run.json predates S122.3 — missing key means unknown/false.
        worktreeDirty = try c.decodeIfPresent(Bool.self, forKey: .worktreeDirty) ?? false
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(changed, forKey: .changed)
        try c.encodeIfPresent(baseline, forKey: .baseline)
        try c.encodeIfPresent(head, forKey: .head)
        try c.encode(commits, forKey: .commits)
        try c.encode(filesChanged, forKey: .filesChanged)
        try c.encode(files, forKey: .files)
        try c.encode(truncated, forKey: .truncated)
        try c.encode(worktreeDirty, forKey: .worktreeDirty)
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
