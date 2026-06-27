import Foundation
import AllnighterCore
import AllnighterEngine

/// `alln pair slice` and `alln pair run` — pair-programming control plane (device pairing stays in PairCLI).
enum PairProgrammingCLI {
    static func runSlice(_ args: [String], runtime: ToolRuntime) async {
        let opts = Options(args)
        guard let packetPath = opts.positional.first else {
            usage("slice <packet-path> --project <id|path> [--executor <teamId>] [--json]")
        }
        guard let projectToken = opts.value("project") else {
            AllnighterCLI.fail(code: "CLI_USAGE_ERROR", message: "--project <id|path> required")
        }

        let packet: WorkSlicePacket
        do {
            packet = try WorkSlicePacketParser.parseFile(at: packetPath)
        } catch {
            AllnighterCLI.fail(code: "CLI_USAGE_ERROR", message: String(describing: error))
        }

        let store = ProjectStore()
        guard let project = AllnighterCLI.resolveProject(projectToken, store: store) else {
            AllnighterCLI.fail(code: "PROJECT_NOT_FOUND", message: "project not found: \(projectToken)")
        }

        let service = makeRunService(runtime: runtime)
        let coordinator = PairCoordinator(
            runService: service,
            checkRunner: CheckRunner(commandRunner: SubprocessCommandRunner())
        )
        let executorId = opts.value("executor") ?? PairCoordinator.defaultExecutorTeamId
        let result = await coordinator.runSlice(
            packet: packet,
            repoRoot: project.normalizedRootPath,
            projectId: project.id,
            executorTeamId: executorId,
            origin: .cli
        )

        switch result {
        case .failure(let error):
            AllnighterCLI.emitFailure(code: error.code, message: error.description)
            exit(1)
        case .success(let outcome):
            let json = sliceJSON(outcome)
            if opts.flag("json") {
                print(AllnighterCLI.jsonString(json))
            } else {
                print(humanSliceSummary(json))
            }
            if outcome.gate.isAllowed == false || outcome.terminal != .passed { exit(1) }
        }
    }

    static func runQueue(_ args: [String], runtime: ToolRuntime) async {
        let opts = Options(args)
        guard let queuePath = opts.value("queue") ?? opts.positional.first else {
            usage("run --queue <dir> --project <id|path> [--until HH:MM] [--max-retries N] [--executor <teamId>] [--json]")
        }
        guard let projectToken = opts.value("project") else {
            AllnighterCLI.fail(code: "CLI_USAGE_ERROR", message: "--project <id|path> required")
        }

        let store = ProjectStore()
        guard let project = AllnighterCLI.resolveProject(projectToken, store: store) else {
            AllnighterCLI.fail(code: "PROJECT_NOT_FOUND", message: "project not found: \(projectToken)")
        }

        let queueDir = URL(fileURLWithPath: (queuePath as NSString).expandingTildeInPath, isDirectory: true)
        var queue: SliceQueue
        let queueStore = SliceQueueStore(rootDirectory: queueDir)
        do {
            if FileManager.default.fileExists(atPath: queueStore.rootDirectory.appendingPathComponent("queue.json").path) {
                queue = try queueStore.load()
            } else {
                queue = try SliceQueueStore.bootstrapQueue(from: queueDir)
                try queueStore.save(queue)
            }
        } catch {
            AllnighterCLI.fail(code: "CLI_USAGE_ERROR", message: String(describing: error))
        }

        let service = makeRunService(runtime: runtime)
        let coordinator = PairCoordinator(
            runService: service,
            checkRunner: CheckRunner(commandRunner: SubprocessCommandRunner())
        )
        let options = PairCoordinator.QueueOptions(
            until: parseUntil(opts.value("until")),
            maxRetries: opts.value("max-retries").flatMap(Int.init),
            executorTeamId: opts.value("executor") ?? PairCoordinator.defaultExecutorTeamId
        )
        let outcome = await coordinator.runQueue(
            queue: &queue,
            store: queueStore,
            repoRoot: project.normalizedRootPath,
            projectId: project.id,
            options: options,
            origin: .cli
        )

        let json = queueJSON(outcome)
        if opts.flag("json") {
            print(AllnighterCLI.jsonString(json))
        } else {
            print("passed \(outcome.passed) · escalated \(outcome.escalated)")
            if let reason = outcome.stoppedReason { print("stopped: \(reason)") }
        }
        if outcome.escalated > 0 { exit(1) }
    }

    private static func makeRunService(runtime: ToolRuntime) -> RunService {
        RunService(
            models: runtime.models,
            registry: runtime.registry,
            teams: runtime.teams,
            invocations: runtime.invocations
        )
    }

    private static func sliceJSON(_ outcome: PairCoordinator.Outcome) -> PairSliceJSON {
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
            childRunId: outcome.childRun?.id
        )
    }

    private static func queueJSON(_ outcome: PairCoordinator.QueueOutcome) -> PairQueueJSON {
        PairQueueJSON(
            contractVersion: ContractRegistry.contractVersion,
            passed: outcome.passed,
            escalated: outcome.escalated,
            stoppedReason: outcome.stoppedReason,
            slices: outcome.entries.map {
                PairQueueJSON.SliceResult(
                    sliceId: $0.packet.sliceId,
                    status: $0.status.rawValue,
                    checkExitCode: $0.checkExitCode.map(Int.init),
                    childRunId: $0.childRunId,
                    escalatedReason: $0.escalatedReason
                )
            }
        )
    }

    private static func humanSliceSummary(_ json: PairSliceJSON) -> String {
        var lines = ["slice \(json.sliceId): \(json.status)"]
        if let check = json.check, let code = check.exitCode {
            lines.append("check exit \(code)")
        }
        if let child = json.childRunId { lines.append("child run \(child)") }
        return lines.joined(separator: "\n")
    }

    private static func parseUntil(_ raw: String?) -> Date? {
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

    private static func usage(_ detail: String) -> Never {
        FileHandle.standardError.write(Data("usage: alln pair \(detail)\n".utf8))
        exit(2)
    }
}
