import Foundation

/// Generates JSON Schema (draft 2020-12) for the public machine contracts
/// `TeamRunJSON` and `DoctorResult`
/// (docs/phases/CLI_Implementation_Contract.md §Generated Artifacts).
///
/// Structural schemas: top-level object + `$defs` for the primary nested objects,
/// with the closed enums enumerated. These are *generated* artifacts — a Mirror
/// drift test ties the top-level property sets back to the Swift types, so adding
/// or removing a field fails the wall until the schema is regenerated.
public enum ContractSchema {
    // MARK: - Tiny schema DSL

    private static var str: [String: Any] { ["type": "string"] }
    private static var int: [String: Any] { ["type": "integer"] }
    private static var bool: [String: Any] { ["type": "boolean"] }

    private static func obj(_ properties: [String: Any], required: [String]) -> [String: Any] {
        ["type": "object", "properties": properties, "required": required, "additionalProperties": false]
    }
    private static func arr(_ items: [String: Any]) -> [String: Any] { ["type": "array", "items": items] }
    private static func ref(_ name: String) -> [String: Any] { ["$ref": "#/$defs/\(name)"] }
    private static func enumStr(_ cases: [String]) -> [String: Any] { ["type": "string", "enum": cases] }
    /// A nullable leaf (`["string","null"]`); object/array nullables use `oneOf`.
    private static func nullable(_ type: String) -> [String: Any] { ["type": [type, "null"]] }
    private static func nullableRef(_ name: String) -> [String: Any] { ["oneOf": [ref(name), ["type": "null"]]] }

    private static var runStatus: [String: Any] { enumStr(["queued", "running", "done", "failed", "timedOut", "cancelled", "skipped", "interrupted"]) }
    /// Run-level status never includes `skipped` — only a worker/stage can be
    /// skipped (a manual-paste worker awaiting input). `interrupted` is a terminal
    /// orphan-recovery state (the owning process stopped before completion).
    private static var teamRunStatus: [String: Any] { enumStr(["queued", "running", "done", "failed", "timedOut", "cancelled", "interrupted"]) }

    // MARK: - TeamRunJSON

    public static func teamRunSchema() -> [String: Any] {
        var schema: [String: Any] = [
            "$schema": "https://json-schema.org/draft/2020-12/schema",
            "$id": "https://allnighter.app/schemas/team-run.schema.json",
            "title": "TeamRunJSON",
        ]
        let top = obj([
            "schemaVersion": int, "contractVersion": str,
            "teamRun": ref("RunInfo"), "models": arr(ref("ModelInfo")),
            "workers": arr(ref("WorkerInfo")), "workerAnswers": arr(ref("AnswerInfo")),
            "stages": arr(ref("StageInfo")), "plan": nullableRef("Plan"),
            "usage": ref("Usage"), "warnings": arr(ref("Warning")),
            "errors": arr(ref("ErrorEnvelope")), "nextActions": arr(ref("NextAction")),
            "audit": ref("Audit"),
        ], required: [
            "schemaVersion", "contractVersion", "teamRun", "models", "workers",
            "workerAnswers", "stages", "plan", "usage", "warnings", "errors", "nextActions", "audit",
        ])
        schema.merge(top) { _, new in new }
        schema["$defs"] = [
            "RunInfo": obj([
                "id": str, "status": teamRunStatus,
                "origin": enumStr(["cli", "gui", "mcp", "ios", "localApi", "system"]),
                "originAgent": nullable("string"), "lane": nullable("string"),
                "type": nullable("string"), "effort": nullable("string"),
                "prompt": str, "promptSource": ref("PromptSource"),
                "createdAt": str, "startedAt": nullable("string"), "completedAt": nullable("string"),
                "threadId": nullable("string"), "teamPresetId": nullable("string"),
                "teamDisplayName": nullable("string"), "outputKind": nullable("string"),
                "planWriterWorkerId": nullable("string"), "reproduceCommand": nullable("string"),
            ], required: ["id", "status", "origin", "prompt", "promptSource", "createdAt"]),
            "PromptSource": obj([
                "kind": enumStr(["positional", "file", "stdin"]), "path": nullable("string"),
            ], required: ["kind"]),
            "ModelInfo": obj([
                "id": str, "displayName": str, "sourceId": str,
                "sourceName": nullable("string"), "status": enumStr(["ready", "unavailable", "unknown"]),
            ], required: ["id", "displayName", "sourceId", "status"]),
            "WorkerInfo": obj([
                "id": str, "skillId": nullable("string"), "skillName": nullable("string"),
                "modelId": str, "modelName": str, "sourceId": str,
                "purpose": enumStr(["answer", "plan", "review"]), "instanceIndex": int,
            ], required: ["id", "modelId", "modelName", "sourceId", "purpose", "instanceIndex"]),
            "AnswerInfo": obj([
                "workerId": str, "modelId": nullable("string"), "status": runStatus,
                "durationMs": nullable("integer"), "markdown": nullable("string"),
                "error": nullableRef("ErrorEnvelope"),
            ], required: ["workerId", "status"]),
            "StageInfo": obj([
                "id": str, "purpose": enumStr(["analysis", "plan", "review"]), "status": runStatus,
                "producedByWorkerId": nullable("string"), "promptProfileId": nullable("string"),
            ], required: ["id", "purpose", "status"]),
            "Plan": obj([
                "status": runStatus, "writerWorkerId": nullable("string"),
                "stageId": nullable("string"), "markdown": str,
            ], required: ["status", "markdown"]),
            "Usage": obj(["cliCalls": int], required: ["cliCalls"]),
            "Warning": obj(["code": nullable("string"), "message": str], required: ["message"]),
            "ErrorEnvelope": errorEnvelopeDef(),
            "NextAction": obj([
                "kind": enumStr(["showRun", "export", "showHistory"]), "command": str, "label": nullable("string"),
            ], required: ["kind", "command"]),
            "Audit": obj(["traceId": str, "runJournalPath": str], required: ["traceId", "runJournalPath"]),
        ]
        return schema
    }

