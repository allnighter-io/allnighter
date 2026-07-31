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
        
        <!-- memory: if MEMORY.md exists at repo root, point dev at relevant lines; dev reads it before anything else and cites honored lines in report -->
        
        <!-- proof required: commands or outputs the dev must capture -->
        
        <!-- stop conditions: when to escalate or stop early -->
        
        """
    }

    /// Writes `round<N>.md` into the relay's state folder (`LoopStateStore` directory).
    public static func writeRoundFile(
        loopId: String,
        round: Int = 1,
        stateStore: LoopStateStore = LoopStateStore()
    ) throws -> String {
        let directory = stateStore.rootDirectory
            .appendingPathComponent(loopId, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("round\(round).md")
        try template(round: round).write(to: url, atomically: true, encoding: .utf8)
        return url.path
    }
}
