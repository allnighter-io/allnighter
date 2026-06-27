import Foundation
import AllnighterCore
import AllnighterEngine

/// MCP resources + prompts (MCP_Tool_Upgrade.md §5B/§5C).
enum MCPResourceHandlers {
    enum ReadOutcome: Sendable {
        case success(String, mime: String)
        case toolError(ErrorEnvelope)
    }

    static func listResources() -> [[String: Any]] {
        [
            resource("contract", "allnighter://contract", "Contract manifest", "application/json"),
            resource("schemas", "allnighter://schemas/{tool}", "Per-tool I/O schema", "application/json"),
            resource("errors", "allnighter://errors", "Error catalog index", "application/json"),
            resource("error_rule", "allnighter://errors/{code}", "One error recovery rule", "application/json"),
            resource("help", "allnighter://help/{topic}", "Help topic body", "text/markdown"),
            resource("workflows", "allnighter://workflows", "Named workflow recipes", "application/json"),
            resource("project_context", "allnighter://projects/{projectId}/context", "Project context pack", "application/json"),
        ]
    }

    private static func resource(_ name: String, _ uri: String, _ description: String, _ mime: String) -> [String: Any] {
        ["uri": uri, "name": name, "description": description, "mimeType": mime]
    }

    static func listPrompts() -> [[String: Any]] {
        [
            prompt("run-sprint", "Run sprint", "Check defaults → project context → team_start(dryRun) → team_start → team_result",
                   [arg("project"), arg("lane"), arg("prompt")]),
            prompt("diagnose-environment", "Diagnose environment", "doctor → error_explain failures", []),
            prompt("resolve-stalls", "Resolve stalls", "stalled_list → stalled_update(check) → wait/dismiss", [arg("project")]),
        ]
    }

    private static func prompt(_ name: String, _ title: String, _ description: String, _ arguments: [[String: Any]]) -> [String: Any] {
        ["name": name, "title": title, "description": description, "arguments": arguments]
    }

    private static func arg(_ name: String, required: Bool = false) -> [String: Any] {
        ["name": name, "description": name, "required": required]
    }

    static func getPrompt(params: [String: Any]) -> [String: Any] {
        let name = params["name"] as? String ?? ""
        let args = params["arguments"] as? [String: Any] ?? [:]
        let text: String
        switch name {
        case "run-sprint":
            text = """
            1. defaults_get
            2. project_context(project: \(args["project"] as? String ?? "<project>"))
            3. team_start(dryRun:true, lane: \(args["lane"] as? String ?? "code"), prompt: \(args["prompt"] as? String ?? "<prompt>"))
            4. team_start → team_result → run_get
            """
        case "diagnose-environment":
            text = "1. doctor(full if needed)\n2. error_explain each failure code\n3. Retry blocked workflow"
        case "resolve-stalls":
            text = "1. stalled_list(project: \(args["project"] as? String ?? "optional"))\n2. stalled_update(action:check)\n3. ask user wait or dismiss"
        default:
            text = "Unknown prompt: \(name)"
        }
        return ["description": name, "messages": [["role": "user", "content": ["type": "text", "text": text]]]]
    }

    static func read(params: [String: Any], runtime: ToolRuntime) -> ReadOutcome {
        guard let uri = params["uri"] as? String else {
            return .toolError(ErrorEnvelope(code: "CLI_USAGE_ERROR", message: "uri required", requiresManual: true, retryable: false))
        }
        if uri == "allnighter://contract" {
            struct Manifest: Encodable {
                let contractVersion: String
                let contractHash: String
                let toolCount: Int
                let resourceCount: Int
                let promptCount: Int
            }
            let m = Manifest(
                contractVersion: ContractRegistry.contractVersion,
                contractHash: MCPWire.contractHash(tools: ContractRegistry.milestone1.mcpTools),
                toolCount: ContractRegistry.milestone1.mcpTools.count,
                resourceCount: listResources().count,
                promptCount: listPrompts().count
            )
            return .success(AllnighterCLI.jsonString(m), mime: "application/json")
        }
        if uri == "allnighter://errors" {
            let codes = ContractRegistry.milestone1.errors.map(\.code)
            return .success(AllnighterCLI.jsonString(codes), mime: "application/json")
        }
        if uri.hasPrefix("allnighter://errors/") {
            let code = String(uri.dropFirst("allnighter://errors/".count))
            guard let spec = ContractRegistry.milestone1.errors.first(where: { $0.code == code }) else {
                return .toolError(ErrorEnvelope(code: "CLI_USAGE_ERROR", message: "unknown error: \(code)", requiresManual: true, retryable: false))
            }
            return .success(AllnighterCLI.jsonString(ErrorHelpBridge.explain(spec, contractVersion: ContractRegistry.contractVersion)), mime: "application/json")
        }
        if uri.hasPrefix("allnighter://help/") {
            let topic = String(uri.dropFirst("allnighter://help/".count))
            let json = HelpProjector.get(topic: topic, contractVersion: ContractRegistry.contractVersion)
            return .success(AllnighterCLI.jsonString(json), mime: "application/json")
        }
        if uri == "allnighter://workflows" {
            return .success(AllnighterCLI.jsonString(AgentHello.defaultWorkflows), mime: "application/json")
        }
        if uri.hasPrefix("allnighter://schemas/") {
            let tool = String(uri.dropFirst("allnighter://schemas/".count))
            guard ContractRegistry.milestone1.mcpTools.contains(where: { $0.name == tool }) else {
                return .toolError(ErrorEnvelope(code: "CLI_USAGE_ERROR", message: "unknown tool: \(tool)", requiresManual: true, retryable: false))
            }
            struct Ref: Encodable { let tool: String; let outputSchema: String; let inputSchemaRef: String }
            let spec = ContractRegistry.milestone1.mcpTools.first { $0.name == tool }!
            return .success(AllnighterCLI.jsonString(Ref(tool: tool, outputSchema: spec.outputSchema.rawValue, inputSchemaRef: "wire:inputSchema")), mime: "application/json")
        }
        if uri.hasPrefix("allnighter://projects/"), uri.hasSuffix("/context") {
            let middle = uri.dropFirst("allnighter://projects/".count).dropLast("/context".count)
            switch MCPProjectHandlers.context(args: ["project": String(middle)]) {
            case .success(let json, _): return .success(json, mime: "application/json")
            case .toolError(let e): return .toolError(e)
            }
        }
        return .toolError(ErrorEnvelope(code: "CLI_USAGE_ERROR", message: "unknown resource uri: \(uri)", requiresManual: true, retryable: false))
    }
}
