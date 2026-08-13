import Foundation
import AgentOSCLI

/// OCL-S02b — Claude Code as a local Ollama body.
///
/// Isolation (designed before spawn):
/// 1. Identity is the seat, not the driver. Paid `claude_code` seats stay paid.
///    A local seat is `driverId == claude_code` and catalog label `ollama/<tag>`.
/// 2. Per-run env only. Overlay `ANTHROPIC_BASE_URL` / token / empty API key onto
///    this spawn's manifest. Never write the user shell, profile, or Claude settings.
///    Never read Keychain or any stored Anthropic credential.
/// 3. Fail closed toward Ollama. Localhost base URL is mandatory so a Keychain
///    credential inside Claude Code still talks to `11434`, never api.anthropic.com.
/// 4. Capacity and meters. A local failure is not a Claude limit. Claude's
///    `costUSD` / `contextWindow: 200000` / `provider: firstParty` are not truth.
public enum ClaudeLocalIsolation {
    public static let driverId = "claude_code"
    public static let signalSourceId = OllamaLocalRuntimeClient.sourceId
    public static let catalogLabelPrefix = "ollama/"
    public static let anthropicBaseURL = "http://localhost:11434"
    public static let anthropicAuthToken = "ollama"
    public static let anthropicAPIKey = ""

    public static let baseURLKey = "ANTHROPIC_BASE_URL"
    public static let authTokenKey = "ANTHROPIC_AUTH_TOKEN"
    public static let apiKeyKey = "ANTHROPIC_API_KEY"

    /// Competing cloud-routing flags, cleared on the child only.
    public static let scrubbedKeys: [String] = [
        "CLAUDE_CODE_USE_BEDROCK",
        "CLAUDE_CODE_USE_VERTEX",
        "CLAUDE_CODE_USE_FOUNDRY",
    ]

    public static let seatingExample =
        "alln models add --driver claude_code --name <name> --model-label ollama/<tag>"

    public static func isLocalSeat(driverId: String, modelLabel: String) -> Bool {
        driverId == Self.driverId && modelLabel.hasPrefix(catalogLabelPrefix)
    }

    public static func isLocalSeat(_ model: Model) -> Bool {
        isLocalSeat(driverId: model.driverId, modelLabel: model.modelLabel)
    }

    /// Catalog `ollama/<tag>` → wire tag Claude Code sends to Ollama.
    public static func wireModelLabel(_ catalogLabel: String) -> String {
        guard catalogLabel.hasPrefix(catalogLabelPrefix) else { return catalogLabel }
        let tag = String(catalogLabel.dropFirst(catalogLabelPrefix.count))
        return tag.isEmpty ? catalogLabel : tag
    }

    /// Overlay applied last onto the child environment. Empty API key is
    /// intentional — it must override a inherited paid key.
    public static func perRunEnvironment() -> [String: String] {
        var env: [String: String] = [
            baseURLKey: anthropicBaseURL,
            authTokenKey: anthropicAuthToken,
            apiKeyKey: anthropicAPIKey,
        ]
        for key in scrubbedKeys {
            env[key] = ""
        }
        return env
    }

    public static func prepare(_ invocation: WorkerInvocation) -> WorkerInvocation {
        guard isLocalSeat(invocation.model) else { return invocation }
        var invocation = invocation
        invocation.model.modelLabel = wireModelLabel(invocation.model.modelLabel)
        var manifest = invocation.manifest
        guard var invoke = manifest.invoke else {
            invocation.manifest = manifest
            return invocation
        }
        var env = invoke.env
        for (key, value) in perRunEnvironment() {
            env[key] = value
        }
        invoke.env = env
        manifest.invoke = invoke
        invocation.manifest = manifest
        return invocation
    }

    public static func sanitize(_ result: WorkerRunResult) -> WorkerRunResult {
        var result = result
        if result.capacityObservation != nil {
            result.capacityObservation = nil
            if result.errorReason?.hasPrefix("capacity:") == true {
                result.errorReason = "ollama_local failed; not an Anthropic limit"
            }
        }
        if let output = result.output {
            result.output = stripVendorShapedMeters(from: output)
        }
        if let reasoning = result.reasoning {
            result.reasoning = stripVendorShapedMeters(from: reasoning)
        }
        return result
    }

