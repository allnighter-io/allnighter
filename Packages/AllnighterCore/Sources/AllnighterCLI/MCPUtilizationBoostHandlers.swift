import Foundation
import AllnighterCore
import AllnighterEngine

/// MCP projection of `alln utilization boost` — same Core path and JSON as CLI.
enum MCPUtilizationBoostHandlers {
    enum Outcome: Sendable {
        case success(String, summary: String)
        case toolError(ErrorEnvelope)
    }

    static func status(runtime: ToolRuntime) -> Outcome {
        get(runtime: runtime)
    }

    static func get(runtime: ToolRuntime) -> Outcome {
        let json = UtilizationBoostOperations.projection(runtime: runtime)
        let summary = "boost \(json.enabled ? "on" : "off") · \(json.displayState)"
        return .success(AllnighterCLI.jsonString(json), summary: summary)
    }

    static func update(runtime: ToolRuntime, args: [String: Any]) -> Outcome {
        let enabled = boolArg(args["enabled"])
        let windowStart = stringArg(args["windowStart"])
        let appliesTo: String?
        if let list = args["appliesTo"] as? [String] {
            appliesTo = list.joined(separator: ",")
        } else {
            appliesTo = stringArg(args["appliesTo"])
        }
        guard enabled != nil || windowStart != nil || appliesTo != nil else {
            return usage("pass enabled, windowStart, and/or appliesTo")
        }
        do {
            let json = try UtilizationBoostOperations.update(
                runtime: runtime,
                enabled: enabled,
                windowStart: windowStart,
                appliesTo: appliesTo
            )
            return .success(AllnighterCLI.jsonString(json), summary: "boost updated · \(json.displayState)")
        } catch let failure as UtilizationBoostOperations.Failure {
            if case .envelope(let env) = failure { return .toolError(env) }
            return .toolError(internalEnvelope(failure))
        } catch {
            return .toolError(internalEnvelope(error))
        }
    }

    static func seed(runtime: ToolRuntime, args: [String: Any]) async -> Outcome {
        guard let sourceId = stringArg(args["sourceId"]) else {
            return usage("sourceId required")
        }
        do {
            let event = try await UtilizationBoostOperations.seed(runtime: runtime, sourceId: sourceId)
            return .success(
                AllnighterCLI.jsonString(event),
                summary: "seed \(sourceId): \(event.outcome.rawValue)"
            )
        } catch let failure as UtilizationBoostOperations.Failure {
            if case .envelope(let env) = failure { return .toolError(env) }
            return .toolError(internalEnvelope(failure))
        } catch {
            return .toolError(internalEnvelope(error))
        }
    }

    static func clearObservations(args: [String: Any]) -> Outcome {
        let sourceId = stringArg(args["sourceId"])
        do {
            let json = try UtilizationBoostOperations.clearObservations(sourceId: sourceId)
            let summary = sourceId.map { "cleared observations for \($0)" } ?? "cleared all seed observations"
            return .success(AllnighterCLI.jsonString(json), summary: summary)
        } catch {
            return .toolError(internalEnvelope(error))
        }
    }

    private static func usage(_ message: String) -> Outcome {
        .toolError(ErrorEnvelope(code: "CLI_USAGE_ERROR", message: message, requiresManual: true, retryable: false))
    }

    private static func stringArg(_ value: Any?) -> String? {
        guard let s = value as? String, !s.isEmpty else { return nil }
        return s
    }

    private static func boolArg(_ value: Any?) -> Bool? {
        if let b = value as? Bool { return b }
        if let s = value as? String {
            switch s.lowercased() {
            case "true", "1", "on", "yes": return true
            case "false", "0", "off", "no": return false
            default: return nil
            }
        }
        return nil
    }

    private static func internalEnvelope(_ error: Error) -> ErrorEnvelope {
        ErrorEnvelope(code: "INTERNAL_ERROR", message: "\(error)", requiresManual: true, retryable: false)
    }
}
