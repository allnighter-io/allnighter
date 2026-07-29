import Foundation
import AgentOSTeam

/// Replay grammar for artifact footers and legacy show/export paths — always `alln run`.
public enum TeamRunReplayCommand {
  /// ADP-S01 — round-trips every explicit selector: the prompt, `--team`, each
  /// explicit `--model`, `--effort`, `--lane` (only when it was explicit context
  /// alongside a pinned worker), and `--no-commit` when ordered.
  public static func build(from run: TeamRun) -> String {
    var parts = ["alln run"]
    if !run.prompt.isEmpty {
      parts.append("\"\(run.prompt)\"")
    }
    if let team = run.presetId { parts.append("--team \(team)") }
    for worker in run.explicitModelIds ?? [] where !worker.isEmpty {
      parts.append("--model \(worker)")
    }
    for seat in run.explicitSeatModelIds ?? [] where !seat.isEmpty {
      parts.append("--seat \(seat)")
    }
    if let effort = run.effort { parts.append("--effort \(effort.rawValue)") }
    if run.laneContextOnly == true, let lane = run.lane {
      parts.append("--lane \(lane.rawValue)")
    }
    if run.noCommitOrdered == true { parts.append("--no-commit") }
    return parts.joined(separator: " ")
  }
}