    public static func stripVendorShapedMeters(from text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("{") || trimmed.hasPrefix("[") {
            if let data = trimmed.data(using: .utf8),
               let obj = try? JSONSerialization.jsonObject(with: data),
               let stripped = stripJSON(obj),
               let out = try? JSONSerialization.data(withJSONObject: stripped, options: [.sortedKeys]),
               let string = String(data: out, encoding: .utf8) {
                return string
            }
        }
        if text.contains("\n") {
            let lines = text.split(separator: "\n", omittingEmptySubsequences: false)
            let rewritten = lines.map { line -> String in
                let raw = String(line)
                let piece = raw.trimmingCharacters(in: .whitespaces)
                guard piece.hasPrefix("{"),
                      let data = piece.data(using: .utf8),
                      let obj = try? JSONSerialization.jsonObject(with: data),
                      let stripped = stripJSON(obj),
                      let out = try? JSONSerialization.data(
                        withJSONObject: stripped, options: [.sortedKeys]
                      ),
                      let string = String(data: out, encoding: .utf8)
                else { return raw }
                return string
            }
            return rewritten.joined(separator: "\n")
        }
        return text
    }

    public static func statusReport() -> StatusReport {
        StatusReport(
            schema: StatusReport.schemaId,
            driverId: driverId,
            signalSourceId: signalSourceId,
            catalogLabelPrefix: catalogLabelPrefix,
            anthropicBaseURL: anthropicBaseURL,
            anthropicAuthToken: anthropicAuthToken,
            anthropicAPIKeyEmpty: true,
            perRunOnly: true,
            writesGlobalShell: false,
            writesClaudeSettings: false,
            readsKeychain: false,
            seating: seatingExample,
            failClosed: "local Ollama Anthropic-compat endpoint only; never api.anthropic.com"
        )
    }

    public struct StatusReport: Codable, Equatable, Sendable {
        public static let schemaId = "alln.claude-local-isolation.v1"
        public var schema: String
        public var driverId: String
        public var signalSourceId: String
        public var catalogLabelPrefix: String
        public var anthropicBaseURL: String
        public var anthropicAuthToken: String
        public var anthropicAPIKeyEmpty: Bool
        public var perRunOnly: Bool
        public var writesGlobalShell: Bool
        public var writesClaudeSettings: Bool
        public var readsKeychain: Bool
        public var seating: String
        public var failClosed: String
    }

    private static let costKeys: Set<String> = ["costUSD", "costUsd", "cost_usd"]
    private static let contextKeys: Set<String> = ["contextWindow", "context_window"]

    private static func stripJSON(_ value: Any) -> Any? {
        if let dict = value as? [String: Any] {
            var out: [String: Any] = [:]
            for (key, child) in dict {
                if costKeys.contains(key) || contextKeys.contains(key) { continue }
                if key == "provider", let name = child as? String, name == "firstParty" {
                    continue
                }
                if let stripped = stripJSON(child) {
                    out[key] = stripped
                }
            }
            return out
        }
        if let array = value as? [Any] {
            return array.compactMap { stripJSON($0) }
        }
        return value
    }
}

/// Rewrites a Claude-local `WorkerInvocation` (per-run env + wire label) and
/// sanitizes the terminal result. Pass-through for every other seat.
public struct ClaudeLocalIsolatingWorkerRunner: WorkerInvoking {
    private let inner: any WorkerInvoking

    public init(inner: any WorkerInvoking) {
        self.inner = inner
    }

    public func invoke(_ invocation: WorkerInvocation) -> AsyncThrowingStream<WorkerStreamEvent, Error> {
        guard ClaudeLocalIsolation.isLocalSeat(invocation.model) else {
            return inner.invoke(invocation)
        }
        let prepared = ClaudeLocalIsolation.prepare(invocation)
        let inner = self.inner
        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    for try await event in inner.invoke(prepared) {
                        switch event {
                        case .completed(let result):
                            continuation.yield(.completed(ClaudeLocalIsolation.sanitize(result)))
                        case .failed(let result):
                            continuation.yield(.failed(ClaudeLocalIsolation.sanitize(result)))
                        default:
                            continuation.yield(event)
                        }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}
