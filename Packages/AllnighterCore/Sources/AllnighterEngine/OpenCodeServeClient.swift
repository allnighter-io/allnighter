import Foundation
import AllnighterCore

/// Talks to the warm `opencode serve` HTTP API — the *real* OpenCode answer channel.
///
/// `opencode run` is a TTY-interactive TUI client: piped into a non-TTY subprocess it
/// emits nothing on stdout/stderr (even with `--format json` / `--print-logs`) and never
/// exits, so it can never be scraped for an answer. The serve exposes a documented HTTP
/// API instead; the assistant answer is the `text` part(s) of `POST /session/{id}/message`.
/// See docs/phases/OpenCode_Smoke_Probe_Blocker.md (RESOLUTION).
public struct OpenCodeServeClient: Sendable {
    public enum ClientError: Error, Sendable, Equatable {
        case sessionCreateFailed(String)
        case messageFailed(String)
        case emptyAnswer
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

    /// Create a session, send one text prompt, and return the joined assistant `text`
    /// parts. One-shot / synchronous — suitable for the setup smoke probe and simple
    /// answer turns. (Long, tool-using executor runs should use prompt_async + /wait.)
    public func prompt(
        _ text: String,
        modelLabel: String,
        timeout: Duration = .seconds(180)
    ) async throws -> String {
        let model = Self.splitModelLabel(modelLabel)
        let sessionID = try await createSession(timeout: timeout)
        return try await sendMessage(
            sessionID: sessionID, text: text,
            providerID: model.providerID, modelID: model.modelID, timeout: timeout
        )
    }

    func createSession(timeout: Duration) async throws -> String {
        var req = URLRequest(url: baseURL.appendingPathComponent("session"))
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "content-type")
        req.httpBody = Data("{}".utf8)
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
    ) async throws -> String {
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
        return try Self.extractTextParts(data)
    }

    /// Collect every assistant `text` part from a `POST .../message` response and join
    /// them. The response is `[step-start, text, step-finish, …]`; reasoning / tool /
    /// step parts are ignored — only `type == "text"` is the visible answer.
    static func extractTextParts(_ data: Data) throws -> String {
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let parts = obj["parts"] as? [[String: Any]] else {
            throw ClientError.messageFailed(snippet(data))
        }
        let text = parts.compactMap { part -> String? in
            guard part["type"] as? String == "text" else { return nil }
            return part["text"] as? String
        }.joined()
        if text.isEmpty { throw ClientError.emptyAnswer }
        return text
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
