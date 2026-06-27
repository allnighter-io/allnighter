import Foundation
import AllnighterCore
import AllnighterEngine

/// MCP stdio server — 30-tool surface + resources/prompts (MCP_Tool_Upgrade.md).
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
                    "capabilities": [
                        "tools": [:],
                        "resources": [:],
                        "prompts": [:],
                    ],
                ])
            case "tools/list":
                respond(id: id, result: ["tools": toolDefinitions()])
            case "tools/call":
                await handleCall(id: id, params: params)
            case "resources/list":
                respond(id: id, result: ["resources": MCPResourceHandlers.listResources()])
            case "resources/read":
                await handleResourceRead(id: id, params: params)
            case "prompts/list":
                respond(id: id, result: ["prompts": MCPResourceHandlers.listPrompts()])
            case "prompts/get":
                respond(id: id, result: MCPResourceHandlers.getPrompt(params: params))
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

        switch name {
        case "mcp_hello":
            let verdict = AgentReadiness.evaluate(teams: runtime.teams, readyModels: runtime.readyModels)
            let text = verdict.canStartTeamRun
                ? "Ready. \(verdict.readyTeams.count) team(s) can start."
                : "Not ready: \(verdict.blockedReason ?? "see doctor")."
            respond(id: id, result: toolText(text, structured: AllnighterCLI.mcpHelloJSONString(runtime)))

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

        case "help":
            respondMerged(id: id, outcome: MCPMergedHandlers.help(args: args))

        case "defaults_get":
            respondDefaults(id: id, outcome: MCPDefaultsHandlers.get(runtime: runtime))

        case "history":
            guard let query = args["query"] as? String, !query.isEmpty else {
                return respondToolError(id: id, code: "CLI_USAGE_ERROR", message: "query required")
            }
            let service = runtime.service()
            let hits = await service.recall(query: query)
            let text = hits.isEmpty ? "(no prior team runs match)" : hits.map { "\($0.createdAt) \($0.prompt)" }.joined(separator: "\n")
            let payload = HistoryJSON(contractVersion: ContractRegistry.contractVersion, query: query, results: hits)
            respond(id: id, result: toolText(text, structured: AllnighterCLI.jsonString(payload)))

        case "teams_get":
            respondMerged(id: id, outcome: MCPMergedHandlers.teamsGet(runtime: runtime, args: args))
        case "teams_edit":
            respondMerged(id: id, outcome: MCPMergedHandlers.teamsEdit(args: args))
        case "skills_get":
            respondMerged(id: id, outcome: MCPMergedHandlers.skillsGet(args: args))
        case "skills_edit":
            respondMerged(id: id, outcome: MCPMergedHandlers.skillsEdit(args: args))

        case "team_ask":
            guard let q = args["question"] as? String else {
                return respondToolError(id: id, code: "CLI_USAGE_ERROR", message: "question required")
            }
            let req = TeamRequest(
                question: q,
                lane: (args["lane"] as? String).flatMap(WorkLane.init(rawValue:)),
                teamPresetId: args["team"] as? String,
                effort: (args["effort"] as? String).flatMap(EffortLevel.init(rawValue:)),
                type: args["type"] as? String,
                context: args["context"] as? String
            )
            let service = runtime.service()
            let result = await service.run(req, origin: .mcp, originAgent: agent)
            guard !result.runId.isEmpty else {
                return respondToolError(id: id, code: result.errorCode ?? "DEFAULT_TEAM_INVALID",
                                      message: result.note.isEmpty ? "team run did not start" : result.note)
            }
            guard let run = AllnighterCLI.loadRun(result.runId) else {
                return respondToolError(id: id, code: "RUN_NOT_FOUND", message: "team run did not persist")
            }
            let trj = TeamRunJSONMapper.map(run, models: runtime.models, manifests: runtime.registry.all,
                                            context: AllnighterCLI.defaultRunContext(run))
            respond(id: id, result: toolText(run.plan ?? "(no plan — status \(run.status.rawValue))",
                                             structured: AllnighterCLI.jsonString(trj)))

        case "team_run":
            await respondRun(id: id, outcome: await MCPRunHandlers.run(runtime: runtime, args: args, defaultAgent: agent))
        case "team_start":
            await respondAsyncTeam(id: id, outcome: await MCPAsyncTeamHandlers.start(runtime: runtime, args: args, defaultAgent: agent))
        case "team_result":
            await respondAsyncTeam(id: id, outcome: await MCPAsyncTeamHandlers.result(runtime: runtime, args: args))
        case "team_cancel":
            await respondAsyncTeam(id: id, outcome: await MCPAsyncTeamHandlers.cancel(runtime: runtime, args: args))

        case "run_get":
            respondMerged(id: id, outcome: MCPMergedHandlers.runGet(runtime: runtime, args: args))

        case "pair_run":
            await respondMerged(id: id, outcome: await MCPMergedHandlers.pairRun(runtime: runtime, args: args))
        case "pair_status":
            await respondPair(id: id, outcome: MCPPairHandlers.status(runtime: runtime, args: args))

        case "thread_send":
            let outcome = await MCPThreadSendHandlers.runSend(args: args, runtime: runtime)
            switch outcome {
            case .success(let response):
                respond(id: id, result: toolText("thread send ok", structured: AllnighterCLI.jsonString(response)))
            case .failure(let envelope):
                respondToolError(id: id, code: envelope.code, message: envelope.message)
            }
        case "thread_get":
            respondMerged(id: id, outcome: MCPMergedHandlers.threadGet(args: args))
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
            } catch {
                respondToolError(id: id, code: "THREAD_NOT_FOUND", message: "\(error)")
            }

        case "pending_list":
            respondMerged(id: id, outcome: MCPMergedHandlers.pendingList(runtime: runtime, args: args))
        case "pending_edit":
            respondPending(id: id, outcome: MCPPendingHandlers.edit(runtime: runtime, args: args))
        case "pending_update":
            respondMerged(id: id, outcome: MCPMergedHandlers.pendingUpdate(runtime: runtime, args: args))
        case "pending_run":
            await respondPending(id: id, outcome: await MCPPendingHandlers.run(runtime: runtime, args: args))

        case "stalled_list":
            respondMerged(id: id, outcome: MCPMergedHandlers.stalledList(args: args))
        case "stalled_update":
            respondMerged(id: id, outcome: MCPMergedHandlers.stalledUpdate(args: args))

        case "project_get":
            respondMerged(id: id, outcome: MCPMergedHandlers.projectGet(args: args))
        case "project_context":
            respondProject(id: id, outcome: MCPProjectHandlers.context(args: args))
        case "project_workers":
            await respondMerged(id: id, outcome: await MCPMergedHandlers.projectWorkers(runtime: runtime, args: args))

        default:
            respondError(id: id, code: -32602, message: "unknown tool: \(name)")
        }
    }

    private func handleResourceRead(id: Any?, params: [String: Any]) async {
        switch MCPResourceHandlers.read(params: params, runtime: runtime) {
        case .success(let contents, let mime):
            respond(id: id, result: [
                "contents": [[
                    "uri": params["uri"] as? String ?? "",
                    "mimeType": mime,
                    "text": contents,
                ]],
            ])
        case .toolError(let envelope):
            respondToolError(id: id, code: envelope.code, message: envelope.message)
        }
    }

    private func toolDefinitions() -> [[String: Any]] {
        MCPWire.toolDefinitions(from: ContractRegistry.milestone1.mcpTools)
    }

    private func respondMerged(id: Any?, outcome: MCPMergedHandlers.Outcome) {
        switch outcome {
        case .success(let json, let summary):
            respond(id: id, result: toolText(summary, structured: json))
        case .toolError(let envelope):
            respondToolError(id: id, code: envelope.code, message: envelope.message)
        }
    }

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

    private func respondDefaults(id: Any?, outcome: MCPDefaultsHandlers.Outcome) {
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
            if chunk.isEmpty { return nil }
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
