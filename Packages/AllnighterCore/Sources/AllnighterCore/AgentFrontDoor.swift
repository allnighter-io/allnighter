import Foundation

/// Shared counsel for agent first-contact surfaces (docs/phases/Agent_Front_Door.md §F3).
/// Empty machine output must never be silent — always name what's missing and the next command.
public struct AgentSurfaceNextAction: Codable, Sendable, Equatable {
    public var kind: String
    public var label: String
    public var command: String

    public init(kind: String, label: String, command: String) {
        self.kind = kind; self.label = label; self.command = command
    }
}

public enum AgentFrontDoor {
    public static let doctorFirst = AgentSurfaceNextAction(
        kind: "runDoctor", label: "Check setup and sources", command: "alln doctor --json")

    /// Prefer the intent resolver over a bare catalog browse when an agent is
    /// hunting by natural-language model/team name (AE-S14).
    public static let routeFirst = AgentSurfaceNextAction(
        kind: "routeIntent",
        label: "Resolve intent to a ready model or team",
        command: "alln route --for \"<intent>\" --json")

    public static func emptyModelsCounsel(
        benchOnly: Bool,
        driverId: String?,
        catalogCount: Int
    ) -> (counsel: String, nextActions: [AgentSurfaceNextAction]) {
        let reason: String
        if let driverId {
            reason = "No models match driver '\(driverId)' in the catalog."
        } else if benchOnly {
            reason = catalogCount == 0
                ? "No models are on the Bench yet."
                : "No on-Bench models match the current filter."
        } else {
            reason = "No models are configured on this machine."
        }
        let counsel = "\(reason) Looking for a model by name (Sonnet, Grok, Sol)? Run `alln route --for \"<intent>\" --json` — do not stop at an empty models list. Then `alln doctor --json` if sources look down."
        return (counsel, [routeFirst, doctorFirst])
    }

    public static func emptyTeamsCounsel() -> (counsel: String, nextActions: [AgentSurfaceNextAction]) {
        let counsel = "No active teams are visible. Looking for a team by intent? Run `alln route --for \"<intent>\" --json`. Otherwise `alln doctor --json` to confirm the bench and sources."
        return (counsel, [routeFirst, doctorFirst])
    }

    public static func missingConfigCounsel() -> (counsel: String, nextActions: [AgentSurfaceNextAction]) {
        let counsel = "Allnighter config directory is missing or not writable. Run `alln doctor --json` for the fix path."
        return (counsel, [doctorFirst])
    }
}
