import Foundation
import AllnighterCore
import AllnighterEngine

/// Shared PM Relay dispatch for CLI + MCP (same engine path, same JSON). Mirrors
/// `PairProgrammingDispatch` (docs/phases/PM_Relay.md §6 R-S05/R-S06).
enum RelayDispatch {
    static func makeCoordinator(runtime: ToolRuntime) -> RelayCoordinator {
        RelayCoordinator(
            runService: RunService(
                models: runtime.models,
                registry: runtime.registry,
                teams: runtime.teams,
                invocations: runtime.invocations
            ),
            // R-S07: real relays (CLI + MCP both dispatch through here) always project
            // into the inbox — default `ThreadStore()`/`RunStore()` roots, same as
            // `RunService`'s own default `RunStore()`, so the projector reads back the
            // exact runs this coordinator just dispatched.
            threadProjector: RelayThreadProjector()
        )
    }

    static func progressJSON(_ event: RelayCoordinator.RelayEvent) -> RelayProgressJSON {
        switch event {
        case .roundStarted(let round):
            return RelayProgressJSON(contractVersion: ContractRegistry.contractVersion, event: "roundStarted", round: round)
        case .pmTurnFinished(let round, let verdict):
            return RelayProgressJSON(contractVersion: ContractRegistry.contractVersion, event: "pmTurnFinished", round: round, verdict: verdict.rawValue)
        case .gateBlocked(let round, let dangerClass, let reason):
            return RelayProgressJSON(contractVersion: ContractRegistry.contractVersion, event: "gateBlocked", round: round, dangerClass: dangerClass, reason: reason)
        case .devTurnFinished(let round):
            return RelayProgressJSON(contractVersion: ContractRegistry.contractVersion, event: "devTurnFinished", round: round)
        case .escalated(let note):
            return RelayProgressJSON(contractVersion: ContractRegistry.contractVersion, event: "escalated", note: note)
        case .done(let note):
            return RelayProgressJSON(contractVersion: ContractRegistry.contractVersion, event: "done", note: note)
        case .stopped(let reason):
            return RelayProgressJSON(contractVersion: ContractRegistry.contractVersion, event: "stopped", reason: reason)
        }
    }

    static func humanProgressLine(_ event: RelayCoordinator.RelayEvent) -> String {
        switch event {
        case .roundStarted(let round):
            return "round \(round) starting…"
        case .pmTurnFinished(let round, let verdict):
            return "round \(round): PM verdict \(verdict.rawValue)"
        case .gateBlocked(let round, let dangerClass, let reason):
            return "round \(round): HandoverGate blocked (\(dangerClass)) — \(reason)"
        case .devTurnFinished(let round):
            return "round \(round): dev turn finished"
        case .escalated(let note):
            return "escalated: \(note)"
        case .done(let note):
            return "done: \(note ?? "(no closing note)")"
        case .stopped(let reason):
            return "stopped: \(reason)"
        }
    }

    static func humanRelaySummary(_ json: RelayJSON) -> String {
        var lines = ["relay \(json.relayId): \(json.status) (\(json.rounds) round\(json.rounds == 1 ? "" : "s"))"]
        if let verdict = json.verdict { lines.append("last verdict: \(verdict)") }
        if let note = json.note { lines.append(note) }
        if let stoppedReason = json.stoppedReason { lines.append("stopped: \(stoppedReason)") }
        return lines.joined(separator: "\n")
    }

    static func humanRoundLog(_ json: RelayJSON) -> String {
        json.roundLog.map { round in
            var parts = ["round \(round.round)"]
            if let verdict = round.verdict { parts.append(verdict) }
            if let baseline = round.baseline, let head = round.head { parts.append("\(baseline.prefix(8))..\(head.prefix(8))") }
            if let pmRunId = round.pmRunId { parts.append("pm \(pmRunId)") }
            if let devRunId = round.devRunId { parts.append("dev \(devRunId)") }
            if let gate = round.gate, !gate.allowed { parts.append("GATE BLOCKED (\(gate.dangerClass ?? "?"))") }
            return parts.joined(separator: " · ")
        }.joined(separator: "\n")
    }

    /// `--until HH:MM` reuses the pair-programming parser — one house parser, not a
    /// second copy.
    static func parseUntil(_ raw: String?) -> Date? {
        PairProgrammingDispatch.parseUntil(raw)
    }
}
