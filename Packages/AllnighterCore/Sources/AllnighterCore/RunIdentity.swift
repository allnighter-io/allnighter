import Foundation

/// Human-facing run identity — worker, lane, write policy, and honest team naming.
/// Per Unified Run Model: with an explicit `--worker`, `--lane` is context metadata;
/// identity leads with what an auditor needs, not internal preset ids.
public enum RunIdentity {
    public static let defaultTeamPresetId = "default_chat"
    public static let defaultTeamDisplayName = "Default Team"

    /// When no named team was chosen, say "Default Team" — not the internal preset label ("Auto").
    public static func teamDisplayName(
        presetId: String?, catalogDisplayName: String, explicitTeamChosen: Bool
    ) -> String {
        if !explicitTeamChosen, presetId == defaultTeamPresetId {
            return defaultTeamDisplayName
        }
        return catalogDisplayName
    }

    public static func writePolicyLabel(mutating: Bool) -> String {
        mutating ? "mutating" : "readOnly"
    }

    /// Headline identity: `worker <id> · lane <lane> · mutating|readOnly`.
    public static func summary(workerId: String?, lane: WorkLane?, mutating: Bool) -> String {
        let worker = workerId ?? "?"
        let laneLabel = lane?.rawValue ?? "?"
        return "worker \(worker) · lane \(laneLabel) · \(writePolicyLabel(mutating: mutating))"
    }

    public static func primaryWorkerModelId(_ run: TeamRun) -> String? {
        run.workers.first?.modelId ?? run.workerAnswers.first?.modelId
    }

    /// stderr / human footer after a plain `alln run` (not --json).
    public static func cliFooter(_ run: TeamRun) -> String {
        var parts = [
            "run \(run.id)",
            summary(workerId: primaryWorkerModelId(run), lane: run.lane, mutating: run.mutating),
        ]
        if let deltaLine = repoDeltaSummary(run.repoDelta) { parts.append(deltaLine) }
        if let name = run.teamDisplayName { parts.append(name) }
        if let preset = run.presetId { parts.append(preset) }
        return parts.joined(separator: " · ")
    }

    /// Human summary for a mutating run's observed repo delta.
    public static func repoDeltaSummary(_ delta: RepoDelta?) -> String? {
        guard let delta else { return nil }
        guard delta.changed else { return "no repo change" }
        let shortSha = delta.head.map { String($0.prefix(7)) } ?? "?"
        let fileWord = delta.filesChanged == 1 ? "file" : "files"
        return "committed \(shortSha): \(delta.filesChanged) \(fileWord)"
    }
}
