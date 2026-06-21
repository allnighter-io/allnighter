import Foundation

/// Composer paste policy (the threshold lives here, NOT as a magic number in the view):
/// a clipboard text paste longer than `longTextThreshold` characters becomes an
/// attachable `.txt` file instead of flooding the prompt editor. The captured text is
/// committed as a real file and delivered to every worker (single or team) by path — it
/// is NOT a fabricated attachment; the content really reaches the model.
public enum ComposerPasteContract {
    /// Pastes longer than this become a text attachment chip. Tuned so a normal sentence
    /// or short snippet still inserts inline, while logs/transcripts/articles attach.
    public static let longTextThreshold = 1_200

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
