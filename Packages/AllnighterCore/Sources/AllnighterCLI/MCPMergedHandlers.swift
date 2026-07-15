import Foundation
import AllnighterCore
import AllnighterEngine

/// Slice 1 merged MCP tool dispatch (MCP_Tool_Upgrade.md §4). Projects multiple
/// legacy CLI paths through one wire name per merge survivor.
enum MCPMergedHandlers {
    enum Outcome: Sendable {
        case success(String, summary: String)
        case toolError(ErrorEnvelope)
    }

    private static func usage(_ message: String) -> Outcome {
        .toolError(ErrorEnvelope(code: "CLI_USAGE_ERROR", message: message, requiresManual: true, retryable: false))
    }

    // MARK: - Catalog

    static func teamsGet(runtime: ToolRuntime, args: [String: Any]) -> Outcome {
        if let teamId = args["teamId"] as? String, !teamId.isEmpty {
            guard let team = TeamCatalog.get(teamId) else {
                return .toolError(ErrorEnvelope(code: "TEAM_NOT_FOUND", message: "unknown team: \(teamId)", requiresManual: true, retryable: false))
            }
            let detail = (args["detail"] as? String)?.lowercased()
            if detail == "definition" {
                return .success(AllnighterCLI.teamDefinitionJSONString(team), summary: team.displayName)
            }
            return .success(AllnighterCLI.teamShowJSONString(team), summary: team.displayName)
        }
        let lane = (args["lane"] as? String).flatMap(WorkLane.init(rawValue:))
        let includeInactive = (args["includeInactive"] as? Bool) ?? false
        let catalog = AllnighterCLI.teamsCatalogJSONString(runtime, lane: lane, includeInactive: includeInactive)
        if args["lane"] == nil, args["includeInactive"] == nil, args["cursor"] == nil, args["limit"] == nil {
            struct Wrapper: Encodable {
                let schemaVersion = 1
                let contractVersion: String
                let catalogJSON: String
                let laneDefaultsJSON: String
            }
            let wrapped = Wrapper(contractVersion: ContractRegistry.contractVersion,
                                  catalogJSON: catalog,
                                  laneDefaultsJSON: AllnighterCLI.teamShowJSONString(runtime))
            return .success(AllnighterCLI.jsonString(wrapped), summary: "Team catalog + lane defaults")
        }
        return .success(catalog, summary: "Team catalog")
    }

