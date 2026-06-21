import Foundation

/// Composer paste policy (the threshold lives here, NOT as a magic number in the view):
/// a clipboard text paste longer than `longTextThreshold` characters becomes an
/// attachable text block instead of flooding the prompt editor. The captured text is
/// delivered to every worker (single or team) as run context — it is NOT a fabricated
/// file; the content really reaches the model.
public enum ComposerPasteContract {
    /// Pastes longer than this become a text attachment chip. Tuned so a normal sentence
    /// or short snippet still inserts inline, while logs/transcripts/articles attach.
    public static let longTextThreshold = 1_200

    /// Render a captured pasted-text block for the run context, fenced so the model can
    /// tell it apart from the user's actual prompt.
    public static func contextBlock(title: String, body: String) -> String {
        "# Pasted: \(title)\n\n```\n\(body)\n```"
    }

    /// A short, honest chip label for a captured paste (e.g. "Pasted text · 4.2k chars").
    public static func chipLabel(charCount: Int) -> String {
        let count: String
        if charCount >= 1_000 {
            let k = Double(charCount) / 1_000
            count = String(format: "%.1fk", k)
        } else {
            count = "\(charCount)"
        }
        return "Pasted text · \(count) chars"
    }
}
