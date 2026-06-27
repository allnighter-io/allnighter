import Foundation
import AllnighterCore

/// Talks to the warm `opencode serve` HTTP API — the *real* OpenCode answer channel.
///
/// `opencode run` is a TTY-interactive TUI client: piped into a non-TTY subprocess it
/// emits nothing on stdout/stderr (even with `--format json` / `--print-logs`) and never
/// exits, so it can never be scraped for an answer. The serve exposes a documented HTTP
/// API instead; the assistant answer is the `text` part(s) of `POST /session/{id}/message`.
/// See docs/phases/OpenCode_Smoke_Probe_Blocker.md (RESOLUTION + OC-B1).
public struct OpenCodeServeClient: Sendable {
    public enum ClientError: Error, Sendable, Equatable {
        case sessionCreateFailed(String)
        case messageFailed(String)
        case emptyAnswer
    }

    /// The assistant's reply, split into the visible answer and (for thinking models) the
    /// separate reasoning parts.
    public struct Answer: Sendable, Equatable {
        public let text: String
        public let reasoning: String?
    }

    /// Injectable HTTP transport so the capture path is fixture-testable without live
    /// network (the OpenCode regression law requires a fixture-backed test).
    public typealias Transport = @Sendable (URLRequest) async throws -> (Data, URLResponse)

    public let baseURL: URL
    private let transport: Transport

    public init(
        baseURL: URL = OpenCodeServeCoordinator.defaultURL,
        transport: @escaping Transport = { try await URLSession.shared.data(for: $0) }
    ) {
        self.baseURL = baseURL
        self.transport = transport
    }

    /// Split an OpenCode model label ("featherless/zai-org/GLM-5.2") into the API's
    /// `providerID` ("featherless") + `modelID` ("zai-org/GLM-5.2"). Splits on the FIRST
    /// slash only — the modelID itself contains slashes.
    public static func splitModelLabel(_ label: String) -> (providerID: String, modelID: String) {
        guard let slash = label.firstIndex(of: "/") else { return ("", label) }
        return (String(label[..<slash]), String(label[label.index(after: slash)...]))
    }

    /// Create a session, send one prompt, and return the assistant answer (+ reasoning).
    /// `directory` roots the session (so tools edit the right repo); `autoApprove` allows
    /// all tool permissions so a headless run never blocks on a permission prompt.
    public func run(
        _ text: String,
        modelLabel: String,
        directory: String? = nil,
        autoApprove: Bool = false,
        timeout: Duration = .seconds(180)
    ) async throws -> Answer {
        let model = Self.splitModelLabel(modelLabel)
        let sessionID = try await createSession(directory: directory, autoApprove: autoApprove, timeout: timeout)
        return try await sendMessage(
            sessionID: sessionID, text: text,
            providerID: model.providerID, modelID: model.modelID, timeout: timeout
        )
    }

    /// Convenience: the visible answer text only. Used by the readiness smoke and any
    /// answer-only turn. (Delegates to `run`.)
    public func prompt(
        _ text: String,
        modelLabel: String,
        directory: String? = nil,
        autoApprove: Bool = false,
        timeout: Duration = .seconds(180)
    ) async throws -> String {
        try await run(text, modelLabel: modelLabel, directory: directory, autoApprove: autoApprove, timeout: timeout).text
    }

    func createSession(directory: String?, autoApprove: Bool, timeout: Duration) async throws -> String {
        var components = URLComponents(
            url: baseURL.appendingPathComponent("session"), resolvingAgainstBaseURL: false
        )!
        if let directory, !directory.isEmpty {
            components.queryItems = [URLQueryItem(name: "directory", value: directory)]
        }
        var req = URLRequest(url: components.url!)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "content-type")
        // allow-all permission ruleset = headless auto-approve (the API equivalent of the
        // TUI's --dangerously-skip-permissions).
        let body: [String: Any] = autoApprove
            ? ["permission": [["permission": "*", "pattern": "**", "action": "allow"]]]
            : [:]
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        req.timeoutInterval = Self.seconds(timeout)
        let (data, response) = try await transport(req)
        if let problem = Self.httpProblem(response, data) {
            throw ClientError.sessionCreateFailed(problem)
        }
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let id = obj["id"] as? String, !id.isEmpty else {
            throw ClientError.sessionCreateFailed(Self.snippet(data))
        }
        return id
    }

    func sendMessage(
        sessionID: String, text: String,
        providerID: String, modelID: String, timeout: Duration
    ) async throws -> Answer {
        let url = baseURL.appendingPathComponent("session")
            .appendingPathComponent(sessionID).appendingPathComponent("message")
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "content-type")
        req.timeoutInterval = Self.seconds(timeout)
        let body: [String: Any] = [
            "model": ["providerID": providerID, "modelID": modelID],
            "parts": [["type": "text", "text": text]],
        ]
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, response) = try await transport(req)
        if let problem = Self.httpProblem(response, data) {
            throw ClientError.messageFailed(problem)
        }
        return try Self.extractAnswer(data)
    }

    /// Collect the assistant `text` part(s) (the answer) and `reasoning` part(s) (thinking)
    /// from a `POST .../message` response. The response is `[step-start, (reasoning), text,
    /// step-finish, …]`; tool / step parts are ignored.
    static func extractAnswer(_ data: Data) throws -> Answer {
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let parts = obj["parts"] as? [[String: Any]] else {
            throw ClientError.messageFailed(snippet(data))
        }
        var texts: [String] = []
        var reasons: [String] = []
        for part in parts {
            guard let type = part["type"] as? String, let value = part["text"] as? String else { continue }
            if type == "text" { texts.append(value) }
            else if type == "reasoning" { reasons.append(value) }
        }
        let text = texts.joined()
        if text.isEmpty { throw ClientError.emptyAnswer }
        return Answer(text: text, reasoning: reasons.isEmpty ? nil : reasons.joined(separator: "\n"))
    }

    /// One-call readiness smoke over the HTTP API: ensure the serve is up, ask the model
    /// for the expected token, confirm it came back. Returns nil on success, else a human
    /// failure reason. Shared by the Mac setup probe (CLIDetector) and Doctor
    /// (ModelHealthChecker) so both read the same channel.
    public static func smokeReason(
        manifest: DriverManifest,
        modelLabel: String,
        coordinator: OpenCodeServeCoordinator = OpenCodeServeCoordinator(),
        client: OpenCodeServeClient = OpenCodeServeClient()
    ) async -> String? {
        do { try await coordinator.ensureRunning() }
        catch { return "opencode serve: \(error)" }
        let expect = manifest.smokeTestExpect ?? "ALLNIGHTER_READY"
        do {
            let answer = try await client.prompt("Reply with the single token \(expect)", modelLabel: modelLabel)
            return answer.contains(expect)
                ? nil
                : "smoke did not return \(expect) · got: \(String(answer.prefix(200)))"
        } catch {
            return "opencode smoke: \(error)"
        }
    }

    private static func seconds(_ d: Duration) -> TimeInterval {
        let c = d.components
        return Double(c.seconds) + Double(c.attoseconds) / 1e18
    }

    private static func httpProblem(_ response: URLResponse, _ data: Data) -> String? {
        guard let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) else {
            return nil
        }
        return "HTTP \(http.statusCode): \(snippet(data))"
    }

    private static func snippet(_ data: Data) -> String {
        String(decoding: data.prefix(300), as: UTF8.self)
    }
}
