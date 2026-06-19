import Foundation

/// Answer = parallel breadth (N workers, read-only). Execution = depth (one worker, may write).
public enum RunShape: String, Codable, Sendable, CaseIterable {
    case answer
    case execution
}

/// Mechanical write policy for a run — not a user toggle.
public enum RunWritePolicy: String, Codable, Sendable, CaseIterable {
    case readOnly
    case mutating
}

public extension TeamPreset {
    /// Derived shape: mutating teams collapse to exactly one worker (execution).
    var runShape: RunShape { mutating ? .execution : .answer }

    var writePolicy: RunWritePolicy { mutating ? .mutating : .readOnly }
}
