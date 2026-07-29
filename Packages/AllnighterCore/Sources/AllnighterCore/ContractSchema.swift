import Foundation

/// Generates JSON Schema (draft 2020-12) for the public machine contracts
/// `TeamRunJSON` and `DoctorResult`
/// (docs/archive/phases/CLI_Implementation_Contract.md §Generated Artifacts).
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
    /// A nullable enum: one of the string cases, or null (a `oneOf`, since a bare
    /// `["string","null"]` + `enum` would exclude null from the enum list).
    private static func nullableEnum(_ cases: [String]) -> [String: Any] {
        ["oneOf": [enumStr(cases), ["type": "null"]]]
    }

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
            "teamRun": ref("RunInfo"),
            "workers": arr(ref("WorkerInfo")), "answers": arr(ref("AnswerInfo")),
            "answer": nullableRef("Answer"),
            "stages": arr(ref("StageInfo")), "plan": nullableRef("Plan"),
            "designBoard": nullableRef("DesignBoard"),
            "repoDelta": nullableRef("RepoDelta"),
            "researchGitObservation": nullableRef("ResearchGitObservation"),
            "outcome": nullableRef("Outcome"),
            "usage": ref("Usage"), "warnings": arr(ref("Warning")),
            "errors": arr(ref("ErrorEnvelope")), "nextActions": arr(ref("NextAction")),
            "audit": ref("Audit"),
        ], required: [
            "schemaVersion", "contractVersion", "teamRun", "workers",
            "answers", "answer", "stages", "plan", "usage", "warnings", "errors", "nextActions", "audit",
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
                "workerId": nullable("string"), "writePolicy": nullable("string"),
                "identitySummary": nullable("string"),
                "planWriterWorkerId": nullable("string"), "reproduceCommand": nullable("string"),
                "endReason": nullable("string"), "blocker": nullableRef("BlockerJSON"),
                "attempts": arr(ref("RunAttempt")),
            ], required: ["id", "status", "origin", "prompt", "promptSource", "createdAt", "attempts"]),
            "BlockerJSON": obj([
                "resource": enumStr(["repoWriteLock", "teamGovernor", "driverCapacity", "vendorBackoff"]),
                "scopeRoot": nullable("string"), "holderId": nullable("string"), "holderKind": nullable("string"),
                "ticketPosition": nullable("integer"), "holderAcquiredAt": nullable("string"),
                "heldSinceSeconds": nullable("number"), "holderDeadlineAt": nullable("string"),
                "quotaScope": nullable("string"), "wakeAfter": nullable("string"),
                "capacityObservation": nullableRef("CapacityObservation"),
            // scopeRoot required only for write-lock waits; vendorBackoff uses quotaScope.
            ], required: ["resource"]),
            "RunAttempt": obj([
                "attemptNumber": int,
                "requestedSourceId": nullable("string"), "requestedModelId": nullable("string"),
                "resolvedSourceId": nullable("string"), "resolvedModelId": nullable("string"),
                "startedAt": str, "endedAt": nullable("string"),
                "capacityObservation": nullableRef("CapacityObservation"),
                "vendorSessionId": nullable("string"), "selectionOrigin": nullable("string"),
                "substitutionOfAttempt": nullable("integer"), "terminalStatus": nullableEnum([
                    "queued", "running", "done", "failed", "timedOut", "cancelled", "skipped", "interrupted",
                ]),
                "reason": nullable("string"), "diagnosticSnippet": nullable("string"),
            ], required: ["attemptNumber", "startedAt"]),
            "CapacityObservation": obj([
                "kind": enumStr([
                    "accountRateLimit", "providerBusy", "cooldown", "authRequired",
                    "manualRequired", "unknownCapacity",
                ]),
                "source": str,
                "sourceConfidence": enumStr(["structured", "messageFallback", "localPolicy", "unknown"]),
                "rawSnippet": str, "observedAt": str,
                "observedResetAt": nullable("string"), "retryAfterSeconds": nullable("integer"),
                "wakeAfter": nullable("string"),
            ], required: ["kind", "source", "sourceConfidence", "rawSnippet", "observedAt"]),
            "PromptSource": obj([
                "kind": enumStr(["positional", "file", "stdin"]), "path": nullable("string"),
            ], required: ["kind"]),
            "ModelInfo": obj([
                "id": str, "displayName": str, "sourceId": str,
                "sourceName": nullable("string"), "status": enumStr(["ready", "unavailable", "unknown"]),
            ], required: ["id", "displayName", "sourceId", "status"]),
            "WorkerInfo": obj([
                "id": str, "skillId": nullable("string"), "skillName": nullable("string"),
                "resolvedWorkerPromptSnapshot": nullable("string"),
                "modelId": str, "modelName": str, "sourceId": str,
                "purpose": enumStr(["answer", "plan", "review"]), "instanceIndex": int,
            ], required: ["id", "modelId", "modelName", "sourceId", "purpose", "instanceIndex"]),
            "AnswerInfo": obj([
                "agentId": str, "modelId": nullable("string"), "status": runStatus,
                "queueMs": nullable("integer"), "ttftMs": nullable("integer"),
                "durationMs": nullable("integer"), "markdown": nullable("string"),
                "error": nullableRef("ErrorEnvelope"),
            ], required: ["agentId", "status"]),
            "Answer": obj([
                "status": runStatus,
                "outputKind": nullable("string"),
                "markdown": nullable("string"),
                "source": ref("AnswerSource"),
                "typedResultField": nullable("string"),
            ], required: ["status", "source"]),
            "AnswerSource": obj([
                "kind": enumStr(["plan", "worker", "typed"]),
                "workerId": nullable("string"),
                "modelId": nullable("string"),
                "stageId": nullable("string"),
            ], required: ["kind"]),
            "StageInfo": obj([
                "id": str, "purpose": enumStr(["analysis", "plan", "review"]), "status": runStatus,
                "producedByAgentId": nullable("string"), "promptProfileId": nullable("string"),
            ], required: ["id", "purpose", "status"]),
            "Plan": obj([
                "status": runStatus, "writerWorkerId": nullable("string"),
                "stageId": nullable("string"), "markdown": nullable("string"),
            ], required: ["status"]),
            "DesignBoard": obj([
                "targetShape": str, "screenshotPath": nullable("string"),
                "screenshotAbsolutePath": nullable("string"),
                "options": arr(ref("DesignBoardOption")), "chosen": nullableRef("DesignBoardChosen"),
            ], required: ["targetShape", "options"]),
            "DesignBoardOption": obj([
                "workerId": str, "modelId": str, "persona": str,
                "imagePath": nullable("string"), "absolutePath": nullable("string"),
                "status": runStatus, "failureReason": nullable("string"), "sessionId": nullable("string"),
            ], required: ["workerId", "modelId", "persona", "status"]),
            "DesignBoardChosen": obj([
                "workerId": str, "persona": str, "chosenAt": nullable("string"),
            ], required: ["workerId", "persona"]),
            "RepoDelta": obj([
                "changed": bool, "baseline": nullable("string"), "head": nullable("string"),
                "commits": arr(ref("RepoDeltaCommit")),
                "filesChanged": int, "files": arr(str), "truncated": bool,
            ], required: ["changed", "commits", "filesChanged", "files", "truncated"]),
            "RepoDeltaCommit": obj([
                "sha": str, "subject": str,
            ], required: ["sha", "subject"]),
            "ResearchGitObservation": obj([
                "changed": bool, "baselineHead": nullable("string"), "head": nullable("string"),
                "changedPaths": arr(str), "truncated": bool,
            ], required: ["changed", "changedPaths", "truncated"]),
            "Outcome": obj([
                "status": enumStr(["completed", "partial", "failed", "timedOut"]),
                "committed": bool, "headline": str,
                "commitMessageMatched": nullable("boolean"),
                "proof": nullableRef("OutcomeProof"),
                "usage": nullableRef("OutcomeTokenUsage"),
                "timing": nullableRef("OutcomeTiming"),
            ], required: ["status", "committed", "headline"]),
            "OutcomeProof": obj([
                "command": str, "exitCode": nullable("integer"), "passed": bool, "outputTail": str,
            ], required: ["command", "passed", "outputTail"]),
            "OutcomeTokenUsage": obj([
                "inputTokens": nullable("integer"), "outputTokens": nullable("integer"),
            ], required: []),
            "OutcomeTiming": obj([
                "wallMs": nullable("integer"),
            ], required: []),
            "Usage": obj(["cliCalls": int], required: ["cliCalls"]),
            "Warning": obj(["code": nullable("string"), "message": str], required: ["message"]),
            "ErrorEnvelope": errorEnvelopeDef(),
            "NextAction": obj([
                "kind": enumStr(["showArtifact", "showRun", "export", "showHistory"]), "command": str, "label": nullable("string"),
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
            "counsel": nullable("string"),
            "nextActions": arr(ref("AgentSurfaceNextAction")),
        ], required: [
            "schemaVersion", "status", "binaryVersion", "contractVersion",
            "docsVersionMatchesBinary", "checks", "fixes", "models", "coordinator", "nextActions",
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
            "AgentSurfaceNextAction": agentSurfaceNextActionDef(),
        ]
        return schema
    }

    private static func errorEnvelopeDef() -> [String: Any] {
        let candidate = obj([
            "id": str,
            "displayName": str,
            "driverId": nullable("string"),
            "state": str,
        ], required: ["id", "displayName", "state"])
        return obj([
            "code": str, "ruleId": nullable("string"), "message": str,
            "agentAction": nullable("string"), "fixCommand": nullable("string"),
            "requiresManual": bool, "retryable": bool, "traceId": nullable("string"),
            "runId": nullable("string"), "sourceId": nullable("string"),
            "modelId": nullable("string"), "workerId": nullable("string"),
            "supportDir": nullable("string"),
            "suggestions": arr(str),
            "candidates": arr(candidate),
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
            "daemonId": nullable("string"),
            "pid": nullable("integer"),
            "startedAt": nullable("string"),
            "contractVersion": str,
            "binaryVersion": str,
            "binaryGitSha": str,
            "journal": ref("Journal"),
            "loopback": ref("Loopback"),
            "activeObligationCount": int,
        ], required: [
            "schemaVersion", "state", "contractVersion", "binaryVersion", "binaryGitSha",
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

    // MARK: - PendingItemJSON

    public static func pendingItemSchema() -> [String: Any] {
        var schema: [String: Any] = [
            "$schema": "https://json-schema.org/draft/2020-12/schema",
            "$id": "https://allnighter.app/schemas/pending-item.schema.json",
            "title": "PendingItemJSON",
        ]
        let top = obj([
            "schemaVersion": int, "contractVersion": str,
            "pendingItem": ref("ItemInfo"), "target": ref("TargetInfo"),
            "policy": ref("PolicyInfo"),
            "safety": ref("SafetyInfo"), "admission": nullableRef("AdmissionInfo"),
            "capacityObservation": nullableRef("CapacityObservationInfo"),
            "attempts": arr(ref("AttemptInfo")), "nextActions": arr(ref("NextAction")),
            "audit": ref("AuditInfo"),
        ], required: [
            "schemaVersion", "contractVersion", "pendingItem", "target", "policy",
            "safety", "attempts", "nextActions", "audit",
        ])
        schema.merge(top) { _, new in new }
        schema["$defs"] = [
            "ItemInfo": obj([
                "id": str, "status": enumStr(["draft", "pending", "running", "done", "failed", "cancelled"]),
                "title": str, "kind": enumStr(["workerChat", "teamRun", "followUp"]),
                "origin": enumStr(["cli", "gui", "mcp", "ios", "localApi", "system", "preset"]),
                "threadId": nullable("string"), "promptExcerpt": str,
                "createdAt": str, "updatedAt": str, "nextWakeAt": nullable("string"),
                "blockedReason": nullable("string"), "needsAttention": bool,
            ], required: ["id", "status", "title", "kind", "origin", "promptExcerpt", "createdAt", "updatedAt", "needsAttention"]),
            "TargetInfo": obj([
                "workerIds": arr(str), "teamPresetId": nullable("string"),
                "preferredWorkerIds": arr(str), "fallbackWorkerIds": arr(str),
                "requiredWorkerIds": arr(str), "minWorkers": nullable("integer"),
            ], required: ["workerIds", "preferredWorkerIds", "fallbackWorkerIds", "requiredWorkerIds"]),
            "PolicyInfo": obj([
                "selection": str, "attentionMode": str, "drainMode": str,
                "maxAttempts": nullable("integer"), "retryFloorSeconds": nullable("integer"),
                "allowDegraded": bool, "requireKnownAvailable": bool, "createSuggestedFollowUps": bool,
            ], required: ["selection", "attentionMode", "drainMode", "allowDegraded", "requireKnownAvailable", "createSuggestedFollowUps"]),
            "SafetyInfo": obj([
                "workingDir": nullable("string"), "requiresTrustedDevice": bool, "privacyLabel": nullable("string"),
            ], required: ["requiresTrustedDevice"]),
            "AdmissionInfo": obj([
                "state": str, "source": nullable("string"), "observedAt": nullable("string"),
                "resetAt": nullable("string"), "confidence": nullable("string"), "reason": nullable("string"),
            ], required: ["state"]),
            "CapacityObservationInfo": obj([
                "kind": enumStr([
                    "accountRateLimit", "providerBusy", "cooldown", "authRequired",
                    "manualRequired", "unknownCapacity",
                ]),
                "source": str,
                "sourceConfidence": enumStr(["structured", "messageFallback", "localPolicy", "unknown"]),
                "rawSnippet": str,
                "observedAt": str,
                "observedResetAt": nullable("string"),
                "retryAfterSeconds": nullable("integer"),
                "wakeAfter": nullable("string"),
            ], required: ["kind", "source", "sourceConfidence", "rawSnippet", "observedAt"]),
            "AttemptInfo": obj([
                "attemptId": str, "createdAt": str, "startedAt": nullable("string"),
                "completedAt": nullable("string"), "workerIds": arr(str), "status": str,
                "reason": nullable("string"), "transcriptRef": nullable("string"),
            ], required: ["attemptId", "createdAt", "workerIds", "status"]),
            "NextAction": obj([
                "kind": enumStr(["submitPending", "runPending", "showPending", "cancelPending"]),
                "command": str, "label": nullable("string"),
            ], required: ["kind", "command"]),
            "AuditInfo": obj([
                "traceId": str, "pendingStorePath": str,
            ], required: ["traceId", "pendingStorePath"]),
        ]
        return schema
    }

    // MARK: - ModelListJSON

    public static func modelListSchema() -> [String: Any] {
        var schema: [String: Any] = [
            "$schema": "https://json-schema.org/draft/2020-12/schema",
            "$id": "https://allnighter.app/schemas/model-list.schema.json",
            "title": "ModelListJSON",
        ]
        let top = obj([
            "schemaVersion": int, "contractVersion": str,
            "models": arr(ref("ModelEntry")),
            "diagnostics": arr(ref("ModelDiagnostic")),
            "counsel": nullable("string"),
            "nextActions": arr(ref("AgentSurfaceNextAction")),
        ], required: ["schemaVersion", "contractVersion", "models", "diagnostics", "nextActions"])
        schema.merge(top) { _, new in new }
        schema["$defs"] = [
            "ModelEntry": obj([
                "id": str, "displayName": str, "modelLabel": str, "driverId": str, "driverName": str,
                "role": str, "origin": enumStr(["built_in", "custom", "discovered"]),
                "enabled": bool, "ready": bool,
                "status": enumStr(["ready", "notReady", "notChecked", "driverMissing"]),
                "state": enumStr(["onBench", "available"]),
                "capabilities": ref("ModelCapabilities"),
                "headlessTrust": nullableRef("HeadlessTrustPolicy"),
            ], required: [
                "id", "displayName", "modelLabel", "driverId", "driverName", "role", "origin",
                "enabled", "ready", "status", "state", "capabilities",
            ]),
            "HeadlessTrustPolicy": obj([
                "required": bool, "cliFlag": str, "disclosure": str,
            ], required: ["required", "cliFlag", "disclosure"]),
            "ModelCapabilities": obj([
                "laneTags": arr(str), "capabilityTags": arr(str), "strengthRank": int,
            ], required: ["laneTags", "capabilityTags", "strengthRank"]),
            "ModelDiagnostic": obj([
                "code": str, "modelId": nullable("string"), "driverId": nullable("string"), "message": str,
            ], required: ["code", "message"]),
            "AgentSurfaceNextAction": agentSurfaceNextActionDef(),
        ]
        return schema
    }

    private static func agentSurfaceNextActionDef() -> [String: Any] {
        obj(["kind": str, "label": str, "command": str], required: ["kind", "label", "command"])
    }

    public static func versionSchema() -> [String: Any] {
        var schema: [String: Any] = [
            "$schema": "https://json-schema.org/draft/2020-12/schema",
            "$id": "https://allnighter.app/schemas/version.schema.json",
            "title": "VersionJSON",
        ]
        let top = obj([
            "schemaVersion": int, "binaryVersion": str, "contractVersion": str, "contractHash": str,
            "gitSha": nullable("string"), "buildTime": nullable("string"),
            "binaryPath": nullable("string"),
        ], required: ["schemaVersion", "binaryVersion", "contractVersion", "contractHash"])
        schema.merge(top) { _, new in new }
        return schema
    }

    // MARK: - FloorRun (Team Run Floor projection)

    public static func floorRunSchema() -> [String: Any] {
        var schema: [String: Any] = [
            "$schema": "https://json-schema.org/draft/2020-12/schema",
            "$id": "https://allnighter.app/schemas/floor-run.schema.json",
            "title": "FloorRun",
        ]
        let top = obj([
            "schemaVersion": int, "run": ref("FloorRunInfo"), "intent": ref("FloorIntent"),
            "team": ref("FloorTeam"), "workerLanes": arr(ref("FloorWorkerLane")),
            "floorReturn": nullableRef("FloorReturn"), "nextActions": arr(ref("FloorNextAction")),
            "artifacts": arr(ref("RunArtifactRef")), "timeline": arr(ref("FloorTimelineEvent")),
            "warnings": arr(str), "errors": arr(ref("ErrorEnvelope")), "audit": ref("FloorAudit"),
        ], required: [
            "schemaVersion", "run", "intent", "team", "workerLanes", "floorReturn", "nextActions",
            "artifacts", "timeline", "warnings", "errors", "audit",
        ])
        schema.merge(top) { _, new in new }
        let floorStatus = enumStr(["queued", "running", "done", "failed", "timedOut", "cancelled", "interrupted"])
        schema["$defs"] = [
            "FloorRunInfo": obj([
                "id": str, "projectId": nullable("string"), "threadId": nullable("string"),
                "status": floorStatus, "family": nullable("string"),
                "mutating": bool, "origin": str, "originAgent": nullable("string"),
                "createdAt": str, "reproduceCommand": nullable("string"),
            ], required: ["id", "status", "mutating", "origin", "createdAt"]),
            "FloorIntent": obj(["prompt": str, "threadId": nullable("string")], required: ["prompt"]),
            "FloorTeam": obj([
                "teamId": nullable("string"), "displayName": nullable("string"), "family": nullable("string"),
                "outputKind": nullable("string"), "workerCount": int, "modelCount": int,
                "leadWorkerId": nullable("string"),
            ], required: ["workerCount", "modelCount"]),
            "FloorWorkerLane": obj([
                "workerId": str, "skillId": nullable("string"), "skillName": nullable("string"),
                "modelId": str, "purpose": enumStr(["answer", "review", "lead", "stage"]),
                "status": str, "startedAt": nullable("string"), "finishedAt": nullable("string"),
                "durationMs": nullable("integer"), "exitCode": nullable("integer"),
                "summary": nullable("string"), "artifactRefs": arr(ref("RunArtifactRef")),
                "promptArtifactRef": nullableRef("RunArtifactRef"), "error": nullable("string"),
            ], required: ["workerId", "modelId", "purpose", "status", "artifactRefs"]),
            "FloorReturn": obj([
                "kind": enumStr(["insight", "plan", "board", "draft", "proposal", "proofPacket", "audit"]),
                "status": str, "title": str, "summaryMarkdown": nullable("string"),
                "producedByAgentId": nullable("string"), "stageId": nullable("string"),
                "artifactRefs": arr(ref("RunArtifactRef")), "insight": nullableRef("SignalInsight"),
            ], required: ["kind", "status", "title", "artifactRefs"]),
            "RunArtifactRef": obj([
                "id": str, "runId": str,
                "kind": enumStr(["workerAnswer", "workerPrompt", "workerMetadata", "stageOutput", "receipt", "returnMarkdown", "insightJSON", "bundle", "source"]),
                "title": str, "relativePath": str, "mimeType": str, "workerId": nullable("string"),
                "stageId": nullable("string"), "createdAt": str, "contentSHA256": nullable("string"), "localOnly": bool,
            ], required: ["id", "runId", "kind", "title", "relativePath", "mimeType", "createdAt", "localOnly"]),
            "FloorTimelineEvent": obj([
                "id": str, "runId": str,
                "kind": enumStr(["runQueued", "runStarted", "workerStarted", "workerReturned", "workerFailed", "stageStarted", "stageFinished", "synthesisStarted", "synthesisFinished", "runFinished"]),
                "at": str, "workerId": nullable("string"), "stageId": nullable("string"), "status": nullable("string"),
            ], required: ["id", "runId", "kind", "at"]),
            "FloorNextAction": obj([
                "id": str,
                "kind": enumStr(["openArtifact", "copyReturn", "exportFloor", "sendTeam", "draftCopy", "createCodeProposal", "createDesignBrief", "savePending", "ignore", "monitorExternally", "showRun", "showHistory"]),
                "label": str, "mutating": bool,
                "command": nullable("string"), "disabledReason": nullable("string"),
            ], required: ["id", "kind", "label", "mutating"]),
            "SignalInsight": obj([
                "title": str, "summary": str, "whatHappened": str, "whyItMatters": str, "whyThisProject": str,
                "window": enumStr(["open", "closing", "closed", "uncertain"]), "freshness": ref("SignalFreshness"),
                "internalLessons": arr(str), "externalProductIdeas": arr(str), "skepticPass": ref("SignalSkepticPass"),
                "receipts": arr(ref("SignalReceipt")), "recommendedNextActionId": nullable("string"),
            ], required: ["title", "summary", "whatHappened", "whyItMatters", "whyThisProject", "window", "freshness", "internalLessons", "externalProductIdeas", "skepticPass", "receipts"]),
            "SignalFreshness": obj([
                "observedAt": str, "newestSourceAt": nullable("string"), "oldestSourceAt": nullable("string"),
                "status": enumStr(["fresh", "stale", "uncertain"]),
            ], required: ["observedAt", "status"]),
            "SignalSkepticPass": obj([
                "verdict": enumStr(["pass", "caution", "reject", "uncertain"]), "reason": str,
                "saturationRisk": nullable("boolean"), "ownedByAnotherAccount": nullable("boolean"),
            ], required: ["verdict", "reason"]),
            "SignalReceipt": obj([
                "id": str, "sourceKind": enumStr(["xPost", "xThread", "article", "releaseNote", "repo", "other"]),
                "url": nullable("string"), "sourceId": nullable("string"), "authorOrPublisher": nullable("string"),
                "observedAt": str, "publishedAt": nullable("string"), "title": nullable("string"),
                "snippet": nullable("string"), "relevance": str,
                "evidenceRole": enumStr(["primary", "corroborating", "counterSignal", "saturation", "skeptic"]),
                "artifactRef": nullable("string"),
            ], required: ["id", "sourceKind", "observedAt", "relevance", "evidenceRole"]),
            "FloorAudit": obj([
                "runJournalPath": nullable("string"), "traceId": nullable("string"),
            ], required: []),
            "ErrorEnvelope": errorEnvelopeDef(),
        ]
        return schema
    }

    // MARK: - SpecRetrieval.Result (spec / spec_get)

    public static func specResultSchema() -> [String: Any] {
        var schema: [String: Any] = [
            "$schema": "https://json-schema.org/draft/2020-12/schema",
            "$id": "https://allnighter.app/schemas/spec-result.schema.json",
            "title": "SpecResult",
        ]
        let top = obj([
            "schemaVersion": int, "runId": str, "status": str, "lane": nullable("string"),
            "teamPresetId": nullable("string"), "outputKind": nullable("string"),
            "selector": str, "detail": str, "summary": str, "full": nullable("string"),
            "warnings": arr(str), "failedWorkers": arr(ref("FailedWorker")), "artifactRefs": arr(str),
        ], required: ["schemaVersion", "runId", "status", "selector", "detail", "summary", "warnings", "failedWorkers", "artifactRefs"])
        schema.merge(top) { _, new in new }
        schema["$defs"] = [
            "FailedWorker": obj([
                "workerId": str, "skillName": nullable("string"), "reason": str,
            ], required: ["workerId", "reason"]),
        ]
        return schema
    }

    // MARK: - Catalog list contracts (teams_list / skills_list)

    public static func teamCatalogSchema() -> [String: Any] {
        var schema: [String: Any] = [
            "$schema": "https://json-schema.org/draft/2020-12/schema",
            "$id": "https://allnighter.app/schemas/team-catalog.schema.json",
            "title": "TeamCatalogJSON",
        ]
        let top = obj([
            "schemaVersion": int, "contractVersion": str, "lane": nullable("string"),
            "teams": arr(ref("TeamCatalogEntry")),
            "counsel": nullable("string"),
            "nextActions": arr(ref("AgentSurfaceNextAction")),
        ], required: ["schemaVersion", "contractVersion", "teams", "nextActions"])
        schema.merge(top) { _, new in new }
        schema["$defs"] = [
            "TeamCatalogEntry": obj([
                "id": str, "displayName": str, "lane": str, "outputKind": str, "defaultEffort": str,
                "mutating": bool, "builtIn": bool, "isDefaultForLane": bool,
                "seatCount": int, "active": bool, "disabledReason": nullable("string"),
            ], required: ["id", "displayName", "lane", "outputKind", "defaultEffort", "mutating", "builtIn", "isDefaultForLane", "seatCount", "active"]),
            "AgentSurfaceNextAction": agentSurfaceNextActionDef(),
        ]
        return schema
    }

    public static func skillCatalogSchema() -> [String: Any] {
        var schema: [String: Any] = [
            "$schema": "https://json-schema.org/draft/2020-12/schema",
            "$id": "https://allnighter.app/schemas/skill-catalog.schema.json",
            "title": "SkillCatalogJSON",
        ]
        let top = obj([
            "schemaVersion": int, "contractVersion": str, "lane": nullable("string"),
            "skills": arr(ref("SkillCatalogEntry")),
        ], required: ["schemaVersion", "contractVersion", "skills"])
        schema.merge(top) { _, new in new }
        schema["$defs"] = [
            "SkillCatalogEntry": obj([
                "id": str, "displayName": str, "lane": str, "purpose": str, "builtIn": bool,
                "origin": str, "seedId": nullable("string"), "restoreAvailable": bool,
            ], required: ["id", "displayName", "lane", "purpose", "builtIn", "origin", "restoreAvailable"]),
        ]
        return schema
    }

    // MARK: - Retrieval contracts (history / thread_status)

    public static func historySchema() -> [String: Any] {
        var schema: [String: Any] = [
            "$schema": "https://json-schema.org/draft/2020-12/schema",
            "$id": "https://allnighter.app/schemas/history.schema.json",
            "title": "HistoryJSON",
        ]
        let top = obj([
            "schemaVersion": int, "contractVersion": str, "query": str,
            "results": arr(ref("RecallResult")),
        ], required: ["schemaVersion", "contractVersion", "query", "results"])
        schema.merge(top) { _, new in new }
        schema["$defs"] = [
            "RecallResult": obj([
                "runId": str, "prompt": str, "createdAt": str, "planExcerpt": str,
            ], required: ["runId", "prompt", "createdAt", "planExcerpt"]),
        ]
        return schema
    }

    public static func threadStatusSchema() -> [String: Any] {
        var schema: [String: Any] = [
            "$schema": "https://json-schema.org/draft/2020-12/schema",
            "$id": "https://allnighter.app/schemas/thread-status.schema.json",
            "title": "ThreadStatusResponse",
        ]
        let top = obj([
            "threadId": str, "isRunning": bool, "needsAttention": bool,
        ], required: ["threadId", "isRunning", "needsAttention"])
        schema.merge(top) { _, new in new }
        return schema
    }

    public static func threadGetSchema() -> [String: Any] {
        var schema: [String: Any] = [
            "$schema": "https://json-schema.org/draft/2020-12/schema",
            "$id": "https://allnighter.app/schemas/thread-get.schema.json",
            "title": "ThreadGetResponse",
        ]
        let top = obj([
            "schemaVersion": int, "contractVersion": str, "formatVersion": int,
            "id": str, "title": str, "status": str, "createdAt": str, "updatedAt": str,
            "turns": arr(ref("ThreadTurnProjection")),
        ], required: ["schemaVersion", "contractVersion", "id", "title", "status", "turns"])
        schema.merge(top) { _, new in new }
        schema["$defs"] = [
            "ThreadTurnProjection": obj([
                "id": str, "kind": str, "status": str, "text": nullable("string"),
                "attachmentRefs": arr(obj(["attachmentId": str, "sequence": int], required: ["attachmentId", "sequence"])),
                "resolvedAttachments": arr(ref("ResolvedThreadAttachment")),
            ], required: ["id", "kind", "status", "resolvedAttachments"]),
            "ResolvedThreadAttachment": obj([
                "attachmentId": str, "sequence": int, "canonicalPath": str,
                "storedSha256": str, "mimeType": str, "sourceKind": str,
                "byteSize": int, "missing": bool,
            ], required: ["attachmentId", "sequence", "canonicalPath", "missing"]),
        ]
        return schema
    }

    public static func threadAttachmentSchema() -> [String: Any] {
        var schema: [String: Any] = [
            "$schema": "https://json-schema.org/draft/2020-12/schema",
            "$id": "https://allnighter.app/schemas/thread-attachment.schema.json",
            "title": "ThreadAttachmentGetResponse",
        ]
        let top = obj([
            "threadId": str, "attachmentId": str, "canonicalPath": str,
            "storedSha256": str, "mimeType": str, "byteSize": int, "missing": bool,
        ], required: ["threadId", "attachmentId", "canonicalPath", "missing"])
        schema.merge(top) { _, new in new }
        return schema
    }

    // MARK: - Ownership (PO-S05)

    public static func ownershipPsSchema() -> [String: Any] {
        var schema: [String: Any] = [
            "$schema": "https://json-schema.org/draft/2020-12/schema",
            "$id": "https://allnighter.app/schemas/ownership-ps.schema.json",
            "title": "OwnershipPsJSON",
        ]
        let top = obj([
            "schemaVersion": int,
            "countedAt": str,
            "processCount": int,
            "processes": arr(ref("OwnershipProcess")),
        ], required: ["schemaVersion", "countedAt", "processCount", "processes"])
        schema.merge(top) { _, new in new }
        schema["$defs"] = [
            "OwnershipProcess": obj([
                "id": str,
                "kind": enumStr(["run", "relay", "pilot", "proof", "worker"]),
                "projectRoot": nullable("string"),
                "identity": nullableRef("ProcessOwner"),
                "identityAlive": bool,
                "wouldReconcile": bool,
                "lane": nullableRef("OwnershipLane"),
                "lastProgressAt": nullable("string"),
                "heartbeatAgeSeconds": nullable("number"),
                "lastActivityKind": nullable("string"),
                "progressStale": nullable("boolean"),
                "endReason": nullable("string"),
                "status": nullable("string"),
                "phase": nullable("string"),
                "blockerResource": nullable("string"),
                "vendorDisplayName": nullable("string"),
                "wakeAfter": nullable("string"),
                "capacityObservation": nullableRef("CapacityObservation"),
                // RLR-S04c: additive killOutcome + read-time contradiction.
                "killOutcome": nullableEnum(["stopped", "partial", "refused", "verificationUnavailable"]),
                "contradiction": nullableEnum(["terminalWithLiveOwnership"]),
                "silenceStatus": nullable("string"),
            ], required: [
                "id", "kind", "identityAlive", "wouldReconcile",
            ]),
            "OwnershipLane": obj([
                "state": enumStr(["held", "ticket", "none"]),
                "holderId": nullable("string"),
                "holderKind": nullable("string"),
                "heldSinceSeconds": nullable("number"),
                "ticketPosition": nullable("integer"),
            ], required: ["state"]),
            "ProcessOwner": obj([
                "pid": int,
                "pgid": nullable("integer"),
                "startTimeTicks": int,
                "kind": str,
            ], required: ["pid", "startTimeTicks", "kind"]),
            "CapacityObservation": obj([
                "kind": str, "source": str, "sourceConfidence": str,
                "rawSnippet": str, "observedAt": str,
                "observedResetAt": nullable("string"),
                "retryAfterSeconds": nullable("integer"),
                "wakeAfter": nullable("string"),
            ], required: ["kind", "source", "sourceConfidence", "rawSnippet", "observedAt"]),
        ]
        return schema
    }

    public static func ownershipKillSchema() -> [String: Any] {
        var schema: [String: Any] = [
            "$schema": "https://json-schema.org/draft/2020-12/schema",
            "$id": "https://allnighter.app/schemas/ownership-kill.schema.json",
            "title": "OwnershipKillJSON",
        ]
        let top = obj([
            "schemaVersion": int,
            "killedCount": int,
            "killed": arr(ref("KillRow")),
            "skipped": arr(ref("KillSkip")),
        ], required: ["schemaVersion", "killedCount", "killed", "skipped"])
        schema.merge(top) { _, new in new }
        schema["$defs"] = [
            "KillRow": obj([
                "id": str, "kind": str,
                // RLR-S04b: `endReason` present only on a verified stop; `killOutcome`
                // is the typed settlement verdict. Both additive; `endReason` is no
                // longer required (absent for partial/refused/verificationUnavailable).
                "endReason": nullable("string"),
                "killOutcome": nullableEnum(["stopped", "partial", "refused", "verificationUnavailable"]),
                "signalled": bool,
            ], required: ["id", "kind", "signalled"]),
            "KillSkip": obj([
                "id": str, "reason": str,
            ], required: ["id", "reason"]),
        ]
        return schema
    }

    public static func ownershipGarbageCollectionSchema() -> [String: Any] {
        var schema: [String: Any] = [
            "$schema": "https://json-schema.org/draft/2020-12/schema",
            "$id": "https://allnighter.app/schemas/ownership-gc.schema.json",
            "title": "OwnershipGarbageCollectionJSON",
        ]
        let rows = arr(ref("GarbageCollectionRecord"))
        let top = obj([
            "schemaVersion": int,
            "retentionCount": int,
            "consideredCount": int,
            "prunedCount": int,
            "keptCount": int,
            "pruned": rows,
            "keptAlive": rows,
            "keptNonTerminal": rows,
            "keptWithinRetention": rows,
            "keptThreadReferenced": rows,
            "keptUnreadable": rows,
            "keptRemovalFailed": rows,
        ], required: [
            "schemaVersion", "retentionCount", "consideredCount", "prunedCount", "keptCount",
            "pruned", "keptAlive", "keptNonTerminal", "keptWithinRetention",
            "keptThreadReferenced", "keptUnreadable", "keptRemovalFailed",
        ])
        schema.merge(top) { _, new in new }
        schema["$defs"] = [
            "GarbageCollectionRecord": obj([
                "id": str,
                "kind": enumStr(["run", "relay", "pilot"]),
                "createdAt": nullable("string"),
                "status": nullable("string"),
                "detail": nullable("string"),
            ], required: ["id", "kind"]),
        ]
        return schema
    }

    // MARK: - MenuJSON (MR-S01)

    public static func menuSchema() -> [String: Any] {
        var schema: [String: Any] = [
            "$schema": "https://json-schema.org/draft/2020-12/schema",
            "$id": "https://allnighter.app/schemas/menu.schema.json",
            "title": "MenuJSON",
        ]
        let effectLevel = enumStr(["never", "always", "dependsOnFlags", "dependsOnSelection"])
        let top = obj([
            "schemaVersion": int, "contractVersion": str, "contractHash": str,
            "catalogRevision": str, "truncated": bool, "detailTemplate": str,
            "actions": arr(ref("MenuAction")),
            "commands": arr(ref("MenuCommand")),
            "teams": arr(ref("MenuTeam")),
            "models": arr(ref("MenuModel")),
            "recipes": arr(ref("MenuRecipe")),
            "effectProfiles": ["type": "object", "additionalProperties": ref("EffectProfile")],
            "defaults": ref("MenuDefaults"),
            "completeness": ref("MenuCompleteness"),
        ], required: [
            "schemaVersion", "contractVersion", "contractHash", "catalogRevision",
            "truncated", "detailTemplate", "actions", "commands", "teams", "models",
            "recipes", "effectProfiles", "defaults", "completeness",
        ])
        schema.merge(top) { _, new in new }
        schema["$defs"] = [
            "EffectProfile": obj([
                "workerStart": effectLevel, "quotaSpend": effectLevel,
                "repoWrite": effectLevel, "destructive": effectLevel,
                "humanInteraction": effectLevel,
            ], required: ["workerStart", "quotaSpend", "repoWrite", "destructive", "humanInteraction"]),
            "MenuAction": obj([
                "id": str, "useWhen": str, "dontUseWhen": str,
                "effectsRef": str, "example": str, "validateExample": str,
            ], required: ["id", "useWhen", "dontUseWhen", "effectsRef", "example", "validateExample"]),
            "MenuCommand": obj([
                "ref": str, "name": str, "effectsRef": str,
            ], required: ["ref", "name", "effectsRef"]),
            "MenuTeam": obj([
                "ref": str, "id": str, "displayName": str, "useWhen": str, "dontUseWhen": str,
                "shape": str, "mutating": bool, "seatCount": int, "isDefault": bool,
                "active": bool, "blockedReason": nullable("string"),
                "runTemplate": str, "validateTemplate": str,
            ], required: [
                "ref", "id", "displayName", "useWhen", "dontUseWhen", "shape", "mutating",
                "seatCount", "isDefault", "active", "runTemplate", "validateTemplate",
            ]),
            "MenuModel": obj([
                "ref": str, "id": str, "displayName": str, "driverId": str,
                "enabled": bool, "ready": bool, "blockedReason": nullable("string"),
                "capabilities": ref("ModelCapabilities"),
                "runTemplate": str, "validateTemplate": str,
            ], required: [
                "ref", "id", "displayName", "driverId", "enabled", "ready",
                "capabilities", "runTemplate", "validateTemplate",
            ]),
            "MenuRecipe": obj([
                "ref": str, "id": str, "title": str, "useWhen": str, "dontUseWhen": str,
            ], required: ["ref", "id", "title", "useWhen", "dontUseWhen"]),
            "MenuDefaults": obj([
                "defaultTeamRef": str, "defaultWorkerId": nullable("string"),
            ], required: ["defaultTeamRef"]),
            "CollectionCompleteness": obj([
                "count": int, "complete": bool,
            ], required: ["count", "complete"]),
            "MenuCompleteness": obj([
                "actions": ref("CollectionCompleteness"),
                "commands": ref("CollectionCompleteness"),
                "teams": ref("CollectionCompleteness"),
                "models": ref("CollectionCompleteness"),
                "recipes": ref("CollectionCompleteness"),
                "effectProfiles": ref("CollectionCompleteness"),
            ], required: ["actions", "commands", "teams", "models", "recipes", "effectProfiles"]),
            "ModelCapabilities": obj([
                "laneTags": arr(str), "capabilityTags": arr(str), "strengthRank": int,
            ], required: ["laneTags", "capabilityTags", "strengthRank"]),
        ]
        return schema
    }

    public static func menuShowSchema() -> [String: Any] {
        var schema: [String: Any] = [
            "$schema": "https://json-schema.org/draft/2020-12/schema",
            "$id": "https://allnighter.app/schemas/menu-show.schema.json",
            "title": "MenuShowJSON",
        ]
        let effectLevel = enumStr(["never", "always", "dependsOnFlags", "dependsOnSelection"])
        let top = obj([
            "schemaVersion": int, "contractVersion": str, "ref": str, "kind": str,
            "command": nullableRef("CommandDetail"),
            "team": nullableRef("TeamDetail"),
            "model": nullableRef("ModelDetail"),
            "recipe": nullableRef("RecipeDetail"),
        ], required: ["schemaVersion", "contractVersion", "ref", "kind"])
        schema.merge(top) { _, new in new }
        schema["$defs"] = [
            "EffectProfile": obj([
                "workerStart": effectLevel, "quotaSpend": effectLevel,
                "repoWrite": effectLevel, "destructive": effectLevel,
                "humanInteraction": effectLevel,
            ], required: ["workerStart", "quotaSpend", "repoWrite", "destructive", "humanInteraction"]),
            "ArgSpec": obj([
                "name": str, "required": bool, "summary": str,
            ], required: ["name", "required", "summary"]),
            "FlagSpec": obj([
                "name": str, "takesValue": bool, "valueType": nullable("string"),
                "defaultValue": nullable("string"),
                "allowedValues": ["oneOf": [arr(str), ["type": "null"]]],
                "summary": str,
            ], required: ["name", "takesValue", "summary"]),
            "FlagConstraint": obj([
                "kind": enumStr(["requires", "onlyWith"]),
                "subject": str,
                "peers": arr(str),
            ], required: ["kind", "subject", "peers"]),
            "CommandDetail": obj([
                "ref": str, "name": str, "summary": str, "trigger": str,
                "example": str, "antiExample": str, "spendsQuota": bool,
                "freeTwinCommand": nullable("string"), "effects": ref("EffectProfile"),
                "args": arr(ref("ArgSpec")), "flags": arr(ref("FlagSpec")),
                "mutuallyExclusiveFlags": arr(arr(str)),
                "flagConstraints": arr(ref("FlagConstraint")),
            ], required: [
                "ref", "name", "summary", "trigger", "example", "antiExample",
                "spendsQuota", "effects", "args", "flags",
                "mutuallyExclusiveFlags", "flagConstraints",
            ]),
            "TeamDetail": obj([
                "ref": str, "id": str, "displayName": str, "description": str,
                "lane": str, "outputKind": str, "shape": str, "mutating": bool,
                "seatCount": int, "isDefault": bool, "active": bool,
                "blockedReason": nullable("string"),
                "runTemplate": str, "validateTemplate": str, "purposeTags": arr(str),
            ], required: [
                "ref", "id", "displayName", "description", "lane", "outputKind",
                "shape", "mutating", "seatCount", "isDefault", "active",
                "runTemplate", "validateTemplate", "purposeTags",
            ]),
            "ModelDetail": obj([
                "ref": str, "id": str, "displayName": str, "driverId": str, "driverName": str,
                "enabled": bool, "ready": bool, "status": str,
                "blockedReason": nullable("string"),
                "capabilities": ref("ModelCapabilities"),
                "runTemplate": str, "validateTemplate": str,
            ], required: [
                "ref", "id", "displayName", "driverId", "driverName", "enabled", "ready",
                "status", "capabilities", "runTemplate", "validateTemplate",
            ]),
            "RecipeDetail": obj([
                "ref": str, "id": str, "title": str, "useWhen": str, "dontUseWhen": str,
                "markdown": str,
            ], required: ["ref", "id", "title", "useWhen", "dontUseWhen", "markdown"]),
            "ModelCapabilities": obj([
                "laneTags": arr(str), "capabilityTags": arr(str), "strengthRank": int,
            ], required: ["laneTags", "capabilityTags", "strengthRank"]),
        ]
        return schema
    }

    // MARK: - Deterministic serialization

    public static func json(_ schema: [String: Any]) throws -> String {
        let data = try JSONSerialization.data(withJSONObject: schema, options: [.prettyPrinted, .sortedKeys])
        return String(decoding: data, as: UTF8.self) + "\n"
    }
}
