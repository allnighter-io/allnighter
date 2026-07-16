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
}
