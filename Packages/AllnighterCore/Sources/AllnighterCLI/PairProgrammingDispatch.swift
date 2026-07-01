import Foundation
import AllnighterCore
import AllnighterEngine

/// Shared pair-programming dispatch for CLI + MCP (same engine path, same JSON).
enum PairProgrammingDispatch {
    static func seats(plannerWorker: String?, executorWorker: String?) -> PairCoordinator.Seats {
        PairCoordinator.Seats(
            plannerWorkerId: plannerWorker ?? PairCoordinator.Seats.testDefaults.plannerWorkerId,
            executorWorkerId: executorWorker ?? PairCoordinator.Seats.testDefaults.executorWorkerId
        )
    }

    static func parsePacket(path: String?) throws -> WorkSlicePacket {
        guard let path else { throw PairProgrammingDispatchError.packetRequired }
        return try WorkSlicePacketParser.parseFile(at: path)
    }

    static func parsePacket(inline: Any?) throws -> WorkSlicePacket {
        guard let inline else { throw PairProgrammingDispatchError.packetRequired }
        let data = try JSONSerialization.data(withJSONObject: inline)
        return try CoreJSON.decode(WorkSlicePacket.self, from: data)
    }

    static func makeCoordinator(runtime: ToolRuntime) -> PairCoordinator {
        PairCoordinator(
            runService: RunService(
                models: runtime.models,
                registry: runtime.registry,
                teams: runtime.teams,
                invocations: runtime.invocations
            ),
            checkRunner: CheckRunner(commandRunner: SubprocessCommandRunner(environmentPolicy: AllnighterSpawnEnvironmentPolicy()))
        )
    }

    static func sliceJSON(_ outcome: PairCoordinator.Outcome) -> PairSliceJSON {
        let status: String
        if !outcome.gate.isAllowed {
            status = "blocked"
        } else if outcome.terminal == .passed {
            status = "passed"
        } else {
            status = outcome.terminal?.rawValue ?? "failed"
        }
        return PairSliceJSON(
            contractVersion: ContractRegistry.contractVersion,
            sliceId: outcome.packet.sliceId,
            status: status,
            gate: .from(outcome.gate),
            check: outcome.check.map {
                PairSliceJSON.Check(
                    exitCode: $0.exitCode.map(Int.init),
                    stdoutTail: $0.stdoutTail.isEmpty ? nil : $0.stdoutTail,
                    timedOut: $0.timedOut
                )
            },
            parentRunId: outcome.parentRun?.id,
            childRunId: outcome.childRun?.id,
            plannerWorkerId: outcome.seats.plannerWorkerId,
            executorWorkerId: outcome.seats.executorWorkerId
        )
    }

    static func queueJSON(_ outcome: PairCoordinator.QueueOutcome) -> PairQueueJSON {
        PairQueueJSON(
            contractVersion: ContractRegistry.contractVersion,
            passed: outcome.passed,
            plannerResolved: outcome.plannerResolved,
            escalated: outcome.escalated,
            stoppedReason: outcome.stoppedReason,
            slices: outcome.entries.map {
                PairQueueJSON.SliceResult(
                    sliceId: $0.packet.sliceId,
                    status: $0.status.rawValue,
                    checkExitCode: $0.checkExitCode.map(Int.init),
                    childRunId: $0.childRunId,
                    escalatedReason: $0.escalatedReason,
                    resolvedBy: $0.resolvedBy,
                    plannerRunId: $0.plannerRunId,
                    executorAttempts: $0.retries > 0 ? $0.retries : nil
                )
            }
        )
    }

    static func progressJSON(_ event: PairQueueProgressEvent) -> PairQueueProgressJSON {
        switch event {
        case .sliceRunning(let sliceId):
            return PairQueueProgressJSON(
                contractVersion: ContractRegistry.contractVersion,
                event: "sliceRunning",
                sliceId: sliceId
            )
        case .sliceFinished(let sliceId, let status, let elapsed):
            return PairQueueProgressJSON(
                contractVersion: ContractRegistry.contractVersion,
                event: "sliceFinished",
                sliceId: sliceId,
                status: status,
                elapsedSeconds: elapsed
            )
        }
    }

    static func humanProgressLine(_ event: PairQueueProgressEvent) -> String {
        switch event {
        case .sliceRunning(let sliceId):
            return "\(sliceId) running…"
        case .sliceFinished(let sliceId, let status, let elapsed):
            let mins = elapsed / 60
            let secs = elapsed % 60
            let duration = mins > 0 ? "\(mins)m\(secs)s" : "\(secs)s"
            return "\(sliceId) \(status) (\(duration))"
        }
    }

    static func loadQueue(at queueDir: URL) throws -> SliceQueue {
        let queueStore = SliceQueueStore(rootDirectory: queueDir)
        if FileManager.default.fileExists(atPath: queueStore.rootDirectory.appendingPathComponent("queue.json").path) {
            return try queueStore.load()
        }
        return try SliceQueueStore.bootstrapQueue(from: queueDir)
    }

    static func humanSliceSummary(_ json: PairSliceJSON) -> String {
        var lines = ["slice \(json.sliceId): \(json.status)"]
        if let check = json.check, let code = check.exitCode { lines.append("check exit \(code)") }
        if let child = json.childRunId { lines.append("child run \(child)") }
        return lines.joined(separator: "\n")
    }

    static func humanStatusSummary(_ status: PairStatusJSON) -> String {
        status.entries.map { entry in
            var line = "\(entry.sliceId): \(entry.status)"
            if let elapsed = entry.elapsedSeconds { line += " (\(elapsed)s)" }
            if let child = entry.childRunId { line += " · run \(child)" }
            line += " — \(entry.guidance)"
            return line
        }.joined(separator: "\n")
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

enum PairProgrammingDispatchError: Error, Equatable {
    case packetRequired
    case queueRequired
}
