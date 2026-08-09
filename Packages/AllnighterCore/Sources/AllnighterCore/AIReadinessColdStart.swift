import Foundation

/// ARA-S06: cold-start counsel for projects with no agent history — never a score,
/// grade, or rating. The first recommended Code Team is AI Readiness.
public enum AIReadinessColdStart {
    public static let teamId = "code_ai_readiness"
    public static let runExample = "alln run \"Audit this repo for AI readiness\" --team code_ai_readiness --json"

    /// Returns counsel when the project has no prior thread/run history; nil otherwise.
    /// The counsel names AI Readiness as the first recommended Code Team and includes
    /// the runExample command so the caller can paste-and-go.
    public static func counsel(threadCount: Int) -> String? {
        guard threadCount == 0 else { return nil }
        return "AI Readiness is the first recommended Code Team — \(runExample)"
    }
}
