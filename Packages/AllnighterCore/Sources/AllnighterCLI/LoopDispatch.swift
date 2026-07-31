import Foundation
import AllnighterCore
import AllnighterEngine

/// Shared PM Relay dispatch for CLI + MCP (same engine path, same JSON). Mirrors the
/// old `PairProgrammingDispatch` shape (docs/phases/PM_Relay.md §6 R-S05/R-S06) —
/// that type was deleted at R-S09; this is now the only such dispatch enum.
enum LoopDispatch {
    static func makeCoordinator(runtime: ToolRuntime) -> LoopCoordinator {
        LoopCoordinator(
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
            threadProjector: LoopThreadProjector()
        )
    }

    static func progressJSON(_ event: LoopCoordinator.RelayEvent) -> RelayProgressJSON {
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

    /// One compact, single-line JSON object per progress event — NDJSON (PM_Relay.md
    /// §6 R-S05, works-test hazard #3). `AllnighterCLI.jsonString`/`CoreJSON.encode`
    /// always pretty-prints (multi-line), which is right for the one final envelope
    /// but wrong for a per-event stream; this mirrors the house NDJSON convention
    /// (`NDJSONStreamProjector.encodeLine`'s plain `JSONEncoder` with only
    /// `.sortedKeys`, no `.prettyPrinted`) rather than inventing a second one.
    static func progressJSONLine(_ event: LoopCoordinator.RelayEvent) -> String {
        AllnighterCLI.jsonLine(progressJSON(event))
    }

    static func humanProgressLine(_ event: LoopCoordinator.RelayEvent) -> String {
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

    static func humanLoopSummary(_ json: LoopJSON) -> String {
        var lines = ["relay \(json.relayId): \(json.status) (\(json.rounds) round\(json.rounds == 1 ? "" : "s"))"]
        if let verdict = json.verdict { lines.append("last verdict: \(verdict)") }
        if let note = json.note { lines.append(note) }
        if let stoppedReason = json.stoppedReason { lines.append("stopped: \(stoppedReason)") }
        // QABC-S01: parked-but-running — surface the wake clock and the exact next
        // command so a founder checking in mid-park sees "waiting", not "stuck".
        if let park = json.capacityPark {
            let wake = park.wakeAfter.map { ISO8601DateFormatter().string(from: $0) } ?? "unknown"
            let source = park.source ?? "unknown vendor"
            lines.append("parked on \(source) quota; wakes after \(wake) — no action needed, re-run \(statusCommandHint(json)) to check again")
        }
        return lines.joined(separator: "\n")
    }

    private static func statusCommandHint(_ json: LoopJSON) -> String {
        "alln loop status --relay \(json.relayId)"
    }

    static func humanRoundLog(_ json: LoopJSON) -> String {
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

    /// `--until HH:MM` → next occurrence of that local clock time (today if still
    /// ahead, else tomorrow). Ported from the deleted `PairProgrammingDispatch`
    /// (R-S09) — the relay is now the only caller, so this is its one house parser.
    /// SR-8 (Sol F18): distinguish *absent* from *invalid* `--until`. Absent → `(nil, nil)`
    /// (no deadline, valid). Present-and-well-formed → `(date, nil)`. Present-and-garbage
    /// (`"7am"`, `"25:00"`) → `(nil, raw)` so the caller can reject it loudly like
    /// `--max-rounds`, instead of silently dropping an unattended-run safety ceiling.
    static func parseUntilValidated(_ raw: String?) -> (value: Date?, invalid: String?) {
        guard let raw, !raw.trimmingCharacters(in: .whitespaces).isEmpty else { return (nil, nil) }
        guard let date = parseUntil(raw) else { return (nil, raw) }
        return (date, nil)
    }

    static func parseUntil(_ raw: String?) -> Date? {
        guard let raw else { return nil }
        let parts = raw.split(separator: ":")
        guard parts.count == 2,
              let hour = Int(parts[0]),
              let minute = Int(parts[1]),
              (0..<24).contains(hour),
              (0..<60).contains(minute) else { return nil }
        var calendar = Calendar.current
        calendar.timeZone = .current
        let now = Date()
        var components = calendar.dateComponents([.year, .month, .day], from: now)
        components.hour = hour
        components.minute = minute
        components.second = 0
        guard var deadline = calendar.date(from: components) else { return nil }
        if deadline <= now {
            deadline = calendar.date(byAdding: .day, value: 1, to: deadline) ?? deadline
        }
        return deadline
    }
}
