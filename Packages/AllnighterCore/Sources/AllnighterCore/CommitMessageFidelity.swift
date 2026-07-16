import Foundation

/// FR12 — compare a requested commit message against observed `repoDelta` subjects.
/// Allnighter instructs and verifies; workers own git.
public enum CommitMessageFidelity {
    /// The first line of the newest commit's message (`repoDelta.commits[0].subject`)
    /// must equal the requested string byte-exact after trimming **trailing** whitespace
    /// on both sides. Additional commit-message lines (body, trailers) are ignored.
    public static func matched(requested: String, delta: RepoDelta?) -> Bool? {
        let expected = trimTrailingWhitespace(requested)
        guard !expected.isEmpty else { return nil }
        guard let delta, delta.changed, let newest = delta.commits.first else { return false }
        return trimTrailingWhitespace(newest.subject) == expected
    }

    private static func trimTrailingWhitespace(_ text: String) -> String {
        var end = text.endIndex
        while end > text.startIndex {
            let prev = text.index(before: end)
            guard text[prev].isWhitespace else { break }
            end = prev
        }
        return String(text[..<end])
    }
}
