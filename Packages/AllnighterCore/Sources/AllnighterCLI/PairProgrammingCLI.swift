import Foundation
import AllnighterCore
import AllnighterEngine

/// `alln pair slice`, `pair run`, and `pair status` — pair-programming control plane (device pairing stays in PairCLI).
enum PairProgrammingCLI {
    private static func seats(from opts: Options) -> PairCoordinator.Seats {
        PairProgrammingDispatch.seats(
            plannerWorker: opts.value("planner-worker"),
            executorWorker: opts.value("executor-worker")
        )
    }

    static func runSlice(_ args: [String], runtime: ToolRuntime) async {
        let opts = Options(args)
        guard let packetPath = opts.positional.first else {
            usage("slice <packet-path> --project <id|path> [--executor <teamId>] [--planner-worker <modelId>] [--executor-worker <modelId>] [--json]")
        }
        guard let projectToken = opts.value("project") else {
            AllnighterCLI.fail(code: "CLI_USAGE_ERROR", message: "--project <id|path> required")
        }

        let packet: WorkSlicePacket
        do {
            packet = try PairProgrammingDispatch.parsePacket(path: packetPath)
        } catch {
            AllnighterCLI.fail(code: "CLI_USAGE_ERROR", message: String(describing: error))
        }

        let store = ProjectStore()
        guard let project = AllnighterCLI.resolveProject(projectToken, store: store) else {
            AllnighterCLI.fail(code: "PROJECT_NOT_FOUND", message: "project not found: \(projectToken)")
        }

        let coordinator = PairProgrammingDispatch.makeCoordinator(runtime: runtime)
        let executorId = opts.value("executor") ?? PairCoordinator.defaultExecutorTeamId
        let result = await coordinator.runSlice(
            packet: packet,
            repoRoot: project.normalizedRootPath,
            projectId: project.id,
            executorTeamId: executorId,
            origin: .cli,
            seats: seats(from: opts)
        )

        switch result {
        case .failure(let error):
            AllnighterCLI.emitFailure(code: error.code, message: error.description)
            exit(1)
        case .success(let outcome):
            let json = PairProgrammingDispatch.sliceJSON(outcome)
            if opts.flag("json") {
                print(AllnighterCLI.jsonString(json))
            } else {
                print(PairProgrammingDispatch.humanSliceSummary(json))
            }
            if outcome.gate.isAllowed == false || outcome.terminal != .passed { exit(1) }
        }
    }

    static func runQueue(_ args: [String], runtime: ToolRuntime) async {
        let opts = Options(args)
        guard let queuePath = opts.value("queue") ?? opts.positional.first else {
            usage("run --queue <dir> --project <id|path> [--until HH:MM] [--max-retries N] [--executor-attempts N] [--executor <teamId>] [--planner-worker <modelId>] [--executor-worker <modelId>] [--verbose] [--json]")
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
            queue = try PairProgrammingDispatch.loadQueue(at: queueDir)
        } catch {
            AllnighterCLI.fail(code: "CLI_USAGE_ERROR", message: String(describing: error))
        }

        let emitJSON = opts.flag("json")
        let verboseURL: URL? = opts.flag("verbose")
            ? queueDir.appendingPathComponent("pair-verbose.log")
            : nil
        if let verboseURL, !emitJSON {
            print("verbose log: \(verboseURL.path)")
        }

        let coordinator = PairProgrammingDispatch.makeCoordinator(runtime: runtime)
        let executorAttempts = opts.value("executor-attempts").flatMap(Int.init) ?? 3
        let options = PairCoordinator.QueueOptions(
            until: PairProgrammingDispatch.parseUntil(opts.value("until")),
            maxRetries: opts.value("max-retries").flatMap(Int.init),
            executorAttemptsBeforePlanner: executorAttempts,
            executorTeamId: opts.value("executor") ?? PairCoordinator.defaultExecutorTeamId,
            seats: seats(from: opts),
            onProgress: { event in
                if emitJSON {
                    print(AllnighterCLI.jsonString(PairProgrammingDispatch.progressJSON(event)))
                } else {
                    print(PairProgrammingDispatch.humanProgressLine(event))
                }
            },
            verboseLogURL: verboseURL
        )
        let outcome = await coordinator.runQueue(
            queue: &queue,
            store: queueStore,
            repoRoot: project.normalizedRootPath,
            projectId: project.id,
            options: options,
            origin: .cli
        )

        let json = PairProgrammingDispatch.queueJSON(outcome)
        if emitJSON {
            print(AllnighterCLI.jsonString(json))
        } else {
            print("passed \(outcome.passed) · planner \(outcome.plannerResolved) · escalated \(outcome.escalated)")
            if let reason = outcome.stoppedReason { print("stopped: \(reason)") }
        }
        if outcome.escalated > 0 { exit(1) }
    }

    static func runStatus(_ args: [String], runtime: ToolRuntime) async {
        let opts = Options(args)
        guard let queuePath = opts.value("queue") ?? opts.positional.first else {
            usage("status --queue <dir> [--json]")
        }

        let queueDir = URL(fileURLWithPath: (queuePath as NSString).expandingTildeInPath, isDirectory: true)
        let queue: SliceQueue
        do {
            queue = try PairProgrammingDispatch.loadQueue(at: queueDir)
        } catch {
            AllnighterCLI.fail(code: "CLI_USAGE_ERROR", message: String(describing: error))
        }

        let coordinator = PairProgrammingDispatch.makeCoordinator(runtime: runtime)
        let status = coordinator.queueStatus(queue: queue, queuePath: queueDir.path)
        if opts.flag("json") {
            print(AllnighterCLI.jsonString(status))
        } else {
            print(PairProgrammingDispatch.humanStatusSummary(status))
        }
    }

    private static func usage(_ detail: String) -> Never {
        FileHandle.standardError.write(Data("usage: alln pair \(detail)\n".utf8))
        exit(2)
    }
}
