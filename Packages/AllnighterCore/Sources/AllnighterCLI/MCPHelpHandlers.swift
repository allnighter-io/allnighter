import Foundation
import AllnighterCore

/// MCP projection of `alln help`. Read-only retrieval over the installed help bundle —
/// no run, probe, auth, or network. Same `HelpProjector` envelopes as the CLI.
enum MCPHelpHandlers {
    enum Outcome: Error, Sendable {
        case success(String, summary: String)
        case toolError(ErrorEnvelope)
    }

    private static var cv: String { ContractRegistry.contractVersion }

    static func search(args: [String: Any]) -> Outcome {
        guard let query = (args["query"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
              !query.isEmpty else {
            return .toolError(ErrorEnvelope(code: "CLI_USAGE_ERROR", message: "query required", requiresManual: true, retryable: false))
        }
        let limit = (args["limit"] as? Int) ?? (args["limit"] as? NSNumber)?.intValue ?? 5
        let json = HelpProjector.search(query, limit: limit, contractVersion: cv)
        let summary = json.suggestedAnswerMarkdown ?? "\(json.results.count) result(s)"
        return .success(AllnighterCLI.jsonString(json), summary: summary)
    }

    static func get(args: [String: Any]) -> Outcome {
        let json = HelpProjector.get(
            topic: args["topic"] as? String, ref: args["ref"] as? String,
            tool: args["tool"] as? String, error: args["error"] as? String, contractVersion: cv)
        let summary = json.topic.map { "\($0.title): \($0.summary)" }
            ?? "no topic — try: \(json.closeMatches.joined(separator: ", "))"
        return .success(AllnighterCLI.jsonString(json), summary: summary)
    }
}
