import Foundation

/// Built-in per-seat stance prefixes (RB1's perspective-diversity amplifier; the
/// field exists from Phase 06 so self-fusion seats can already differ). A stance
/// is a short framing prepended to the founder prompt for one seat. Unknown ids
/// resolve to no prefix (graceful).
public enum StanceLibrary {
    public static let builtInIDs = ["neutral", "skeptic", "first_principles", "minimalist", "user_advocate"]

    public static func prefix(for stanceId: String?) -> String? {
        guard let stanceId else { return nil }
        switch stanceId {
        case "neutral":
            return nil
        case "skeptic":
            return "Adopt a skeptical stance: assume the obvious approach has a fundamental flaw. Find it and say what you would do differently."
        case "first_principles":
            return "Reason from first principles: ignore existing conventions and design from scratch what you would build."
        case "minimalist":
            return "Take a minimalist stance: propose the smallest version that delivers the core value; cut everything non-essential."
        case "user_advocate":
            return "Answer as the end user who will live with the result: what is confusing, risky, or missing for them?"
        default:
            return nil
        }
    }

    /// Assembles a seat's prompt: stance prefix (if any) then the founder prompt.
    public static func assemblePrompt(stance: String?, founderPrompt: String) -> String {
        guard let prefix = prefix(for: stance) else { return founderPrompt }
        return "\(prefix)\n\n\(founderPrompt)"
    }
}
