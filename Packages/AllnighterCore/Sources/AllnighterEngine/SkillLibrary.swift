import Foundation

/// Built-in per-worker skill prefixes. A skill is a short framing prepended to
/// the founder prompt for one worker assignment.
public enum SkillLibrary {
    public static let builtInIDs = ["neutral", "skeptic", "first_principles", "minimalist", "user_advocate"]

    public static func prefix(for skillId: String?) -> String? {
        guard let skillId else { return nil }
        switch skillId {
        case "neutral":
            return nil
        case "skeptic":
            return "Adopt a skeptical lens: assume the obvious approach has a fundamental flaw. Find it and say what you would do differently."
        case "first_principles":
            return "Reason from first principles: ignore existing conventions and design from scratch what you would build."
        case "minimalist":
            return "Take a minimalist lens: propose the smallest version that delivers the core value; cut everything non-essential."
        case "user_advocate":
            return "Answer as the end user who will live with the result: what is confusing, risky, or missing for them?"
        default:
            return nil
        }
    }

    public static func assemblePrompt(skillId: String?, founderPrompt: String) -> String {
        guard let prefix = prefix(for: skillId) else { return founderPrompt }
        return "\(prefix)\n\n\(founderPrompt)"
    }
}