    // MARK: - DoctorResult

    public static func doctorResultSchema() -> [String: Any] {
        let docStatus = enumStr(["ok", "degraded", "critical"])
        var schema: [String: Any] = [
            "$schema": "https://json-schema.org/draft/2020-12/schema",
            "$id": "https://allnighter.app/schemas/doctor-result.schema.json",
            "title": "DoctorResult",
        ]
        let top = obj([
            "schemaVersion": int, "status": docStatus,
            "binaryVersion": str, "contractVersion": str, "docsVersionMatchesBinary": bool,
            "checks": arr(ref("Check")), "fixes": arr(ref("ErrorEnvelope")),
            "models": arr(ref("ModelInfo")), "coordinator": ref("Coordinator"),
        ], required: [
            "schemaVersion", "status", "binaryVersion", "contractVersion",
            "docsVersionMatchesBinary", "checks", "fixes", "models", "coordinator",
        ])
        schema.merge(top) { _, new in new }
        schema["$defs"] = [
            "Check": obj([
                "name": str, "status": enumStr(["ok", "degraded", "critical", "notChecked"]), "detail": str,
                "fixCommand": nullable("string"), "requiresManual": bool,
            ], required: ["name", "status", "detail", "requiresManual"]),
            "Coordinator": obj([
                "state": enumStr(["foregroundOnly", "available", "unavailable"]),
                "available": bool, "detail": str,
                "coordinatorId": nullable("string"), "pid": nullable("integer"),
                "startedAt": nullable("string"),
            ], required: ["state", "available", "detail"]),
            "ModelInfo": obj([
                "id": str, "displayName": str, "sourceId": str,
                "sourceName": nullable("string"), "status": enumStr(["ready", "unavailable", "unknown"]),
            ], required: ["id", "displayName", "sourceId", "status"]),
            "ErrorEnvelope": errorEnvelopeDef(),
        ]
        return schema
    }

    private static func errorEnvelopeDef() -> [String: Any] {
        obj([
            "code": str, "ruleId": nullable("string"), "message": str,
            "agentAction": nullable("string"), "fixCommand": nullable("string"),
            "requiresManual": bool, "retryable": bool, "traceId": nullable("string"),
            "runId": nullable("string"), "sourceId": nullable("string"),
            "modelId": nullable("string"), "workerId": nullable("string"),
        ], required: ["code", "message", "requiresManual", "retryable"])
    }

    // MARK: - CoordinatorHealth

    public static func coordinatorHealthSchema() -> [String: Any] {
        var schema: [String: Any] = [
            "$schema": "https://json-schema.org/draft/2020-12/schema",
            "$id": "https://allnighter.app/schemas/coordinator-health.schema.json",
            "title": "CoordinatorHealth",
        ]
        let top = obj([
            "schemaVersion": int,
            "state": enumStr(["foregroundOnly", "available", "unavailable"]),
            "coordinatorId": nullable("string"),
            "pid": nullable("integer"),
            "startedAt": nullable("string"),
            "contractVersion": str,
            "binaryVersion": str,
            "journal": ref("Journal"),
            "loopback": ref("Loopback"),
            "activeObligationCount": int,
        ], required: [
            "schemaVersion", "state", "contractVersion", "binaryVersion",
            "journal", "loopback", "activeObligationCount",
        ])
        schema.merge(top) { _, new in new }
        schema["$defs"] = [
            "Journal": obj([
                "incrementalDurable": bool, "orphanRecovery": bool, "runsDirWritable": bool,
            ], required: ["incrementalDurable", "orphanRecovery", "runsDirWritable"]),
            "Loopback": obj([
                "listening": bool, "host": str, "port": nullable("integer"),
            ], required: ["listening", "host"]),
        ]
        return schema
    }

    // MARK: - Deterministic serialization

    public static func json(_ schema: [String: Any]) throws -> String {
        let data = try JSONSerialization.data(withJSONObject: schema, options: [.prettyPrinted, .sortedKeys])
        return String(decoding: data, as: UTF8.self) + "\n"
    }
}
