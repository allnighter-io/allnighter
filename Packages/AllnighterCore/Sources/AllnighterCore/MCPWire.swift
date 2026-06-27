import CryptoKit
import Foundation

/// MCP wire-protocol helpers (MCP_Tool_Upgrade.md §6–§8). Registry owns truth;
/// this module projects Cursor-safe `tools/list` descriptors and validates them.
public enum MCPWire {
    public static let protocolVersion = "2025-06-18"
    public static let serverVersion = "1.0"

    /// Stable hash over tool names + contract version — agents detect stale cached schemas.
    public static func contractHash(tools: [ContractRegistry.MCPToolSpec]) -> String {
        let payload = ContractRegistry.contractVersion + "\n" + tools.map(\.name).joined(separator: "\n")
        let digest = SHA256.hash(data: Data(payload.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    /// Build MCP `tools/list` descriptors. Never emits wire `outputSchema` (§6.7).
    public static func toolDefinitions(from tools: [ContractRegistry.MCPToolSpec]) -> [[String: Any]] {
        tools.map { tool in
            var def: [String: Any] = [
                "name": tool.name,
                "title": tool.wireTitle,
                "description": tool.summary,
                "inputSchema": tool.wireInputSchema(),
            ]
            let annotations = tool.wireAnnotations()
            if !annotations.isEmpty { def["annotations"] = annotations }
            return def
        }
    }

    /// Parse a JSON string into a typed object for `structuredContent`, or omit on failure.
    public static func typedStructuredContent(_ json: String) -> Any? {
        guard let data = json.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) else { return nil }
        return obj
    }

    /// Cursor-compat lint: one invalid tool zeros the entire list (§6.7 / T7.7).
    public static func wireValidationIssues(tools: [ContractRegistry.MCPToolSpec]) -> [String] {
        var issues: [String] = []
        for tool in tools {
            if toolDefinitions(from: [tool]).first?["outputSchema"] != nil {
                issues.append("\(tool.name): wire outputSchema is forbidden until T7.7")
            }
            issues.append(contentsOf: inputSchemaIssues(tool: tool.name, schema: tool.wireInputSchema()))
        }
        return issues
    }

    private static func inputSchemaIssues(tool: String, schema: [String: Any]) -> [String] {
        var issues: [String] = []
        if schema["type"] as? String != "object" {
            issues.append("\(tool).inputSchema: root type must be object")
        }
        guard let properties = schema["properties"] as? [String: Any] else { return issues }
        for (name, raw) in properties {
            guard let prop = raw as? [String: Any] else { continue }
            let type = prop["type"] as? String
            if type == "array", prop["items"] == nil {
                issues.append("\(tool).\(name): array missing items")
            }
            if type == "object", prop["properties"] == nil {
                issues.append("\(tool).\(name): object missing properties")
            }
        }
        return issues
    }

    /// Enrich a tool failure with catalog metadata + help routing for wire emission.
    public static func toolErrorStructuredContent(code: String, message: String) -> [String: Any] {
        let spec = ContractRegistry.milestone1.errors.first { $0.code == code }
        let envelope = ErrorEnvelope(
            code: code,
            ruleId: spec?.ruleId,
            message: message,
            agentAction: spec?.agentAction,
            requiresManual: spec?.requiresManual ?? (code == "RUN_NOT_FOUND"),
            retryable: spec?.retryable ?? false
        )
        var errorObj: Any = envelope
        if let data = try? CoreJSON.encode(envelope),
           let decoded = try? JSONSerialization.jsonObject(with: data) {
            errorObj = decoded
        }
        var structured: [String: Any] = ["error": errorObj]
        if let spec {
            let explain = ErrorHelpBridge.explain(spec, contractVersion: ContractRegistry.contractVersion)
            if let helpRef = explain.helpRef { structured["helpRef"] = helpRef }
            if let step = explain.nextToolPlan.first {
                structured["nextTool"] = step.tool
                if !step.args.isEmpty { structured["nextToolArgs"] = step.args }
            }
        }
        return structured
    }
}

public extension ContractRegistry.MCPToolSpec {
    var wireTitle: String {
        if let title { return title }
        return name.split(separator: "_").map { part in
            part.prefix(1).uppercased() + part.dropFirst()
        }.joined(separator: " ")
    }

    func wireInputSchema() -> [String: Any] {
        var properties: [String: Any] = [:]
        var required: [String] = []
        for p in params {
            var property: [String: Any] = ["type": p.type, "description": p.summary]
            if p.type == "array" {
                if let arrayItems = p.arrayItems {
                    property["items"] = ["oneOf": arrayItems.oneOf.map { item -> [String: Any] in
                        var spec: [String: Any] = [:]
                        if let type = item.type { spec["type"] = type }
                        if let properties = item.properties {
                            spec["properties"] = properties.mapValues { ["type": $0.type] }
                            spec["additionalProperties"] = false
                        }
                        if let required = item.required { spec["required"] = required }
                        return spec
                    }]
                } else {
                    property["items"] = ["type": "string"]
                }
            }
            if p.type == "object" {
                property["properties"] = [String: Any]()
                property["additionalProperties"] = true
            }
            properties[p.name] = property
            if p.required { required.append(p.name) }
        }
        var schema: [String: Any] = ["type": "object", "properties": properties, "additionalProperties": false]
        if !required.isEmpty { schema["required"] = required }
        return schema
    }

    func wireAnnotations() -> [String: Any] {
        var ann: [String: Any] = [:]
        if MCPWireCatalog.readOnly.contains(name) {
            ann["readOnlyHint"] = true
        }
        if MCPWireCatalog.destructive.contains(name) {
            ann["destructiveHint"] = true
            ann["openWorldHint"] = true
        }
        switch idempotency {
        case .idempotent: ann["idempotentHint"] = true
        case .keyed, .notIdempotent: ann["idempotentHint"] = false
        }
        return ann
    }
}

/// Per-tool annotation hints — updated on Slice 1 surface cut.
enum MCPWireCatalog {
    static let destructive: Set<String> = [
        "team_run", "team_start", "team_ask", "pending_run", "thread_send", "thread_rename",
        "pair_run", "pair_slice", "teams_save", "teams_delete", "teams_duplicate",
        "teams_set_default", "teams_restore", "skills_save", "skills_delete", "skills_duplicate",
        "pending_submit", "pending_edit", "pending_cancel", "pending_reorder", "pending_run",
        "boost_window_set", "boost_window_seed", "boost_window_observations_clear",
        "stall_check_status", "stall_keep_waiting", "stall_dismiss", "project_recheck_workers",
        "teams_edit", "skills_edit", "pending_update", "stalled_update",
    ]

    static let readOnly: Set<String> = [
        "mcp_hello", "doctor", "error_explain", "help", "help_search", "help_get",
        "defaults_get", "history", "team_preflight", "team_status", "team_result", "team_cancel",
        "teams_list", "teams_show", "teams_definition", "skills_list", "skills_show",
        "show", "spec_get", "floor_show", "pair_status", "thread_get", "thread_status",
        "thread_attachment_get", "pending_list", "pending_show", "pending_queue",
        "stalled_list", "project_stalled", "project_list", "project_get", "project_context",
        "project_workers", "team_show", "boost_window_show",
        "teams_get", "skills_get", "run_get", "stalled_list",
    ]
}
