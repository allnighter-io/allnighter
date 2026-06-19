import Foundation
import AllnighterCore
import AllnighterEngine

/// A minimal MCP stdio server exposing the team as tools any MCP-aware agent can call.
struct MCPServer {
    let runtime: ToolRuntime
    static let protocolVersion = "2024-11-05"

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
                    "serverInfo": ["name": "alln", "version": "0.6"],
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
            respond(id: id, result: toolText("Team catalog", structured: AllnighterCLI.teamsCatalogJSONString(runtime, lane: lane)))
        case "teams_show":
            guard let teamId = args["teamId"] as? String, let team = TeamCatalog.get(teamId) else {
                return respondToolError(id: id, code: "TEAM_NOT_FOUND", message: "teamId required")
            }
            respond(id: id, result: toolText(team.displayName, structured: AllnighterCLI.teamShowJSONString(team)))
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
            guard TeamCatalog.get(teamId) != nil else {
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
        case "team_ask":
            guard let q = args["question"] as? String else { return respondToolError(id: id, code: "CLI_USAGE_ERROR", message: "question required") }
            let req = TeamRequest(
                question: q,
                lane: (args["lane"] as? String).flatMap(WorkLane.init(rawValue:)),
                teamPresetId: (args["team"] as? String) ?? (args["preset"] as? String),
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
            let ref = (args["run"] as? String) ?? "latest"
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
            respond(id: id, result: toolText("\(spec.code): \(spec.agentAction)", structured: AllnighterCLI.jsonString(spec)))
        case "spec_get":
            let ref = (args["run"] as? String) ?? "latest"
            guard let run = AllnighterCLI.resolveRun(ref) else {
                return respondToolError(id: id, code: "RUN_NOT_FOUND", message: "no run matches \(ref)")
            }
            let result = AllnighterCLI.specResult(run, runtime: runtime, detail: args["detail"] as? String)
            respond(id: id, result: toolText(result.summary, structured: AllnighterCLI.jsonString(result)))
        case "floor_show":
            let ref = (args["run"] as? String) ?? "latest"
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
            guard let threadId = args["threadId"] as? String else {
                return respondToolError(id: id, code: "CLI_USAGE_ERROR", message: "threadId required")
            }
            guard let thread = ThreadStore().get(threadId) else {
                return respondToolError(id: id, code: "CLI_USAGE_ERROR", message: "thread not found")
            }
            respond(id: id, result: toolText(thread.title, structured: AllnighterCLI.jsonString(thread)))
        case "thread_status":
            guard let threadId = args["threadId"] as? String else {
                return respondToolError(id: id, code: "CLI_USAGE_ERROR", message: "threadId required")
            }
            guard let thread = ThreadStore().get(threadId) else {
                return respondToolError(id: id, code: "CLI_USAGE_ERROR", message: "thread not found")
            }
            let running = thread.isRunning
            let status = ThreadStatusResponse(threadId: threadId, isRunning: running, needsAttention: thread.needsAttention)
            respond(id: id, result: toolText(running ? "running" : "idle", structured: AllnighterCLI.jsonString(status)))
        case "pending_list":
            respondPending(id: id, outcome: MCPPendingHandlers.list(runtime: runtime, args: args))
        case "pending_show":
            respondPending(id: id, outcome: MCPPendingHandlers.show(runtime: runtime, args: args))
        case "pending_run":
            await respondPending(id: id, outcome: await MCPPendingHandlers.run(runtime: runtime, args: args))
        default:
            respondError(id: id, code: -32602, message: "unknown tool: \(name)")
        }
    }

    /// Tool descriptors derive from the contract registry — no MCP-only schemas.
    private func toolDefinitions() -> [[String: Any]] {
        ContractRegistry.milestone1.mcpTools.map { tool in
            var properties: [String: Any] = [:]
            var required: [String] = []
            for p in tool.params {
                var property: [String: Any] = ["type": p.type, "description": p.summary]
                if let arrayItems = p.arrayItems {
                    property["items"] = ["oneOf": arrayItems.oneOf.map { item -> [String: Any] in
                        var spec: [String: Any] = [:]
                        if let type = item.type { spec["type"] = type }
                        if let properties = item.properties {
                            spec["properties"] = properties.mapValues { ["type": $0.type] }
                        }
                        if let required = item.required { spec["required"] = required }
                        return spec
                    }]
                }
                properties[p.name] = property
                if p.required { required.append(p.name) }
            }
            var schema: [String: Any] = ["type": "object", "properties": properties]
            if !required.isEmpty { schema["required"] = required }
            return ["name": tool.name, "description": tool.summary, "inputSchema": schema]
        }
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

    private func respondPending(id: Any?, outcome: MCPPendingHandlers.Outcome) {
        switch outcome {
        case .success(let json, let summary):
            respond(id: id, result: toolText(summary, structured: json))
        case .toolError(let envelope):
            respondToolError(id: id, code: envelope.code, message: envelope.message)
        }
    }

    private func respondToolError(id: Any?, code: String, message: String) {
        let envelope = ErrorEnvelope(code: code, message: message, requiresManual: code == "RUN_NOT_FOUND", retryable: false)
        respond(id: id, result: [
            "content": [["type": "text", "text": "\(code): \(message)"]],
            "isError": true,
            "structuredContent": ["error": AllnighterCLI.jsonString(envelope)],
        ])
    }

    private func toolText(_ text: String, structured: String? = nil) -> [String: Any] {
        var result: [String: Any] = ["content": [["type": "text", "text": text]]]
        if let structured { result["structuredContent"] = ["json": structured] }
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
