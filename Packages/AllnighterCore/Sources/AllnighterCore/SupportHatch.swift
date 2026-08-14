import Foundation

/// Person hatch for CLI identity and failed JSON. Same address as Ask AI /
/// legal (`AskAIPrompt.supportEmail`). Doctor stays diagnostics — this is the
/// discoverability line, not a new pipe.
public enum SupportHatch {
    public static let email = AskAIPrompt.supportEmail
    public static let tellHuman = "Hit a wall? Email \(email) — a person reads it."
    public static let feedbackSentTellHuman =
        "Sent. A person reads it. Left this machine: your message, CLI version, and OS — nothing else."
    public static let feedbackDryRunTellHuman = "Nothing left this machine (--dry-run)."

    /// Fallback when `ErrorDiscovery` has no recovery command. Agents quote
    /// `label` / `tellHuman` to the human. `command` is identity only — do not
    /// treat it as mail-sending.
    public static let nextAction = AgentNextAction(
        kind: "emailSupport",
        label: tellHuman,
        command: "alln version --json"
    )

    /// Recovery `nextAction` wins. When none exists, this hatch is what the
    /// agent should show the human. Usage errors are not a wall. Entitlement
    /// keeps its own `tellHuman`.
    public static func decorate(
        code: String,
        nextAction: AgentNextAction?
    ) -> (nextAction: AgentNextAction?, tellHuman: String?) {
        if let resolved = nextAction ?? ErrorDiscovery.nextAction(forErrorCode: code) {
            return (resolved, nil)
        }
        if code == "CLI_USAGE_ERROR" {
            return (nil, nil)
        }
        return (Self.nextAction, tellHuman)
    }
}
