import Foundation

/// Signal-craft scout policy. Only an X-capable model (Grok today) can grab a
/// public post from a link, so the scout role wants Grok. This is the source of
/// the customize-team warning when a user removes Grok from the scout role.
public enum SignalScoutPolicy {
    /// Canonical X-capable scout seat (Grok 4.6 on the native Grok CLI).
    public static let xCapableScoutModelId = "model_grok_46"

    private static let xCapableScoutModelIds: Set<String> = [
        "model_grok", "model_grok_46",
        "model_cursor_grok_45", "model_cursor_grok_46",
    ]

    public static func isXCapableScout(_ modelId: String?) -> Bool {
        guard let modelId else { return false }
        return xCapableScoutModelIds.contains(modelId)
    }

    /// A non-blocking warning for the customize-team surface, or nil when the team's
    /// scout role is fine. Surfaced when editing a Signal team that drops Grok from
    /// the scout — the user can still save, but should understand the tradeoff.
    public static func scoutWarning(for team: TeamPreset) -> String? {
        guard team.lane == .signal else { return nil }
        guard let scout = team.scout else {
            return "No scout: without an X-capable scout (Grok), this team can't grab a public X/URL link — workers only see text you paste."
        }
        if scout.allowedModelIds.contains(where: isXCapableScout) { return nil }
        return scoutModelWarning(scout.preferredModelId)
    }

    /// Live warning for the editor as a scout model is picked, or nil when it's Grok.
    /// Drives the inline warning under the Scout row in the customize-team UI.
    public static func scoutModelWarning(_ modelId: String?) -> String? {
        guard !isXCapableScout(modelId) else { return nil }
        return "Grok removed from the scout role: only Grok can grab a public X post from a link. Without it the scout can't read X URLs — paste the post text instead, or keep Grok as the scout."
    }
}
