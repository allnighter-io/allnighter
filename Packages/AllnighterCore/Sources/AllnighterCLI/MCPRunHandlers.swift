import Foundation
import AllnighterCore
import AllnighterEngine

/// MCP `team_run` — unified run entry (Unified Run Model).
enum MCPRunHandlers {
    enum Outcome: Sendable {
        case success(String, summary: String)
        case toolError(ErrorEnvelope)
    }

    static func run(runtime: ToolRuntime, args: [String: Any], defaultAgent: String) async -> Outcome {
        guard let message = (args["message"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines), !message.isEmpty else {
            return .toolError(ErrorEnvelope(code: "CLI_USAGE_ERROR", message: "message required", requiresManual: true, retryable: false))
        }
        guard let projectToken = args["project"] as? String, !projectToken.isEmpty else {
            return .toolError(ErrorEnvelope(code: "CLI_USAGE_ERROR", message: "project required", requiresManual: true, retryable: false))
        }
        let store = ProjectStore()
        guard let project = AllnighterCLI.resolveProject(projectToken, store: store) else {
            return .toolError(ErrorEnvelope(code: "PROJECT_NOT_FOUND", message: "project not found: \(projectToken)", requiresManual: true, retryable: false))
        }

        let effort = (args["effort"] as? String).flatMap(EffortLevel.init(rawValue:))
        let lane = (args["lane"] as? String).flatMap(WorkLane.init(rawValue:))
        let request = RunRequest(
            message: message,
            repoRoot: project.normalizedRootPath,
            projectId: project.id,
            presetId: args["team"] as? String,
            workerId: args["worker"] as? String,
            effort: effort,
            lane: lane,
            type: args["type"] as? String,
            context: args["context"] as? String
        )

        let service = RunService(
            models: runtime.models,
            registry: runtime.registry,
            teams: runtime.teams,
            invocations: runtime.invocations
        )
        let agent = (args["originAgent"] as? String) ?? defaultAgent
        let result = await service.run(request, origin: .mcp, originAgent: agent)
        switch result {
        case .failure(let error):
            return .toolError(ErrorEnvelope(code: error.code, message: error.description, requiresManual: error.code != "RUN_WRITE_LOCK_BUSY", retryable: error.code == "RUN_WRITE_LOCK_BUSY"))
        case .success(let run):
            let trj = TeamRunJSONMapper.map(
                run, models: runtime.models, manifests: runtime.registry.all,
                context: AllnighterCLI.defaultRunContext(run))
            let text = run.plan ?? run.workerAnswers.first?.output ?? "run \(run.status.rawValue)"
            return .success(AllnighterCLI.jsonString(trj), summary: text.prefix(200).description)
        }
    }
}
