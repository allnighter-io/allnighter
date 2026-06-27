import Foundation
import AllnighterCore
import AllnighterEngine

/// MCP `pair_slice` / `pair_run` — pair-programming control plane (Pair_Programming_Team).
enum MCPPairHandlers {
    enum Outcome: Sendable {
        case success(String, summary: String)
        case toolError(ErrorEnvelope)
    }

    static func slice(runtime: ToolRuntime, args: [String: Any]) async -> Outcome {
        let packet: WorkSlicePacket
        if let inline = args["packet"] {
            do {
                packet = try PairProgrammingDispatch.parsePacket(inline: inline)
            } catch {
                return .toolError(ErrorEnvelope(
                    code: "PAIR_SLICE_PACKET_MISSING",
                    message: "packet or packetPath required",
                    requiresManual: true,
                    retryable: false))
            }
        } else if let path = args["packetPath"] as? String {
            do {
                packet = try PairProgrammingDispatch.parsePacket(path: path)
            } catch {
                return .toolError(ErrorEnvelope(
                    code: "PAIR_SLICE_PACKET_MISSING",
                    message: String(describing: error),
                    requiresManual: true,
                    retryable: false))
            }
        } else {
            return .toolError(ErrorEnvelope(
                code: "PAIR_SLICE_PACKET_MISSING",
                message: "packet or packetPath required",
                requiresManual: true,
                retryable: false))
        }

        guard let projectToken = args["project"] as? String, !projectToken.isEmpty else {
            return .toolError(ErrorEnvelope(
                code: "CLI_USAGE_ERROR", message: "project required",
                requiresManual: true, retryable: false))
        }
        let store = ProjectStore()
        guard let project = AllnighterCLI.resolveProject(projectToken, store: store) else {
            return .toolError(ErrorEnvelope(
                code: "PROJECT_NOT_FOUND", message: "project not found: \(projectToken)",
                requiresManual: true, retryable: false))
        }

        let seats = PairProgrammingDispatch.seats(
            plannerWorker: args["plannerWorker"] as? String,
            executorWorker: args["executorWorker"] as? String
        )
        let executorTeamId = (args["executor"] as? String) ?? PairCoordinator.defaultExecutorTeamId
        let coordinator = PairProgrammingDispatch.makeCoordinator(runtime: runtime)
        let result = await coordinator.runSlice(
            packet: packet,
            repoRoot: project.normalizedRootPath,
            projectId: project.id,
            executorTeamId: executorTeamId,
            origin: .mcp,
            seats: seats
        )

        switch result {
        case .failure(let error):
            return .toolError(ErrorEnvelope(
                code: error.code, message: error.description,
                requiresManual: error.code != "RUN_WRITE_LOCK_BUSY",
                retryable: error.code == "RUN_WRITE_LOCK_BUSY"))
        case .success(let outcome):
            let json = PairProgrammingDispatch.sliceJSON(outcome)
            let encoded = AllnighterCLI.jsonString(json)
            return .success(encoded, summary: PairProgrammingDispatch.humanSliceSummary(json))
        }
    }

    static func run(runtime: ToolRuntime, args: [String: Any]) async -> Outcome {
        guard let queuePath = args["queueDir"] as? String, !queuePath.isEmpty else {
            return .toolError(ErrorEnvelope(
                code: "CLI_USAGE_ERROR", message: "queueDir required",
                requiresManual: true, retryable: false))
        }
        guard let projectToken = args["project"] as? String, !projectToken.isEmpty else {
            return .toolError(ErrorEnvelope(
                code: "CLI_USAGE_ERROR", message: "project required",
                requiresManual: true, retryable: false))
        }
        let store = ProjectStore()
        guard let project = AllnighterCLI.resolveProject(projectToken, store: store) else {
            return .toolError(ErrorEnvelope(
                code: "PROJECT_NOT_FOUND", message: "project not found: \(projectToken)",
                requiresManual: true, retryable: false))
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
            return .toolError(ErrorEnvelope(
                code: "CLI_USAGE_ERROR", message: String(describing: error),
                requiresManual: true, retryable: false))
        }

        let seats = PairProgrammingDispatch.seats(
            plannerWorker: args["plannerWorker"] as? String,
            executorWorker: args["executorWorker"] as? String
        )
        let maxRetries: Int? = {
            if let n = args["maxRetries"] as? Int { return n }
            if let s = args["maxRetries"] as? String { return Int(s) }
            return nil
        }()
        let executorAttempts: Int? = {
            if let n = args["executorAttemptsBeforePlanner"] as? Int { return n }
            if let s = args["executorAttemptsBeforePlanner"] as? String { return Int(s) }
            return nil
        }()
        let options = PairCoordinator.QueueOptions(
            until: PairProgrammingDispatch.parseUntil(args["until"] as? String),
            maxRetries: maxRetries,
            executorAttemptsBeforePlanner: executorAttempts ?? 3,
            executorTeamId: (args["executor"] as? String) ?? PairCoordinator.defaultExecutorTeamId,
            seats: seats
        )
        let coordinator = PairProgrammingDispatch.makeCoordinator(runtime: runtime)
        let outcome = await coordinator.runQueue(
            queue: &queue,
            store: queueStore,
            repoRoot: project.normalizedRootPath,
            projectId: project.id,
            options: options,
            origin: .mcp
        )

        let json = PairProgrammingDispatch.queueJSON(outcome)
        let encoded = AllnighterCLI.jsonString(json)
        let summary = "passed \(outcome.passed) · planner \(outcome.plannerResolved) · escalated \(outcome.escalated)"
        return .success(encoded, summary: summary)
    }

    static func status(runtime: ToolRuntime, args: [String: Any]) async -> Outcome {
        guard let queuePath = args["queueDir"] as? String, !queuePath.isEmpty else {
            return .toolError(ErrorEnvelope(
                code: "CLI_USAGE_ERROR", message: "queueDir required",
                requiresManual: true, retryable: false))
        }
        let queueDir = URL(fileURLWithPath: (queuePath as NSString).expandingTildeInPath, isDirectory: true)
        let queue: SliceQueue
        do {
            queue = try PairProgrammingDispatch.loadQueue(at: queueDir)
        } catch {
            return .toolError(ErrorEnvelope(
                code: "CLI_USAGE_ERROR", message: String(describing: error),
                requiresManual: true, retryable: false))
        }
        let coordinator = PairProgrammingDispatch.makeCoordinator(runtime: runtime)
        let status = coordinator.queueStatus(queue: queue, queuePath: queueDir.path)
        let encoded = AllnighterCLI.jsonString(status)
        let running = status.entries.filter { $0.status == "running" }.count
        let summary = running > 0
            ? "\(running) slice(s) in progress — check queue.json"
            : "queue idle or complete (\(status.entries.count) entries)"
        return .success(encoded, summary: summary)
    }
}
