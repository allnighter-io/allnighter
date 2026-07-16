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
