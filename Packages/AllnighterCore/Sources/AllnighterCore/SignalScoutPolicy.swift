import Foundation

/// Signal-craft scout policy. Only an X-capable model (Grok today) can grab a
/// public post from a link, so the scout role wants Grok. This is the source of
/// the customize-team warning when a user removes Grok from the scout role.
public enum SignalScoutPolicy {
    /// The X-capable scout model. Capability-selected in spirit (a future X-capable
    /// model would join here); pinned to Grok today, the only web/X reader on-bench.
    public static let xCapableScoutModelId = "model_grok"

    /// A non-blocking warning for the customize-team surface, or nil when the team's
    /// scout role is fine. Surfaced when editing a Signal team that drops Grok from
    /// the scout — the user can still save, but should understand the tradeoff.
    public static func scoutWarning(for team: TeamPreset) -> String? {
        guard team.lane == .signal else { return nil }
        guard let scout = team.scout else {
            return "No scout: without an X-capable scout (Grok), this team can't grab a public X/URL link — workers only see text you paste."
        }
        let usesGrok = scout.preferredModelId == xCapableScoutModelId
            || scout.allowedModelIds.contains(xCapableScoutModelId)
        guard !usesGrok else { return nil }
        return "Grok removed from the scout role: only Grok can grab a public X post from a link. Without it the scout can't read X URLs — paste the post text instead, or keep Grok as the scout."
    }
}