    static func teamsEdit(args: [String: Any]) -> Outcome {
        guard let action = (args["action"] as? String)?.lowercased(), !action.isEmpty else {
            return usage("action required (save|duplicate|set_default|delete|restore)")
        }
        guard let teamId = args["teamId"] as? String, !teamId.isEmpty else {
            return usage("teamId required")
        }
        do {
            switch action {
            case "duplicate":
                let team = try TeamCatalog.duplicateBuiltIn(teamId, name: args["name"] as? String)
                return .success(AllnighterCLI.teamShowJSONString(team), summary: "duplicated \(teamId)")
            case "save":
                let isNewLabTeam = TeamCatalog.get(teamId) == nil && teamId.hasPrefix("lab_")
                guard TeamCatalog.get(teamId) != nil || isNewLabTeam else {
                    return .toolError(ErrorEnvelope(code: "TEAM_NOT_FOUND", message: "unknown team: \(teamId)", requiresManual: true, retryable: false))
                }
                guard let definition = args["definition"] else { return usage("definition required") }
                let data = try JSONSerialization.data(withJSONObject: definition)
                let team = try CoreJSON.decode(TeamPreset.self, from: data)
                guard team.id == teamId else {
                    return .toolError(ErrorEnvelope(code: "TEAM_INVALID", message: "definition id must match teamId", requiresManual: true, retryable: false))
                }
                if teamId.hasPrefix("lab_"), !team.typeTags.contains(TeamPreset.labTypeTag) {
                    return .toolError(ErrorEnvelope(code: "TEAM_INVALID", message: "lab_ teams must include typeTags [\"lab\"]", requiresManual: true, retryable: false))
                }
                try TeamCatalog.saveCustom(team)
                return .success(AllnighterCLI.teamShowJSONString(team), summary: "saved \(teamId)")
            case "set_default":
                let team = try TeamCatalog.setDefault(teamId)
                return .success(AllnighterCLI.teamShowJSONString(team), summary: "default \(team.lane.rawValue)")
            case "delete":
                try TeamCatalog.deleteCustom(teamId)
                return .success(#"{"schemaVersion":1,"deleted":"\#(teamId)"}"#, summary: "deleted \(teamId)")
            case "restore":
                let restored = try TeamCatalog.restore(teamId)
                return .success(AllnighterCLI.teamShowJSONString(restored.team), summary: "restored \(teamId)")
            default:
                return usage("unknown action: \(action)")
            }
        } catch let error as CatalogError {
            let env = AllnighterCLI.catalogErrorEnvelope(error)
            return .toolError(ErrorEnvelope(code: env.code, message: env.message, requiresManual: true, retryable: false))
        } catch {
            return usage("\(error)")
        }
    }

    static func skillsGet(args: [String: Any]) -> Outcome {
        if let skillId = args["skillId"] as? String, !skillId.isEmpty {
            guard let skill = SkillCatalog.skill(skillId) else {
                return .toolError(ErrorEnvelope(code: "SKILL_NOT_FOUND", message: "unknown skill: \(skillId)", requiresManual: true, retryable: false))
            }
            return .success(AllnighterCLI.skillShowJSONString(skill), summary: skill.displayName)
        }
        return .success(AllnighterCLI.skillsCatalogJSONString(lane: nil), summary: "Skill catalog")
    }

    static func skillsEdit(args: [String: Any]) -> Outcome {
        guard let action = (args["action"] as? String)?.lowercased(), !action.isEmpty else {
            return usage("action required (save|duplicate|delete)")
        }
        guard let skillId = args["skillId"] as? String, !skillId.isEmpty else {
            return usage("skillId required")
        }
        do {
            switch action {
            case "duplicate":
                let skill = try SkillCatalog.duplicateBuiltIn(skillId, name: args["name"] as? String)
                return .success(AllnighterCLI.skillShowJSONString(skill), summary: "duplicated \(skillId)")
            case "save":
                guard let definition = args["definition"] else { return usage("definition required") }
                let data = try JSONSerialization.data(withJSONObject: definition)
                let skill = try CoreJSON.decode(Skill.self, from: data)
                guard skill.id == skillId else {
                    return .toolError(ErrorEnvelope(code: "SKILL_INVALID", message: "definition id must match skillId", requiresManual: true, retryable: false))
                }
                try SkillCatalog.saveCustom(skill)
                return .success(AllnighterCLI.skillShowJSONString(skill), summary: "saved \(skillId)")
            case "delete":
                try SkillCatalog.deleteCustom(skillId)
                return .success(#"{"schemaVersion":1,"deleted":"\#(skillId)"}"#, summary: "deleted \(skillId)")
            default:
                return usage("unknown action: \(action)")
            }
        } catch let error as CatalogError {
            let env = AllnighterCLI.catalogErrorEnvelope(error, skillContext: true)
            return .toolError(ErrorEnvelope(code: env.code, message: env.message, requiresManual: true, retryable: false))
        } catch {
            return usage("\(error)")
        }
    }

    // MARK: - Runs

    static func runGet(runtime: ToolRuntime, args: [String: Any]) -> Outcome {
        let ref = (args["run"] as? String) ?? (args["runId"] as? String) ?? "latest"
        var runArgs = args
        runArgs["run"] = ref
        guard let run = AllnighterCLI.resolveRun(AllnighterCLI.runRef(from: runArgs)) else {
            return .toolError(ErrorEnvelope(code: "RUN_NOT_FOUND", message: "no run matches \(ref)", requiresManual: true, retryable: false))
        }
        let view = ((args["view"] as? String) ?? "summary").lowercased()
        switch view {
        case "spec":
            let result = AllnighterCLI.specResult(run, runtime: runtime, detail: args["detail"] as? String)
            return .success(AllnighterCLI.jsonString(result), summary: result.summary)
        case "floor":
            return .success(AllnighterCLI.floorRunJSONString(run), summary: "Floor \(run.id)")
        default:
            let full = (args["full"] as? Bool) ?? ((args["includePrompts"] as? Bool) ?? false)
            let trj = TeamRunJSONMapper.map(
                run, models: runtime.models, manifests: runtime.registry.all,
                context: AllnighterCLI.defaultRunContext(run, full: full))
            return .success(AllnighterCLI.jsonString(trj), summary: "Run \(run.id) · \(run.status.rawValue)")
        }
    }

    // MARK: - Help

    static func help(args: [String: Any]) -> Outcome {
        if let query = (args["query"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines), !query.isEmpty {
            switch MCPHelpHandlers.search(args: args) {
            case .success(let json, let summary): return .success(json, summary: summary)
            case .toolError(let e): return .toolError(e)
            }
        }
        switch MCPHelpHandlers.get(args: args) {
        case .success(let json, let summary): return .success(json, summary: summary)
        case .toolError(let e): return .toolError(e)
        }
    }

    // MARK: - Threads

    static func threadGet(args: [String: Any]) -> Outcome {
        guard let threadRef = args["threadId"] as? String else {
            return usage("threadId required")
        }
        let store = ThreadStore()
        guard let threadId = AllnighterCLI.resolveThreadId(threadRef, store: store) else {
            return .toolError(ErrorEnvelope(code: "THREAD_NOT_FOUND", message: "thread not found", requiresManual: true, retryable: false))
        }
        if let attachmentId = args["attachmentId"] as? String, !attachmentId.isEmpty {
            do {
                let dir = try store.threadDirectory(forThreadId: threadId)
                guard let response = ThreadAttachmentResolver.attachmentGet(
                    threadId: threadId, attachmentId: attachmentId, threadDirectory: dir
                ) else {
                    return .toolError(ErrorEnvelope(code: "ATTACHMENT_NOT_FOUND", message: "attachment not found", requiresManual: true, retryable: false))
                }
                return .success(AllnighterCLI.jsonString(response), summary: response.canonicalPath)
            } catch {
                return .toolError(ErrorEnvelope(code: "THREAD_NOT_FOUND", message: "\(error)", requiresManual: true, retryable: false))
            }
        }
        guard let thread = store.get(threadId) else {
            return .toolError(ErrorEnvelope(code: "THREAD_NOT_FOUND", message: "thread not found", requiresManual: true, retryable: false))
        }
        let projection = ThreadCLI.project(thread: thread, threadId: threadId, store: store)
        return .success(AllnighterCLI.jsonString(projection), summary: projection.title)
    }

    // MARK: - Pending

    static func pendingList(runtime: ToolRuntime, args: [String: Any]) -> Outcome {
        if (args["mode"] as? String)?.lowercased() == "queue" {
            switch MCPPendingHandlers.queue(runtime: runtime) {
            case .success(let j, let s): return .success(j, summary: s)
            case .toolError(let e): return .toolError(e)
            }
        }
        if let pendingId = args["pendingId"] as? String, !pendingId.isEmpty {
            switch MCPPendingHandlers.show(runtime: runtime, args: ["pendingId": pendingId]) {
            case .success(let j, let s): return .success(j, summary: s)
            case .toolError(let e): return .toolError(e)
            }
        }
        switch MCPPendingHandlers.list(runtime: runtime, args: args) {
        case .success(let j, let s): return .success(j, summary: s)
        case .toolError(let e): return .toolError(e)
        }
    }

    static func pendingUpdate(runtime: ToolRuntime, args: [String: Any]) -> Outcome {
        guard let action = (args["action"] as? String)?.lowercased(), !action.isEmpty else {
            return usage("action required (submit|cancel|reorder)")
        }
        switch action {
        case "submit":
            switch MCPPendingHandlers.submit(runtime: runtime, args: args) {
            case .success(let j, let s): return .success(j, summary: s)
            case .toolError(let e): return .toolError(e)
            }
        case "cancel":
            switch MCPPendingHandlers.cancel(runtime: runtime, args: args) {
            case .success(let j, let s): return .success(j, summary: s)
            case .toolError(let e): return .toolError(e)
            }
        case "reorder":
            switch MCPPendingHandlers.reorder(runtime: runtime, args: args) {
            case .success(let j, let s): return .success(j, summary: s)
            case .toolError(let e): return .toolError(e)
            }
        default:
            return usage("unknown action: \(action)")
        }
    }

    // MARK: - Stalled

    static func stalledList(args: [String: Any]) -> Outcome {
        if let project = args["project"] as? String, !project.isEmpty {
            switch MCPStalledHandlers.projectStalled(args: ["project": project, "includeCleared": args["includeCleared"] as Any]) {
            case .success(let j, let s): return .success(j, summary: s)
            case .toolError(let e): return .toolError(e)
            }
        }
        switch MCPStalledHandlers.stalledList(args: ["all": true]) {
        case .success(let j, let s): return .success(j, summary: s)
        case .toolError(let e): return .toolError(e)
        }
    }

    static func stalledUpdate(args: [String: Any]) -> Outcome {
        guard let action = (args["action"] as? String)?.lowercased(), !action.isEmpty else {
            return usage("action required (check|wait|dismiss)")
        }
        switch action {
        case "check":
            switch MCPStalledHandlers.checkStatus(args: args) {
            case .success(let j, let s): return .success(j, summary: s)
            case .toolError(let e): return .toolError(e)
            }
        case "wait":
            switch MCPStalledHandlers.keepWaiting(args: args) {
            case .success(let j, let s): return .success(j, summary: s)
            case .toolError(let e): return .toolError(e)
            }
        case "dismiss":
            switch MCPStalledHandlers.dismiss(args: args) {
            case .success(let j, let s): return .success(j, summary: s)
            case .toolError(let e): return .toolError(e)
            }
        default:
            return usage("unknown action: \(action)")
        }
    }

    // MARK: - Projects

    static func projectGet(args: [String: Any]) -> Outcome {
        if let project = args["project"] as? String, !project.isEmpty {
            switch MCPProjectHandlers.get(args: args) {
            case .success(let j, let s): return .success(j, summary: s)
            case .toolError(let e): return .toolError(e)
            }
        }
        switch MCPProjectHandlers.list(args: args) {
        case .success(let j, let s): return .success(j, summary: s)
        case .toolError(let e): return .toolError(e)
        }
    }

    static func projectWorkers(runtime: ToolRuntime, args: [String: Any]) async -> Outcome {
        let refresh = (args["refresh"] as? Bool) == true
            || ((args["refresh"] as? String)?.lowercased() == "true")
        if refresh {
            switch await MCPProjectHandlers.recheckWorkers(args: args, runtime: runtime) {
            case .success(let j, let s): return .success(j, summary: s)
            case .toolError(let e): return .toolError(e)
            }
        }
        switch MCPProjectHandlers.workers(args: args) {
        case .success(let j, let s): return .success(j, summary: s)
        case .toolError(let e): return .toolError(e)
        }
    }
}
