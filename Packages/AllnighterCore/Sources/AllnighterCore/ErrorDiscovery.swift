import Foundation

/// AE-S07: discovery command + near-match suggestions for identifier errors.
public enum ErrorDiscovery {
    /// Discovery command for a `*_NOT_FOUND` / `*_NOT_AVAILABLE` code.
    /// Prefer catalog/list discovery over `alln doctor` for noun lookup
    /// (`SOURCE_NOT_FOUND` is the exception — sources live on doctor).
    public static func discoveryCommand(forErrorCode code: String, lane: String? = nil) -> String? {
        let laneFlag = lane.map { " --lane \($0)" } ?? ""
        switch code {
        case "TEAM_NOT_FOUND":
            // MR-S04: menu is the selection truth; teams list remains a domain projection.
            return "alln menu --json"
        case "SKILL_NOT_FOUND":
            return "alln skills\(laneFlag) --json"
        case "MODEL_NOT_FOUND", "WORKER_NOT_AVAILABLE":
            return "alln menu --json"
        case "PROJECT_NOT_FOUND":
            return "alln project list --json"
        case "RUN_NOT_FOUND":
            return "alln history --json"
        case "THREAD_NOT_FOUND":
            return "alln project threads --json"
        case "SOURCE_NOT_FOUND":
            return "alln doctor --json"
        case "OWNERSHIP_NOT_FOUND":
            return "alln ps --json"
        case "STALL_EPISODE_NOT_FOUND":
            return "alln stalled list --all --json"
        case "RELAY_NOT_FOUND":
            return "alln pair relay-status --json"
        case "PANEL_NOT_FOUND":
            return "alln panel status --json"
        default:
            return nil
        }
    }

    public static func nextAction(forErrorCode code: String, lane: String? = nil) -> AgentNextAction? {
        guard let command = discoveryCommand(forErrorCode: code, lane: lane) else { return nil }
        return AgentNextAction(
            kind: "discover",
            label: "List valid \(noun(for: code)) values",
            command: command
        )
    }

    /// Top-N near matches by edit distance (typo / near-miss only).
    public static func nearestMatches(to query: String, in candidates: [String], limit: Int = 3) -> [String] {
        guard !candidates.isEmpty, limit > 0, !query.isEmpty else { return [] }
        let scored = candidates.map { ($0, CLIUsage.editDistance(query.lowercased(), $0.lowercased())) }
            .sorted { lhs, rhs in
                if lhs.1 != rhs.1 { return lhs.1 < rhs.1 }
                return lhs.0 < rhs.0
            }
        let maxDist = max(2, query.count / 2)
        return scored.filter { $0.1 <= maxDist && $0.1 > 0 }.prefix(limit).map(\.0)
    }

    public static func messageWithSuggestions(_ base: String, suggestions: [String]) -> String {
        guard !suggestions.isEmpty else { return base }
        return base + "; did you mean: " + suggestions.joined(separator: ", ")
    }

    private static func noun(for code: String) -> String {
        switch code {
        case "TEAM_NOT_FOUND": return "team"
        case "SKILL_NOT_FOUND": return "skill"
        case "MODEL_NOT_FOUND", "WORKER_NOT_AVAILABLE": return "model"
        case "PROJECT_NOT_FOUND": return "project"
        case "RUN_NOT_FOUND": return "run"
        case "THREAD_NOT_FOUND": return "thread"
        default: return "id"
        }
    }
}
