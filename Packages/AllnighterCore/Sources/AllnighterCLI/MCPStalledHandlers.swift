import Foundation
import AllnighterCore
import AllnighterEngine

enum MCPStalledHandlers {
    enum Outcome: Sendable {
        case success(String, summary: String)
        case toolError(ErrorEnvelope)
    }

    static func projectStalled(args: [String: Any]) -> Outcome {
        guard let projectToken = args["project"] as? String, !projectToken.isEmpty else {
            return .toolError(ErrorEnvelope(
                code: "CLI_USAGE_ERROR",
                message: "project required",
                requiresManual: true,
                retryable: false
            ))
        }
        let projectStore = ProjectStore()
        guard let project = try? projectStore.get(projectToken) else {
            return .toolError(ErrorEnvelope(
                code: "PROJECT_NOT_FOUND",
                message: "project not found: \(projectToken)",
                requiresManual: true,
                retryable: false
            ))
        }
        let includeCleared = boolArg(args["includeCleared"]) ?? false
        let service = StalledWorkService()
        _ = try? service.scanAndRefresh()
        let payload = service.projectStalledJSON(projectId: project.id, includeCleared: includeCleared)
        let json = AllnighterCLI.jsonString(payload)
        return .success(json, summary: "\(payload.episodes.count) stalled episode(s) in \(project.displayName)")
    }

    static func stalledList(args: [String: Any]) -> Outcome {
        guard boolArg(args["all"]) == true else {
            return .toolError(ErrorEnvelope(
                code: "CLI_USAGE_ERROR",
                message: "all=true required",
                requiresManual: true,
                retryable: false
            ))
        }
        let service = StalledWorkService()
        _ = try? service.scanAndRefresh()
        let payload = service.aggregateStalledJSON()
        let json = AllnighterCLI.jsonString(payload)
        let count = payload.projects.reduce(0) { $0 + $1.episodes.count }
        return .success(json, summary: "\(count) stalled episode(s) across \(payload.projects.count) project(s)")
    }

    private static func boolArg(_ value: Any?) -> Bool? {
        switch value {
        case let b as Bool: return b
        case let s as String: return ["true", "1", "yes"].contains(s.lowercased())
        case let n as NSNumber: return n.boolValue
        default: return nil
        }
    }
}
