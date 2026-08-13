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
/// 5. Context bound. Unrecognized local tags make Claude Code assume 200k and
///    skip auto-compact until then, while the served window may be 65536.
///    Overlay `CLAUDE_CODE_CONTEXT_WINDOW` from `/api/ps` when observed.
///    Never invent a number; unobserved means the key is absent.
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
    /// Per-run overlay so Claude Code auto-compacts at the served window.
    public static let contextWindowKey = "CLAUDE_CODE_CONTEXT_WINDOW"

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
    /// `servedContextWindow` is only the `/api/ps` observation. Nil/non-positive
    /// omits the context key — never 200k, never a guessed size.
    public static func perRunEnvironment(servedContextWindow: Int? = nil) -> [String: String] {
        var env: [String: String] = [
            baseURLKey: anthropicBaseURL,
            authTokenKey: anthropicAuthToken,
            apiKeyKey: anthropicAPIKey,
        ]
        for key in scrubbedKeys {
            env[key] = ""
        }
        if let servedContextWindow, servedContextWindow > 0 {
            env[contextWindowKey] = String(servedContextWindow)
        }
        return env
    }

    /// Local-evidence verify. Never spawns Claude Code — the invoke-smoke
    /// token echo is what timed out while Ollama and a direct Claude-local
    /// body both succeeded.
    public static func verify(
        modelLabel: String,
        driverId: String,
        probeRecord: ToolProbeRecord?,
        snapshot: OllamaLocalRuntimeObserver.Snapshot?,
        now: Date = Date()
    ) -> OpenCodeLocalSeatReadiness.LocalVerify {
        OpenCodeLocalSeatReadiness.verifyOllamaBackedSeat(
            isLocalSeat: isLocalSeat(driverId: driverId, modelLabel: modelLabel),
            modelLabel: modelLabel,
            driverId: driverId,
            probeRecord: probeRecord,
            snapshot: snapshot,
            now: now,
            unobservedDetail: "Ollama not observed — local seat does not use Claude Code invoke smoke"
        )
    }

    /// Served window from an observed `/api/ps` row. Nil when unobserved or
    /// not a local seat — never advertised `context_length`, never 200k.
    public static func observedServedContextWindow(
        for model: Model,
        snapshot: OllamaLocalRuntimeObserver.Snapshot? = nil,
        now: Date = Date(),
        isTestHost: Bool = AllnighterSupportRoot.isRunningUnderTestHost
    ) -> Int? {
        guard isLocalSeat(model) else { return nil }
        let snap = snapshot ?? OllamaLocalDoctorReport.snapshotIfAllowed(
            transport: nil,
            observedAt: now,
            isTestHost: isTestHost
        )
        return LoopLocalSeatPolicy.servedContextWindow(for: model, snapshot: snap)
    }

    public static func prepare(
        _ invocation: WorkerInvocation,
        servedContextWindow: Int? = nil
    ) -> WorkerInvocation {
        guard isLocalSeat(invocation.model) else { return invocation }
        var invocation = invocation
        invocation.model.modelLabel = wireModelLabel(invocation.model.modelLabel)
        var manifest = invocation.manifest
        guard var invoke = manifest.invoke else {
            invocation.manifest = manifest
            return invocation
        }
        var env = invoke.env
        for (key, value) in perRunEnvironment(servedContextWindow: servedContextWindow) {
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
            failClosed: "local Ollama Anthropic-compat endpoint only; never api.anthropic.com",
            verifyUsesLocalEvidence: true,
            contextWindowEnvKey: contextWindowKey,
            contextWindowOnlyWhenObserved: true
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
        public var verifyUsesLocalEvidence: Bool
        public var contextWindowEnvKey: String
        public var contextWindowOnlyWhenObserved: Bool
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
    public typealias ServedContextWindowLookup = @Sendable (Model) -> Int?

    private let inner: any WorkerInvoking
    private let servedContextWindow: ServedContextWindowLookup

    public init(
        inner: any WorkerInvoking,
        servedContextWindow: @escaping ServedContextWindowLookup = { _ in nil }
    ) {
        self.inner = inner
        self.servedContextWindow = servedContextWindow
    }

    public func invoke(_ invocation: WorkerInvocation) -> AsyncThrowingStream<WorkerStreamEvent, Error> {
        guard ClaudeLocalIsolation.isLocalSeat(invocation.model) else {
            return inner.invoke(invocation)
        }
        let prepared = ClaudeLocalIsolation.prepare(
            invocation,
            servedContextWindow: servedContextWindow(invocation.model)
        )
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
