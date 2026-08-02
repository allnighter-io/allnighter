import Foundation
import AllnighterCore
import AllnighterEngine

/// Shared free-twin helpers for `loop resume` / `loop step` / `loop pm` `--dry-run`
/// (LOOP-TWIN). Pure resolve + report — never mutates durable state.
enum LoopDryRunSupport {
    /// Advisory write-lock probe for dry-run warnings. Read-only; does not take the lock.
    static func writeLockWarning(projectRoot: String) async -> String? {
        guard !projectRoot.isEmpty else { return nil }
        let key = RunWriteLock.key(repoRoot: projectRoot)
        let held = await ExecutionLaneRegistry.shared.isHeld(key)
        guard held else { return nil }
        return "write lock is held on \(projectRoot) — a real dispatch may queue behind the holder"
    }

    static func resumeCommand(loopId: String, answer: String, maxRounds: String?, until: String?) -> String {
        var command = "alln loop resume \(loopId) --answer \"\(answer)\""
        if let maxRounds { command += " --max-rounds \(maxRounds)" }
        if let until { command += " --until \(until)" }
        return command
    }

    static func stepCommand(loopId: String, message: String?, doneSummary: String?) -> String {
        if let doneSummary {
            return "alln loop step \(loopId) --done \"\(doneSummary)\""
        }
        let body = message ?? "<message>"
        return "alln loop step \(loopId) \"\(body)\""
    }

    static func pmCommand(loopId: String, occupant: String, maxRounds: String?, until: String?) -> String {
        var command = "alln loop pm \(loopId) \(occupant)"
        if let maxRounds { command += " --max-rounds \(maxRounds)" }
        if let until { command += " --until \(until)" }
        return command
    }

    static func seatOccupant(from state: LoopState) -> (pm: String, dev: String) {
        (state.isCallerChair ? "caller" : state.pmModelId, state.devModelId)
    }
}
