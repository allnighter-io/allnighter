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
        case promptAsyncFailed(String)
        case streamFailed(String)
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
    /// Injectable SSE byte stream for `GET /event` (fixture tests yield canned SSE bodies).
    public typealias SSETransport = @Sendable (URLRequest) async throws -> AsyncThrowingStream<Data, Error>

    public let baseURL: URL
    private let transport: Transport
    private let sseTransport: SSETransport

    public init(
        baseURL: URL = OpenCodeServeCoordinator.defaultURL,
        transport: @escaping Transport = { try await URLSession.shared.data(for: $0) },
        sseTransport: @escaping SSETransport = OpenCodeServeClient.defaultSSETransport
    ) {
        self.baseURL = baseURL
        self.transport = transport
        self.sseTransport = sseTransport
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

    /// Fire-and-forget prompt over `POST /session/{id}/prompt_async` (204).
    public func promptAsync(
        sessionID: String,
        text: String,
        providerID: String,
        modelID: String,
        timeout: Duration = .seconds(180)
    ) async throws {
        let url = baseURL.appendingPathComponent("session")
            .appendingPathComponent(sessionID).appendingPathComponent("prompt_async")
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
            throw ClientError.promptAsyncFailed(problem)
        }
    }

    /// Create session → subscribe SSE → prompt_async → stream deltas until idle.
    public func streamRun(
        _ text: String,
        modelLabel: String,
        directory: String? = nil,
        autoApprove: Bool = false,
        timeout: Duration = .seconds(180)
    ) -> AsyncThrowingStream<WorkerStreamEvent, Error> {
        let model = Self.splitModelLabel(modelLabel)
        return AsyncThrowingStream { continuation in
            let task = Task {
                let startedAt = Date()
                do {
                    let sessionID = try await createSession(
                        directory: directory, autoApprove: autoApprove, timeout: timeout)
                    continuation.yield(.started(workerId: "opencode", modelId: modelLabel, sourceId: "opencode"))

                    let sseURL = baseURL.appendingPathComponent("event")
                    var sseReq = URLRequest(url: sseURL)
                    sseReq.httpMethod = "GET"
                    sseReq.timeoutInterval = Self.seconds(timeout)

                    let parser = OpenCodeSSEParser()
                    let idleGate = IdleGate()

                    let consume = Task {
                        do {
                            let byteStream = try await sseTransport(sseReq)
                            for try await chunk in byteStream {
                                for event in parser.receive(chunk) {
                                    if Self.isIdleSignal(event) {
                                        await idleGate.signal(clean: true)
                                        continue
                                    }
                                    continuation.yield(event)
                                }
                                // A reported session error ends the turn just like idle, but is
                                // not a clean completion — stop waiting and let the terminal
                                // block surface the failure.
                                if parser.sessionError != nil { await idleGate.signal(); break }
                                if await idleGate.isSignaled { break }
                            }
                            for event in parser.flush() {
                                if Self.isIdleSignal(event) { await idleGate.signal(clean: true); continue }
                                continuation.yield(event)
                            }
                            await idleGate.signal()
                        } catch {
                            await idleGate.signal()
                        }
                    }

                    try await promptAsync(
                        sessionID: sessionID, text: text,
                        providerID: model.providerID, modelID: model.modelID, timeout: timeout)

                    let deadline = Date().addingTimeInterval(Self.seconds(timeout))
                    while await !idleGate.isSignaled, Date() < deadline {
                        try await Task.sleep(nanoseconds: 50_000_000)
                    }
                    consume.cancel()

                    let finishedAt = Date()
                    let durationMs = Int(finishedAt.timeIntervalSince(startedAt) * 1000)
                    let answerText = parser.accumulatedAnswer
                    let reasoning = parser.accumulatedReasoning
                    let toolActions = parser.toolActionCount
                    let sawCleanIdle = await idleGate.sawCleanIdle

                    func done(_ output: String) {
                        var outcome = WorkerRunOutcome(
                            status: .done, output: output,
                            startedAt: startedAt, finishedAt: finishedAt)
                        outcome.durationMs = durationMs
                        outcome.reasoning = reasoning.isEmpty ? nil : reasoning
                        continuation.yield(.completed(outcome))
                    }
                    func failed(_ kind: WorkerAnswerErrorKind, _ reason: String) {
                        var outcome = WorkerRunOutcome(
                            status: .failed, errorKind: kind, errorReason: reason,
                            startedAt: startedAt, finishedAt: finishedAt)
                        outcome.durationMs = durationMs
                        continuation.yield(.failed(outcome))
                    }

                    if let sessionError = parser.sessionError {
                        // The run actually errored — a failure regardless of any tool work.
                        failed(.nonzeroExit, "opencode session error: \(sessionError)")
                    } else if !answerText.isEmpty {
                        done(answerText)
                    } else if toolActions > 0, sawCleanIdle {
                        // Tool-only completion: the model did its work through tools (wrote
                        // files / ran commands) and the session ended cleanly without a closing
                        // assistant message. The deliverable is the side effects, not chat
                        // text — this is success, not `empty_output`. (Decoupling this from
                        // visible text is what unblocks unattended review/execute batches.)
                        done("Completed via \(toolActions) tool action\(toolActions == 1 ? "" : "s") with no closing message.")
                    } else {
                        // No text, no tool work (or the stream never reached a clean idle):
                        // a genuinely empty turn stays a failure.
                        failed(.emptyOutput, "opencode stream: empty answer")
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { @Sendable _ in task.cancel() }
        }
    }

    private static func isIdleSignal(_ event: WorkerStreamEvent) -> Bool {
        guard case .rawEvent(_, let json) = event else { return false }
        return json.contains("session.idle") || json.contains(#""status":"idle"#)
    }

    private actor IdleGate {
        private(set) var isSignaled = false
        /// True only when an actual `session.idle` was observed — i.e. the run finished
        /// cleanly, as opposed to the stream merely ending or erroring. Tool-only success is
        /// gated on this so a timed-out / dropped stream is never mistaken for completion.
        private(set) var sawCleanIdle = false
        func signal(clean: Bool = false) {
            isSignaled = true
            if clean { sawCleanIdle = true }
        }
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

    /// Live SSE transport over URLSession byte streaming.
    public static func defaultSSETransport(_ request: URLRequest) async throws -> AsyncThrowingStream<Data, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let (bytes, response) = try await URLSession.shared.bytes(for: request)
                    guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                        continuation.finish(throwing: ClientError.streamFailed("SSE HTTP error"))
                        return
                    }
                    var lineBuffer = Data()
                    let newline = UInt8(ascii: "\n")
                    for try await byte in bytes {
                        lineBuffer.append(byte)
                        if byte == newline {
                            continuation.yield(lineBuffer)
                            lineBuffer = Data()
                        }
                    }
                    if !lineBuffer.isEmpty { continuation.yield(lineBuffer) }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { @Sendable _ in task.cancel() }
        }
    }
}
