import Foundation
import AllnighterCore
import AllnighterEngine

/// A minimal MCP stdio server exposing the team as tools any MCP-aware agent can call.
struct MCPServer {
    let runtime: ToolRuntime
    static let protocolVersion = MCPWire.protocolVersion

    func serve() async {
        let reader = FrameReader()
        while let message = reader.next() {
            guard let obj = try? JSONSerialization.jsonObject(with: Data(message.utf8)) as? [String: Any] else { continue }
            let id = obj["id"]
            guard let method = obj["method"] as? String else { continue }
            let params = obj["params"] as? [String: Any] ?? [:]

            switch method {
            case "initialize":
                respond(id: id, result: [
                    "protocolVersion": Self.protocolVersion,
                    "serverInfo": ["name": "alln", "version": MCPWire.serverVersion],
                    "capabilities": ["tools": [:]]
                ])
            case "tools/list":
                respond(id: id, result: ["tools": toolDefinitions()])
            case "tools/call":
                await handleCall(id: id, params: params)
            case "notifications/initialized", "ping":
                if id != nil { respond(id: id, result: [:]) }
            default:
                if id != nil { respondError(id: id, code: -32601, message: "method not found: \(method)") }
            }
        }
    }

    private func handleCall(id: Any?, params: [String: Any]) async {
        let name = params["name"] as? String ?? ""
        let args = params["arguments"] as? [String: Any] ?? [:]
        let agent = (args["originAgent"] as? String) ?? "mcp"
        let service = runtime.service()
        switch name {
        case "mcp_hello":
            let verdict = AgentReadiness.evaluate(teams: runtime.teams, readyModels: runtime.readyModels)
            let text = verdict.canStartTeamRun
                ? "Ready. \(verdict.readyTeams.count) team(s) can start."
                : "Not ready: \(verdict.blockedReason ?? "see doctor")."
            respond(id: id, result: toolText(text, structured: AllnighterCLI.mcpHelloJSONString(runtime)))
        case "teams_list":
            let lane = (args["lane"] as? String).flatMap(WorkLane.init(rawValue:))
            let includeInactive = (args["includeInactive"] as? Bool) ?? false
            respond(id: id, result: toolText("Team catalog", structured: AllnighterCLI.teamsCatalogJSONString(runtime, lane: lane, includeInactive: includeInactive)))
        case "teams_show":
            guard let teamId = args["teamId"] as? String, let team = TeamCatalog.get(teamId) else {
                return respondToolError(id: id, code: "TEAM_NOT_FOUND", message: "teamId required")
            }
            respond(id: id, result: toolText(team.displayName, structured: AllnighterCLI.teamShowJSONString(team)))
        case "teams_definition":
            guard let teamId = args["teamId"] as? String, let team = TeamCatalog.get(teamId) else {
                return respondToolError(id: id, code: "TEAM_NOT_FOUND", message: "teamId required")
            }
            respond(id: id, result: toolText(team.displayName, structured: AllnighterCLI.teamDefinitionJSONString(team)))
        case "teams_duplicate":
            guard let teamId = args["teamId"] as? String else {
                return respondToolError(id: id, code: "CLI_USAGE_ERROR", message: "teamId required")
            }
            do {
                let team = try TeamCatalog.duplicateBuiltIn(teamId, name: args["name"] as? String)
                respond(id: id, result: toolText("duplicated \(teamId)", structured: AllnighterCLI.teamShowJSONString(team)))
            } catch let error as CatalogError {
                let env = AllnighterCLI.catalogErrorEnvelope(error)
                respondToolError(id: id, code: env.code, message: env.message)
            } catch {
                respondToolError(id: id, code: "CLI_USAGE_ERROR", message: "\(error)")
            }
        case "teams_save":
            guard let teamId = args["teamId"] as? String else {
                return respondToolError(id: id, code: "CLI_USAGE_ERROR", message: "teamId required")
            }
            let isNewLabTeam = TeamCatalog.get(teamId) == nil && teamId.hasPrefix("lab_")
            guard TeamCatalog.get(teamId) != nil || isNewLabTeam else {
                return respondToolError(id: id, code: "TEAM_NOT_FOUND", message: "unknown team: \(teamId)")
            }
            guard let definition = args["definition"] else {
                return respondToolError(id: id, code: "CLI_USAGE_ERROR", message: "definition required")
            }
            do {
                let data = try JSONSerialization.data(withJSONObject: definition)
                let team = try CoreJSON.decode(TeamPreset.self, from: data)
                guard team.id == teamId else {
                    return respondToolError(id: id, code: "TEAM_INVALID", message: "definition id must match teamId")
                }
                // Any lab_-prefixed team must carry the lab typeTag — on create AND
                // edit — so it can never be stripped back into GUI visibility.
                if teamId.hasPrefix("lab_"), !team.typeTags.contains(TeamPreset.labTypeTag) {
                    return respondToolError(id: id, code: "TEAM_INVALID", message: "lab_ teams must include typeTags [\"lab\"]")
                }
                try TeamCatalog.saveCustom(team)
                respond(id: id, result: toolText("saved \(teamId)", structured: AllnighterCLI.teamShowJSONString(team)))
            } catch let error as CatalogError {
                let env = AllnighterCLI.catalogErrorEnvelope(error)
                respondToolError(id: id, code: env.code, message: env.message)
            } catch {
                respondToolError(id: id, code: "CLI_USAGE_ERROR", message: "\(error)")
            }
        case "teams_set_default":
            guard let teamId = args["teamId"] as? String else {
                return respondToolError(id: id, code: "CLI_USAGE_ERROR", message: "teamId required")
            }
            do {
                let team = try TeamCatalog.setDefault(teamId)
                respond(id: id, result: toolText("default \(team.lane.rawValue)", structured: AllnighterCLI.teamShowJSONString(team)))
            } catch let error as CatalogError {
                let env = AllnighterCLI.catalogErrorEnvelope(error)
                respondToolError(id: id, code: env.code, message: env.message)
            } catch {
                respondToolError(id: id, code: "CLI_USAGE_ERROR", message: "\(error)")
            }
        case "teams_delete":
            guard let teamId = args["teamId"] as? String else {
                return respondToolError(id: id, code: "CLI_USAGE_ERROR", message: "teamId required")
            }
            do {
                try TeamCatalog.deleteCustom(teamId)
                respond(id: id, result: toolText("deleted \(teamId)", structured: AllnighterCLI.jsonString(AllnighterCLI.DeleteAck(deleted: teamId))))
            } catch let error as CatalogError {
                let env = AllnighterCLI.catalogErrorEnvelope(error)
                respondToolError(id: id, code: env.code, message: env.message)
            } catch {
                respondToolError(id: id, code: "CLI_USAGE_ERROR", message: "\(error)")
            }
        case "teams_restore":
            guard let teamId = args["teamId"] as? String else {
                return respondToolError(id: id, code: "CLI_USAGE_ERROR", message: "teamId required")
            }
            do {
                let result = try TeamCatalog.restore(teamId)
                respond(id: id, result: toolText(
                    result.removedOverride ? "restored \(teamId)" : "\(teamId) already shipped",
                    structured: AllnighterCLI.teamRestoreJSONString(id: teamId, restored: result.removedOverride)))
            } catch let error as CatalogError {
                let env = AllnighterCLI.catalogErrorEnvelope(error)
                respondToolError(id: id, code: env.code, message: env.message)
            } catch {
                respondToolError(id: id, code: "CLI_USAGE_ERROR", message: "\(error)")
            }
        case "skills_list":
            let lane = (args["lane"] as? String).flatMap(WorkLane.init(rawValue:))
            respond(id: id, result: toolText("Skill catalog", structured: AllnighterCLI.skillsCatalogJSONString(lane: lane)))
        case "skills_show":
            guard let skillId = args["skillId"] as? String, let skill = SkillCatalog.get(skillId) else {
                return respondToolError(id: id, code: "SKILL_NOT_FOUND", message: "skillId required")
            }
            respond(id: id, result: toolText(skill.displayName, structured: AllnighterCLI.skillShowJSONString(skill)))
        case "skills_duplicate":
            guard let skillId = args["skillId"] as? String else {
                return respondToolError(id: id, code: "CLI_USAGE_ERROR", message: "skillId required")
            }
            do {
                let skill = try SkillCatalog.duplicateBuiltIn(skillId, name: args["name"] as? String)
                respond(id: id, result: toolText("duplicated \(skillId)", structured: AllnighterCLI.skillShowJSONString(skill)))
            } catch let error as CatalogError {
                let env = AllnighterCLI.catalogErrorEnvelope(error, skillContext: true)
                respondToolError(id: id, code: env.code, message: env.message)
            } catch {
                respondToolError(id: id, code: "CLI_USAGE_ERROR", message: "\(error)")
            }
        case "skills_save":
            guard let skillId = args["skillId"] as? String else {
                return respondToolError(id: id, code: "CLI_USAGE_ERROR", message: "skillId required")
            }
            guard SkillCatalog.get(skillId) != nil else {
                return respondToolError(id: id, code: "SKILL_NOT_FOUND", message: "unknown skill: \(skillId)")
            }
            guard let definition = args["definition"] else {
                return respondToolError(id: id, code: "CLI_USAGE_ERROR", message: "definition required")
            }
            do {
                let data = try JSONSerialization.data(withJSONObject: definition)
                let skill = try CoreJSON.decode(Skill.self, from: data)
                guard skill.id == skillId else {
                    return respondToolError(id: id, code: "SKILL_INVALID", message: "definition id must match skillId")
                }
                try SkillCatalog.saveCustom(skill)
                respond(id: id, result: toolText("saved \(skillId)", structured: AllnighterCLI.skillShowJSONString(skill)))
            } catch let error as CatalogError {
                let env = AllnighterCLI.catalogErrorEnvelope(error, skillContext: true)
                respondToolError(id: id, code: env.code, message: env.message)
            } catch {
                respondToolError(id: id, code: "CLI_USAGE_ERROR", message: "\(error)")
            }
        case "skills_delete":
            guard let skillId = args["skillId"] as? String else {
                return respondToolError(id: id, code: "CLI_USAGE_ERROR", message: "skillId required")
            }
            do {
                try SkillCatalog.deleteCustom(skillId)
                respond(id: id, result: toolText("deleted \(skillId)", structured: AllnighterCLI.jsonString(AllnighterCLI.DeleteAck(deleted: skillId))))
            } catch let error as CatalogError {
                let env = AllnighterCLI.catalogErrorEnvelope(error, skillContext: true)
                respondToolError(id: id, code: env.code, message: env.message)
            } catch {
                respondToolError(id: id, code: "CLI_USAGE_ERROR", message: "\(error)")
            }
        case "team_preflight":
            let result = AllnighterCLI.preflight(runtime, args: args)
            let text = result.canStart
                ? "Preflight OK: \(result.teamDisplayName ?? result.teamPresetId ?? "team") / \(result.effort ?? "?"). \(result.readyWorkers.count) workers."
                : "Preflight blocked: \(result.blockedReason ?? "unknown")."
            respond(id: id, result: toolText(text, structured: AllnighterCLI.jsonString(result)))
        case "team_start":
            await respondAsyncTeam(id: id, outcome: await MCPAsyncTeamHandlers.start(runtime: runtime, args: args, defaultAgent: agent))
        case "team_status":
            await respondAsyncTeam(id: id, outcome: await MCPAsyncTeamHandlers.status(runtime: runtime, args: args))
        case "team_result":
            await respondAsyncTeam(id: id, outcome: await MCPAsyncTeamHandlers.result(runtime: runtime, args: args))
        case "team_cancel":
            await respondAsyncTeam(id: id, outcome: await MCPAsyncTeamHandlers.cancel(runtime: runtime, args: args))
        case "team_run":
            await respondRun(id: id, outcome: await MCPRunHandlers.run(runtime: runtime, args: args, defaultAgent: agent))
        case "pair_slice":
            await respondPair(id: id, outcome: await MCPPairHandlers.slice(runtime: runtime, args: args))
        case "pair_run":
            await respondPair(id: id, outcome: await MCPPairHandlers.run(runtime: runtime, args: args))
        case "pair_status":
            await respondPair(id: id, outcome: await MCPPairHandlers.status(runtime: runtime, args: args))
        case "team_ask":
            guard let q = args["question"] as? String else { return respondToolError(id: id, code: "CLI_USAGE_ERROR", message: "question required") }
            let req = TeamRequest(
                question: q,
                lane: (args["lane"] as? String).flatMap(WorkLane.init(rawValue:)),
                teamPresetId: args["team"] as? String,
                effort: (args["effort"] as? String).flatMap(EffortLevel.init(rawValue:)),
                type: args["type"] as? String,
                context: args["context"] as? String
            )
            let result = await service.run(req, origin: .mcp, originAgent: agent)
            guard !result.runId.isEmpty else {
                return respondToolError(id: id, code: result.errorCode ?? "DEFAULT_TEAM_INVALID", message: result.note.isEmpty ? "team run did not start" : result.note)
            }
            guard let run = AllnighterCLI.loadRun(result.runId) else {
                return respondToolError(id: id, code: "RUN_NOT_FOUND", message: "team run did not persist")
            }
            let trj = TeamRunJSONMapper.map(run, models: runtime.models, manifests: runtime.registry.all, context: AllnighterCLI.defaultRunContext(run))
            respond(id: id, result: toolText(run.plan ?? "(no plan — status \(run.status.rawValue))", structured: AllnighterCLI.jsonString(trj)))
        case "team_show":
            respond(id: id, result: toolText("Current default team", structured: AllnighterCLI.teamShowJSONString(runtime)))
        case "history":
            let query = args["query"] as? String ?? ""
            let hits = await service.recall(query: query)
            let text = hits.isEmpty ? "(no prior team runs match)" : hits.map { "\($0.createdAt) \($0.prompt)" }.joined(separator: "\n")
            let payload = HistoryJSON(contractVersion: ContractRegistry.contractVersion, query: query, results: hits)
            respond(id: id, result: toolText(text, structured: AllnighterCLI.jsonString(payload)))
        case "show":
            let ref = AllnighterCLI.runRef(from: args)
            guard let run = AllnighterCLI.resolveRun(ref) else {
                return respondToolError(id: id, code: "RUN_NOT_FOUND", message: "no run matches \(ref)")
            }
            let full = (args["full"] as? Bool) ?? false
            let trj = TeamRunJSONMapper.map(
                run, models: runtime.models, manifests: runtime.registry.all,
                context: AllnighterCLI.defaultRunContext(run, full: full))
            respond(id: id, result: toolText("Run \(run.id) · \(run.status.rawValue)", structured: AllnighterCLI.jsonString(trj)))
        case "doctor":
            let sourceId = args["agent"] as? String
            if let sourceId, runtime.registry.manifest(id: sourceId) == nil {
                return respondToolError(id: id, code: "SOURCE_NOT_FOUND", message: "no source manifest '\(sourceId)'")
            }
            let doc = await AllnighterCLI.doctorResult(
                runtime, full: (args["full"] as? Bool) ?? false, sourceId: sourceId)
            respond(id: id, result: toolText("doctor: \(doc.status.rawValue)", structured: AllnighterCLI.jsonString(doc)))
        case "error_explain":
            guard let code = args["code"] as? String,
                  let spec = ContractRegistry.milestone1.errors.first(where: { $0.code == code }) else {
                return respondToolError(id: id, code: "CLI_USAGE_ERROR", message: "unknown error code: \(args["code"] as? String ?? "")")
            }
            let bridged = ErrorHelpBridge.explain(spec, contractVersion: ContractRegistry.contractVersion)
            respond(id: id, result: toolText("\(spec.code): \(spec.agentAction)", structured: AllnighterCLI.jsonString(bridged)))
        case "spec_get":
            let ref = AllnighterCLI.runRef(from: args)
            guard let run = AllnighterCLI.resolveRun(ref) else {
                return respondToolError(id: id, code: "RUN_NOT_FOUND", message: "no run matches \(ref)")
            }
            let result = AllnighterCLI.specResult(run, runtime: runtime, detail: args["detail"] as? String)
            respond(id: id, result: toolText(result.summary, structured: AllnighterCLI.jsonString(result)))
        case "floor_show":
            let ref = AllnighterCLI.runRef(from: args)
            guard let run = AllnighterCLI.resolveRun(ref) else {
                return respondToolError(id: id, code: "RUN_NOT_FOUND", message: "no run matches \(ref)")
            }
            respond(id: id, result: toolText("Floor \(run.id) · \(run.status.rawValue)",
                                             structured: AllnighterCLI.floorRunJSONString(run)))
        case "thread_send":
            let outcome = await MCPThreadSendHandlers.runSend(args: args, runtime: runtime)
            switch outcome {
            case .success(let response):
                respond(id: id, result: toolText("thread send ok", structured: AllnighterCLI.jsonString(response)))
            case .failure(let envelope):
                respondToolError(id: id, code: envelope.code, message: envelope.message)
            }
        case "thread_get":
            guard let threadRef = args["threadId"] as? String else {
                return respondToolError(id: id, code: "CLI_USAGE_ERROR", message: "threadId required")
            }
            let store = ThreadStore()
            guard let threadId = AllnighterCLI.resolveThreadId(threadRef, store: store),
                  let thread = store.get(threadId) else {
                return respondToolError(id: id, code: "THREAD_NOT_FOUND", message: "thread not found")
            }
            let projection = ThreadCLI.project(thread: thread, threadId: threadId, store: store)
            respond(id: id, result: toolText(projection.title, structured: AllnighterCLI.jsonString(projection)))
        case "thread_rename":
            guard let threadRef = args["threadId"] as? String else {
                return respondToolError(id: id, code: "CLI_USAGE_ERROR", message: "threadId required")
            }
            guard let title = (args["title"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines), !title.isEmpty else {
                return respondToolError(id: id, code: "CLI_USAGE_ERROR", message: "non-empty title required")
            }
            let store = ThreadStore()
            guard let threadId = AllnighterCLI.resolveThreadId(threadRef, store: store) else {
                return respondToolError(id: id, code: "THREAD_NOT_FOUND", message: "thread not found: \(threadRef)")
            }
            do {
                let thread = try store.renameThread(threadId: threadId, title: title)
                respond(id: id, result: toolText("renamed → \(thread.title)", structured: AllnighterCLI.jsonString(thread)))
            } catch let error as ThreadStoreError {
                if case .threadNotFound = error {
                    return respondToolError(id: id, code: "THREAD_NOT_FOUND", message: "thread not found: \(threadId)")
                }
                return respondToolError(id: id, code: "CLI_USAGE_ERROR", message: "\(error)")
            } catch {
                return respondToolError(id: id, code: "CLI_USAGE_ERROR", message: "\(error)")
            }
        case "thread_status":
            guard let threadRef = args["threadId"] as? String else {
                return respondToolError(id: id, code: "CLI_USAGE_ERROR", message: "threadId required")
            }
            let store = ThreadStore()
            guard let threadId = AllnighterCLI.resolveThreadId(threadRef, store: store),
                  let thread = store.get(threadId) else {
                return respondToolError(id: id, code: "THREAD_NOT_FOUND", message: "thread not found")
            }
            let status = ThreadStatusResponse(threadId: threadId, isRunning: thread.isRunning, needsAttention: thread.needsAttention)
            respond(id: id, result: toolText(thread.isRunning ? "running" : "idle", structured: AllnighterCLI.jsonString(status)))
        case "thread_attachment_get":
            guard let threadRef = args["threadId"] as? String,
                  let attachmentId = args["attachmentId"] as? String else {
                return respondToolError(id: id, code: "CLI_USAGE_ERROR", message: "threadId and attachmentId required")
            }
            let store = ThreadStore()
            guard let threadId = AllnighterCLI.resolveThreadId(threadRef, store: store) else {
                return respondToolError(id: id, code: "THREAD_NOT_FOUND", message: "thread not found")
            }
            do {
                let dir = try store.threadDirectory(forThreadId: threadId)
                guard let response = ThreadAttachmentResolver.attachmentGet(
                    threadId: threadId, attachmentId: attachmentId, threadDirectory: dir
                ) else {
                    return respondToolError(id: id, code: "ATTACHMENT_NOT_FOUND", message: "attachment not found")
                }
                respond(id: id, result: toolText(response.canonicalPath, structured: AllnighterCLI.jsonString(response)))
            } catch {
                return respondToolError(id: id, code: "THREAD_NOT_FOUND", message: "\(error)")
            }
        case "pending_list":
            respondPending(id: id, outcome: MCPPendingHandlers.list(runtime: runtime, args: args))
        case "pending_queue":
            respondPending(id: id, outcome: MCPPendingHandlers.queue(runtime: runtime))
        case "pending_submit":
            respondPending(id: id, outcome: MCPPendingHandlers.submit(runtime: runtime, args: args))
        case "pending_edit":
            respondPending(id: id, outcome: MCPPendingHandlers.edit(runtime: runtime, args: args))
        case "pending_reorder":
            respondPending(id: id, outcome: MCPPendingHandlers.reorder(runtime: runtime, args: args))
        case "pending_cancel":
            respondPending(id: id, outcome: MCPPendingHandlers.cancel(runtime: runtime, args: args))
        case "pending_show":
            respondPending(id: id, outcome: MCPPendingHandlers.show(runtime: runtime, args: args))
        case "pending_run":
            await respondPending(id: id, outcome: await MCPPendingHandlers.run(runtime: runtime, args: args))
        case "project_stalled":
            respondStalled(id: id, outcome: MCPStalledHandlers.projectStalled(args: args))
        case "stalled_list":
            respondStalled(id: id, outcome: MCPStalledHandlers.stalledList(args: args))
        case "stall_check_status":
            respondStalled(id: id, outcome: MCPStalledHandlers.checkStatus(args: args))
        case "stall_keep_waiting":
            respondStalled(id: id, outcome: MCPStalledHandlers.keepWaiting(args: args))
        case "stall_dismiss":
            respondStalled(id: id, outcome: MCPStalledHandlers.dismiss(args: args))
        case "defaults_get": respondDefaults(id: id, outcome: MCPDefaultsHandlers.get(runtime: runtime))
        case "boost_window_show": respondBoostWindow(id: id, outcome: MCPBoostWindowHandlers.show(runtime: runtime))
        case "boost_window_set": respondBoostWindow(id: id, outcome: MCPBoostWindowHandlers.set(runtime: runtime, args: args))
        case "boost_window_seed": respondBoostWindow(id: id, outcome: await MCPBoostWindowHandlers.seed(runtime: runtime, args: args))
        case "boost_window_observations_clear": respondBoostWindow(id: id, outcome: MCPBoostWindowHandlers.clearObservations(args: args))
        case "help_search": respondHelp(id: id, outcome: MCPHelpHandlers.search(args: args))
        case "help_get": respondHelp(id: id, outcome: MCPHelpHandlers.get(args: args))
        case "project_list": respondProject(id: id, outcome: MCPProjectHandlers.list(args: args))
        case "project_get": respondProject(id: id, outcome: MCPProjectHandlers.get(args: args))
        case "project_context": respondProject(id: id, outcome: MCPProjectHandlers.context(args: args))
        case "project_workers": respondProject(id: id, outcome: MCPProjectHandlers.workers(args: args))
        case "project_recheck_workers": respondProject(id: id, outcome: await MCPProjectHandlers.recheckWorkers(args: args, runtime: runtime))
        default:
            respondError(id: id, code: -32602, message: "unknown tool: \(name)")
        }
    }

    /// Tool descriptors derive from the contract registry — no MCP-only schemas.
    private func toolDefinitions() -> [[String: Any]] {
        MCPWire.toolDefinitions(from: ContractRegistry.milestone1.mcpTools)
    }

    /// A tool-level failure carrying the shared `ErrorEnvelope` (no MCP-only error shape).
    private func respondAsyncTeam(id: Any?, outcome: MCPAsyncTeamHandlers.Outcome) {
        switch outcome {
        case .success(let json, let summary):
            respond(id: id, result: toolText(summary, structured: json))
        case .toolError(let envelope):
            respondToolError(id: id, code: envelope.code, message: envelope.message)
        }
    }

    private func respondRun(id: Any?, outcome: MCPRunHandlers.Outcome) {
        switch outcome {
        case .success(let json, let summary):
            respond(id: id, result: toolText(summary, structured: json))
        case .toolError(let envelope):
            respondToolError(id: id, code: envelope.code, message: envelope.message)
        }
    }

    private func respondPair(id: Any?, outcome: MCPPairHandlers.Outcome) {
        switch outcome {
        case .success(let json, let summary):
            respond(id: id, result: toolText(summary, structured: json))
        case .toolError(let envelope):
            respondToolError(id: id, code: envelope.code, message: envelope.message)
        }
    }

    private func respondPending(id: Any?, outcome: MCPPendingHandlers.Outcome) {
        switch outcome {
        case .success(let json, let summary):
            respond(id: id, result: toolText(summary, structured: json))
        case .toolError(let envelope):
            respondToolError(id: id, code: envelope.code, message: envelope.message)
        }
    }

    private func respondStalled(id: Any?, outcome: MCPStalledHandlers.Outcome) {
        switch outcome {
        case .success(let json, let summary):
            respond(id: id, result: toolText(summary, structured: json))
        case .toolError(let envelope):
            respondToolError(id: id, code: envelope.code, message: envelope.message)
        }
    }

    private func respondDefaults(id: Any?, outcome: MCPDefaultsHandlers.Outcome) {
        switch outcome {
        case .success(let json, let summary):
            respond(id: id, result: toolText(summary, structured: json))
        case .toolError(let envelope):
            respondToolError(id: id, code: envelope.code, message: envelope.message)
        }
    }

    private func respondBoostWindow(id: Any?, outcome: MCPBoostWindowHandlers.Outcome) {
        switch outcome {
        case .success(let json, let summary):
            respond(id: id, result: toolText(summary, structured: json))
        case .toolError(let envelope):
            respondToolError(id: id, code: envelope.code, message: envelope.message)
        }
    }

    private func respondHelp(id: Any?, outcome: MCPHelpHandlers.Outcome) {
        switch outcome {
        case .success(let json, let summary):
            respond(id: id, result: toolText(summary, structured: json))
        case .toolError(let envelope):
            respondToolError(id: id, code: envelope.code, message: envelope.message)
        }
    }

    private func respondProject(id: Any?, outcome: MCPProjectHandlers.Outcome) {
        switch outcome {
        case .success(let json, let summary):
            respond(id: id, result: toolText(summary, structured: json))
        case .toolError(let envelope):
            respondToolError(id: id, code: envelope.code, message: envelope.message)
        }
    }

    private func respondToolError(id: Any?, code: String, message: String) {
        respond(id: id, result: [
            "content": [["type": "text", "text": "\(code): \(message)"]],
            "isError": true,
            "structuredContent": MCPWire.toolErrorStructuredContent(code: code, message: message),
        ])
    }

    private func toolText(_ text: String, structured: String? = nil) -> [String: Any] {
        var result: [String: Any] = ["content": [["type": "text", "text": text]]]
        if let structured, let obj = MCPWire.typedStructuredContent(structured) {
            result["structuredContent"] = obj
        }
        return result
    }

    // MARK: - JSON-RPC framing

    private func respond(id: Any?, result: [String: Any]) {
        var msg: [String: Any] = ["jsonrpc": "2.0", "result": result]
        if let id { msg["id"] = id }
        write(msg)
    }
    private func respondError(id: Any?, code: Int, message: String) {
        var msg: [String: Any] = ["jsonrpc": "2.0", "error": ["code": code, "message": message]]
        if let id { msg["id"] = id }
        write(msg)
    }
    private func write(_ object: [String: Any]) {
        guard let body = try? JSONSerialization.data(withJSONObject: object) else { return }
        let header = "Content-Length: \(body.count)\r\n\r\n"
        FileHandle.standardOutput.write(Data(header.utf8))
        FileHandle.standardOutput.write(body)
    }
}

/// Reads Content-Length-framed JSON-RPC messages from stdin (blocking).
final class FrameReader {
    private var buffer = Data()
    private let input = FileHandle.standardInput

    func next() -> String? {
        while true {
            if let message = extractFrame() { return message }
            let chunk = input.availableData
            if chunk.isEmpty { return nil } // EOF
            buffer.append(chunk)
        }
    }

    private func extractFrame() -> String? {
        guard let headerEnd = buffer.range(of: Data("\r\n\r\n".utf8)) else { return nil }
        let headerData = buffer.subdata(in: buffer.startIndex..<headerEnd.lowerBound)
        let header = String(decoding: headerData, as: UTF8.self)
        var length = 0
        for line in header.split(separator: "\r\n") where line.lowercased().hasPrefix("content-length:") {
            length = Int(line.split(separator: ":")[1].trimmingCharacters(in: .whitespaces)) ?? 0
        }
        let bodyStart = headerEnd.upperBound
        guard buffer.distance(from: bodyStart, to: buffer.endIndex) >= length else { return nil }
        let bodyEnd = buffer.index(bodyStart, offsetBy: length)
        let body = buffer.subdata(in: bodyStart..<bodyEnd)
        buffer.removeSubrange(buffer.startIndex..<bodyEnd)
        return String(decoding: body, as: UTF8.self)
    }
}
