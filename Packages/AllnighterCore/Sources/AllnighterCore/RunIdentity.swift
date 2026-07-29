import Foundation

/// Human-facing run identity — worker, lane, write policy, and honest team naming.
/// Per Unified Run Model: with an explicit `--model`, `--lane` is context metadata;
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

    /// Lane fragment for identity lines — appends the FR7 clarifier when `--lane` was context only.
    public static func laneLabel(_ lane: WorkLane?, contextOnly: Bool) -> String {
        guard let lane else { return "lane ?" }
        if contextOnly {
            return "lane \(lane.rawValue) (context — --team routes)"
        }
        return "lane \(lane.rawValue)"
    }

    /// Headline identity: `worker <id> · lane <lane> · mutating|readOnly`.
    public static func summary(
        workerId: String?, lane: WorkLane?, mutating: Bool, laneContextOnly: Bool = false
    ) -> String {
        let worker = workerId ?? "?"
        return "worker \(worker) · \(laneLabel(lane, contextOnly: laneContextOnly)) · \(writePolicyLabel(mutating: mutating))"
    }

    public static func primaryWorkerModelId(_ run: TeamRun) -> String? {
        run.workers.first?.modelId ?? run.workerAnswers.first?.modelId
    }

    /// Headline for `TeamRunJSON.outcome` and human stderr: identity + repo delta when mutating.
    /// Optional `wallMs` lets a single-worker terminal summarize observed phase clocks
    /// (queue / ttft / duration / wall) without inventing overhead or blaming parallel seats.
    public static func outcomeHeadline(_ run: TeamRun, wallMs: Int? = nil) -> String {
        var parts = [
            summary(
                workerId: primaryWorkerModelId(run), lane: run.lane, mutating: run.mutating,
                laneContextOnly: run.laneContextOnly == true)
        ]
        if run.mutating {
            if run.noCommitOrdered == true {
                if run.repoDelta?.changed != true,
                   let count = run.uncommittedFileCount, count > 0 {
                    parts.append("left uncommitted for PM review (as ordered)")
                } else if run.repoDelta?.changed == true {
                    parts.append("committed despite no-commit order")
                } else {
                    parts.append("no repo change")
                }
            } else if let deltaLine = repoDeltaSummary(run.repoDelta) {
                parts.append(deltaLine)
            }
            if let requested = run.requestedCommitMessage,
               let matched = CommitMessageFidelity.matched(requested: requested, delta: run.repoDelta),
               !matched {
                parts.append("commit message mismatch")
            }
        }
        if let proof = run.proofResult {
            if proof.timedOut {
                parts.append("PROOF FAILED (timeout)")
            } else if proof.passed {
                parts.append("proof passed")
            } else if let code = proof.exitCode {
                parts.append("PROOF FAILED (exit \(code))")
            } else {
                parts.append("PROOF FAILED")
            }
        }
        if let suffix = run.workerAnswers.first?.result.reportedTokenUsage?.headlineSuffix {
            parts.append(suffix)
        }
        parts.append(contentsOf: singleWorkerTimingSummary(run, wallMs: wallMs))
        return parts.joined(separator: " · ")
    }

    /// Observed phase clocks for a single executable seat only. Parallel runs stay
    /// identity-only — never subtract phases into an invented orchestration tax or seat blame.
    private static func singleWorkerTimingSummary(_ run: TeamRun, wallMs: Int?) -> [String] {
        let seats = run.workerAnswers.filter { $0.result.status != .skipped }
        guard seats.count == 1, let answer = seats.first else { return [] }
        var parts: [String] = []
        if let queueMs = answer.queueMs { parts.append("queue \(queueMs)ms") }
        if let ttftMs = answer.result.timing.ttftMs { parts.append("ttft \(ttftMs)ms") }
        if let durationMs = answer.result.timing.durationMs { parts.append("duration \(durationMs)ms") }
        if let wallMs { parts.append("wall \(wallMs)ms") }
        return parts
    }

    /// stderr / human footer after a plain `alln run` (not --json).
    public static func cliFooter(_ run: TeamRun) -> String {
        var parts = [
            "run \(run.id)",
            outcomeHeadline(run),
        ]
        if let name = run.teamDisplayName { parts.append(name) }
        if let preset = run.presetId {
            // Default route: preset id is provenance, not the actor — never bare `default_chat`.
            if preset == defaultTeamPresetId {
                parts.append("preset \(preset)")
            } else {
                parts.append(preset)
            }
        }
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
