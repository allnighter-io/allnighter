import Foundation
import AllnighterCore
import AllnighterEngine

/// MCP projections of async `team start/status/result/cancel` — same Core path as CLI.
enum MCPAsyncTeamHandlers {
    enum Outcome: Sendable {
        case success(String, summary: String)
        case toolError(ErrorEnvelope)
    }

    static func start(runtime: ToolRuntime, args: [String: Any], defaultAgent: String) async -> Outcome {
        guard var request = AsyncTeamStartRequest(mcpArguments: args) else {
            return .toolError(ErrorEnvelope(code: "CLI_USAGE_ERROR", message: "prompt required",
                                            requiresManual: true, retryable: false))
        }
        if request.originAgent == nil { request.originAgent = defaultAgent }
        if request.repoRoot == nil, let projectToken = args["project"] as? String, !projectToken.isEmpty {
            let store = ProjectStore()
            guard let project = AllnighterCLI.resolveProject(projectToken, store: store) else {
                return .toolError(ErrorEnvelope(code: "PROJECT_NOT_FOUND", message: "project not found: \(projectToken)",
                                                requiresManual: true, retryable: false))
            }
            request.repoRoot = project.normalizedRootPath
        }
        if let lane = args["lane"] as? String, request.lane == nil {
            return .toolError(ErrorEnvelope(code: "CLI_USAGE_ERROR", message: "unknown lane: \(lane)",
                                            requiresManual: true, retryable: false))
        }
        if let effort = args["effort"] as? String, request.effort == nil {
            return .toolError(ErrorEnvelope(code: "CLI_USAGE_ERROR", message: "unknown effort: \(effort)",
                                            requiresManual: true, retryable: false))
        }
        switch await runtime.asyncTeamService().start(request, origin: .mcp, readyModels: runtime.readyModels) {
        case .success(let response):
            let text = "Started \(response.runId) · \(response.status.rawValue) · poll in \(response.nextPollAfterMs)ms"
            return .success(AllnighterCLI.jsonString(response), summary: text)
        case .failure(let refusal):
            return .toolError(ErrorEnvelope(code: refusal.code, message: refusal.message,
                                            requiresManual: refusal.code == "DEFAULT_TEAM_INVALID",
                                            retryable: false))
        }
    }

    static func status(runtime: ToolRuntime, args: [String: Any]) async -> Outcome {
        guard let runId = args["runId"] as? String, !runId.isEmpty else {
            return .toolError(ErrorEnvelope(code: "CLI_USAGE_ERROR", message: "runId required",
                                            requiresManual: true, retryable: false))
        }
        guard let status = await runtime.asyncTeamService().status(runId: runId) else {
            return .toolError(ErrorEnvelope(code: "RUN_NOT_FOUND", message: "no run matches \(runId)",
                                            requiresManual: true, retryable: false))
        }
        let text = "Run \(status.runId) · \(status.status.rawValue) · resultAvailable=\(status.resultAvailable)"
        return .success(AllnighterCLI.jsonString(status), summary: text)
    }

    static func result(runtime: ToolRuntime, args: [String: Any]) async -> Outcome {
        guard let runId = args["runId"] as? String, !runId.isEmpty else {
            return .toolError(ErrorEnvelope(code: "CLI_USAGE_ERROR", message: "runId required",
                                            requiresManual: true, retryable: false))
        }
        let includePrompts = Self.includeWorkerPromptSnapshots(args)
        switch await runtime.asyncTeamService().result(runId: runId) {
        case .notFound:
            return .toolError(ErrorEnvelope(code: "RUN_NOT_FOUND", message: "no run matches \(runId)",
                                            requiresManual: true, retryable: false))
        case .notReady(let nr):
            return .success(AllnighterCLI.jsonString(nr),
                            summary: "Not ready · \(nr.status.rawValue) · poll in \(nr.nextPollAfterMs)ms")
        case .ready(let run):
            let trj = TeamRunJSONMapper.map(
                run, models: runtime.models, manifests: runtime.registry.all,
                context: AllnighterCLI.defaultRunContext(run, full: includePrompts))
            return .success(AllnighterCLI.jsonString(trj),
                            summary: "Run \(run.id) · \(run.status.rawValue)")
        }
    }

    /// Honor MCP/CLI parity: `detail: "full"` or `includePrompts: true`.
    static func includeWorkerPromptSnapshots(_ args: [String: Any]) -> Bool {
        if (args["includePrompts"] as? Bool) == true { return true }
        if let detail = args["detail"] as? String, detail.lowercased() == "full" { return true }
        return false
    }

    static func cancel(runtime: ToolRuntime, args: [String: Any]) async -> Outcome {
        guard let runId = args["runId"] as? String, !runId.isEmpty else {
            return .toolError(ErrorEnvelope(code: "CLI_USAGE_ERROR", message: "runId required",
                                            requiresManual: true, retryable: false))
        }
        guard let response = await runtime.asyncTeamService().cancel(runId: runId) else {
            return .toolError(ErrorEnvelope(code: "RUN_NOT_FOUND", message: "no run matches \(runId)",
                                            requiresManual: true, retryable: false))
        }
        return .success(AllnighterCLI.jsonString(response),
                        summary: "Cancelled \(response.runId) · \(response.status.rawValue)")
    }
}
