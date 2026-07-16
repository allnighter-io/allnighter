import Foundation

/// Standing provenance instruction for mutating runs (Field_Reports_1.md §FR4).
/// Convention only — Allnighter does no git and cannot enforce commit trailers.
public enum ProvenanceConvention {
    /// One sentence asking the worker to end commit messages with a Co-Authored-By trailer.
    public static func commitTrailerAsk(displayName: String) -> String {
        "End every commit message with a final line: Co-Authored-By: \(displayName) via Allnighter."
    }

    /// Marker used to avoid double-injecting the trailer when multiple prompt layers assemble.
    public static let trailerMarker = "Co-Authored-By:"

    // MARK: - FR12 commit fidelity (instruct + verify, never perform)

    public static let commitMessageMarker = "COMMIT MESSAGE (VERBATIM — do not reword)"

    public static func commitMessageVerbatimBlock(message: String) -> String {
        """
        COMMIT MESSAGE (VERBATIM — do not reword)

        Use this commit message **verbatim** — byte-exact, do not reword, do not translate, \
        append nothing before the first line:

        ```
        \(message)
        ```

        The first line must match exactly. You may add Co-Authored-By trailers and body lines \
        after the first line only.
        """
    }

    public static let noCommitMarker = "DO NOT COMMIT — leave work uncommitted"

    public static func noCommitBlock() -> String {
        """
        DO NOT COMMIT — leave work uncommitted

        Leave all changes **uncommitted** in the working tree. The PM will commit with their \
        own hands after review. Do not run `git commit`.
        """
    }

    // MARK: - FR13 proof alignment (surface only, never gate git)

    public static let proofVerificationMarker = "your work will be verified by:"

    public static func proofVerificationLine(command: String) -> String {
        "your work will be verified by: \(command)"
    }
}
