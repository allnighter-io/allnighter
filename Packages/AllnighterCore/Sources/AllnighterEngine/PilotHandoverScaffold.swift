import Foundation
import AllnighterCore

/// Suggested PM handover scaffold for Pilot (`Pilot_DX.md §DX4`). Sections are
/// markdown comments — suggestions only; the gate/parser accepts any prose.
public enum PilotHandoverScaffold {
    public static func template(round: Int) -> String {
        """
        # PM handover — round \(round)

        <!-- goal: what this round should accomplish -->
        
        <!-- out of scope: what the dev must NOT do this round -->
        
        <!-- pointers: spec paths, code areas, prior round context -->
        
        <!-- proof required: commands or outputs the dev must capture -->
        
        <!-- stop conditions: when to escalate or stop early -->
        
        """
    }

    /// Writes `round<N>.md` into the relay's state folder (`RelayStateStore` directory).
    public static func writeRoundFile(
        relayId: String,
        round: Int = 1,
        stateStore: RelayStateStore = RelayStateStore()
    ) throws -> String {
        let directory = stateStore.rootDirectory
            .appendingPathComponent(relayId, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("round\(round).md")
        try template(round: round).write(to: url, atomically: true, encoding: .utf8)
        return url.path
    }
}
