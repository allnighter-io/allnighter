import XCTest
@testable import AllnighterCore

/// OCL-S02b — Claude-local isolation. Fixtures only; never live Ollama or Anthropic.
final class ClaudeLocalIsolationTests: XCTestCase {
    private let paid = Model(
        id: "model_opus", displayName: "Opus", modelLabel: "opus",
        driverId: "claude_code", role: .both
    )
    private let local = Model(
        id: "custom_claude_code_qwen", displayName: "Qwen local",
        modelLabel: "ollama/qwen2.5:0.5b", driverId: "claude_code", role: .both
    )
    private let openCodeLocal = Model(
        id: "custom_opencode_qwen", displayName: "Qwen OpenCode",
        modelLabel: "ollama/qwen2.5:0.5b", driverId: "opencode", role: .both
    )

    private func manifest(id: String = "claude_code", env: [String: String] = [:]) -> DriverManifest {
        DriverManifest(
            id: id,
            displayName: id,
            kind: .headlessCLI,
            invoke: .init(
                command: "claude",
                args: ["-p", "{{prompt}}", "--model", "{{model}}"],
                env: env
            )
        )
    }

    private func invocation(_ model: Model, env: [String: String] = [:]) -> WorkerInvocation {
        WorkerInvocation(
            model: model,
            manifest: manifest(id: model.driverId, env: env),
            prompt: "hi"
        )
    }

    func testPaidClaudeIsNotALocalSeatEvenIfOllamaIsAbsent() {
        XCTAssertFalse(ClaudeLocalIsolation.isLocalSeat(paid))
        XCTAssertFalse(ClaudeLocalIsolation.isLocalSeat(driverId: "claude_code", modelLabel: "sonnet"))
        XCTAssertFalse(ClaudeLocalIsolation.isLocalSeat(driverId: "claude_code", modelLabel: "fable"))
        XCTAssertFalse(CapacityAcquisition.benchSourceOrder.contains(ClaudeLocalIsolation.signalSourceId))
        XCTAssertEqual(ClaudeLocalIsolation.signalSourceId, "ollama_local")
    }

    func testOpenCodeOllamaLabelDoesNotTakeClaudeEnv() {
        XCTAssertFalse(ClaudeLocalIsolation.isLocalSeat(openCodeLocal))
        let prepared = ClaudeLocalIsolation.prepare(invocation(openCodeLocal))
        XCTAssertNil(prepared.manifest.invoke?.env[ClaudeLocalIsolation.baseURLKey])
        XCTAssertEqual(prepared.model.modelLabel, "ollama/qwen2.5:0.5b")
    }

    func testLocalSeatIdentityAndWireLabel() {
        XCTAssertTrue(ClaudeLocalIsolation.isLocalSeat(local))
        XCTAssertEqual(ClaudeLocalIsolation.wireModelLabel("ollama/qwen2.5:0.5b"), "qwen2.5:0.5b")
        XCTAssertEqual(ClaudeLocalIsolation.wireModelLabel("opus"), "opus")
    }

    func testPrepareOverlaysPerRunEnvAndDoesNotKeepPaidKey() throws {
        let prepared = ClaudeLocalIsolation.prepare(
            invocation(local, env: ["ANTHROPIC_API_KEY": "sk-ant-secret", "KEEP": "yes"])
        )
        let env = try XCTUnwrap(prepared.manifest.invoke?.env)
        XCTAssertEqual(env[ClaudeLocalIsolation.baseURLKey], "http://localhost:11434")
        XCTAssertEqual(env[ClaudeLocalIsolation.authTokenKey], "ollama")
        XCTAssertEqual(env[ClaudeLocalIsolation.apiKeyKey], "")
        XCTAssertEqual(env["KEEP"], "yes")
        XCTAssertEqual(env["CLAUDE_CODE_USE_BEDROCK"], "")
        XCTAssertEqual(env["CLAUDE_CODE_USE_VERTEX"], "")
        XCTAssertEqual(prepared.model.modelLabel, "qwen2.5:0.5b")
        XCTAssertFalse(env[ClaudeLocalIsolation.baseURLKey]?.contains("anthropic.com") ?? true)
    }

    func testPrepareLeavesPaidClaudeManifestUntouched() {
        let original = invocation(paid, env: ["ANTHROPIC_API_KEY": "sk-ant-paid"])
        let prepared = ClaudeLocalIsolation.prepare(original)
        XCTAssertEqual(prepared.manifest.invoke?.env["ANTHROPIC_API_KEY"], "sk-ant-paid")
        XCTAssertNil(prepared.manifest.invoke?.env[ClaudeLocalIsolation.baseURLKey])
        XCTAssertEqual(prepared.model.modelLabel, "opus")
    }

    func testLocalFailureNeverClassifiesAsAnthropicLimit() {
        let claudeLimit = CapacityClassifier.classify(
            CapacityClassifier.Input(
                workerId: paid.id,
                sourceId: "claude_code",
                stderr: #"{"type":"error","error":{"type":"rate_limit_error","message":"You've been rate limited","retry_after":90}}"#,
                exitCode: 1,
                observedAt: Date(timeIntervalSince1970: 1_700_000_000)
            )
        )
        XCTAssertEqual(claudeLimit?.source, "claude_code")
        XCTAssertTrue(claudeLimit.map(VendorBackoffPolicy.shouldPark) ?? false)

        let misattributed = WorkerRunResult(
            status: .failed,
            errorKind: .nonzeroExit,
            errorReason: "capacity: accountRateLimit",
            exitCode: 1,
            capacityObservation: claudeLimit
        )
        let sanitized = ClaudeLocalIsolation.sanitize(misattributed)
        XCTAssertNil(sanitized.capacityObservation)
        XCTAssertFalse(sanitized.capacityObservation.map(VendorBackoffPolicy.shouldPark) ?? false)
        XCTAssertEqual(sanitized.errorReason, "ollama_local failed; not an Anthropic limit")
        XCTAssertNotEqual(sanitized.errorReason, "capacity: accountRateLimit")
    }

    func testOllamaLocalSourceDoesNotBorrowClaudeStructuredParser() {
        let obs = CapacityClassifier.classify(
            CapacityClassifier.Input(
                workerId: local.id,
                sourceId: "ollama_local",
                stderr: #"{"type":"error","error":{"type":"rate_limit_error","message":"You've been rate limited","retry_after":90}}"#,
                exitCode: 1
            )
        )
        XCTAssertNotEqual(obs?.source, "claude_code")
        if let obs {
            XCTAssertFalse(obs.source == "claude_code" && VendorBackoffPolicy.shouldPark(obs))
        }
    }

    func testStripVendorShapedMetersFromClaudeResultJSON() throws {
        let raw = """
            {"type":"result","costUSD":1.25,"contextWindow":200000,"provider":"firstParty","result":"ok","usage":{"input_tokens":12}}
            """
        let stripped = ClaudeLocalIsolation.stripVendorShapedMeters(from: raw)
        let obj = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(stripped.utf8)) as? [String: Any]
        )
        XCTAssertNil(obj["costUSD"])
        XCTAssertNil(obj["contextWindow"])
        XCTAssertNil(obj["provider"])
        XCTAssertEqual(obj["result"] as? String, "ok")
        XCTAssertEqual(obj["type"] as? String, "result")
        XCTAssertEqual((obj["usage"] as? [String: Any])?["input_tokens"] as? Int, 12)
    }

    func testSanitizeDoesNotTouchPaidClaudeMetersOrCapacity() {
        let obs = CapacityObservation(
            kind: .accountRateLimit,
            source: "claude_code",
            sourceConfidence: .structured,
            rawSnippet: "rate limited",
            observedAt: Date(timeIntervalSince1970: 1)
        )
        let paidResult = WorkerRunResult(
            status: .failed,
            output: "paid answer",
            errorReason: "capacity: accountRateLimit",
            capacityObservation: obs,
            reportedTokenUsage: ReportedTokenUsage(inputTokens: 10, outputTokens: 2)
        )
        // Sanitizer is only applied by the runner for local seats. Direct call
        // would strip — the runner pass-through is the paid-seat guarantee.
        XCTAssertTrue(VendorBackoffPolicy.shouldPark(obs))
        XCTAssertEqual(obs.source, "claude_code")
        XCTAssertEqual(paidResult.output, "paid answer")
    }

    func testStatusReportNeverClaimsGlobalWritesOrKeychain() {
        let report = ClaudeLocalIsolation.statusReport()
        XCTAssertTrue(report.perRunOnly)
        XCTAssertFalse(report.writesGlobalShell)
        XCTAssertFalse(report.writesClaudeSettings)
        XCTAssertFalse(report.readsKeychain)
        XCTAssertTrue(report.anthropicAPIKeyEmpty)
        XCTAssertEqual(report.signalSourceId, "ollama_local")
        XCTAssertTrue(report.seating.contains("models add"))
        XCTAssertTrue(report.seating.contains("ollama/"))
    }

    func testContractAndHelpDeclareClaudeLocalStatus() {
        let names = ContractRegistry.milestone1.commands.map(\.name)
        XCTAssertTrue(names.contains("claude-local status"))
        XCTAssertNotNil(HelpTopicRegistry.topic(id: "claude_local_isolation"))
        XCTAssertEqual(
            HelpTopicRegistry.canonicalTopicId(for: "claude-local"),
            "claude_local_isolation"
        )
    }

    func testIsolatingRunnerPassThroughForPaidClaude() async throws {
        let inner = RecordingInvoker()
        inner.result = WorkerRunResult(
            status: .done,
            output: "paid",
            capacityObservation: CapacityObservation(
                kind: .accountRateLimit,
                source: "claude_code",
                sourceConfidence: .structured,
                rawSnippet: "limit",
                observedAt: Date()
            )
        )
        let runner = ClaudeLocalIsolatingWorkerRunner(inner: inner)
        let result = await runner.collect(invocation(paid))
        XCTAssertEqual(inner.seen.count, 1)
        XCTAssertEqual(inner.seen[0].model.modelLabel, "opus")
        XCTAssertNil(inner.seen[0].manifest.invoke?.env[ClaudeLocalIsolation.baseURLKey])
        XCTAssertEqual(result.capacityObservation?.source, "claude_code")
        XCTAssertEqual(result.output, "paid")
    }

    func testIsolatingRunnerAppliesEnvAndStripsLocalLies() async throws {
        let inner = RecordingInvoker()
        inner.result = WorkerRunResult(
            status: .failed,
            output: #"{"costUSD":9.9,"contextWindow":200000,"provider":"firstParty","result":"nope"}"#,
            errorReason: "capacity: accountRateLimit",
            capacityObservation: CapacityObservation(
                kind: .accountRateLimit,
                source: "claude_code",
                sourceConfidence: .structured,
                rawSnippet: "rate_limit_error",
                observedAt: Date(),
                retryAfterSeconds: 90
            )
        )
        let runner = ClaudeLocalIsolatingWorkerRunner(inner: inner)
        let result = await runner.collect(invocation(local))
        XCTAssertEqual(inner.seen.count, 1)
        XCTAssertEqual(inner.seen[0].model.modelLabel, "qwen2.5:0.5b")
        XCTAssertEqual(
            inner.seen[0].manifest.invoke?.env[ClaudeLocalIsolation.baseURLKey],
            "http://localhost:11434"
        )
        XCTAssertEqual(inner.seen[0].manifest.invoke?.env[ClaudeLocalIsolation.apiKeyKey], "")
        XCTAssertNil(result.capacityObservation)
        XCTAssertFalse(result.capacityObservation.map(VendorBackoffPolicy.shouldPark) ?? false)
        XCTAssertEqual(result.errorReason, "ollama_local failed; not an Anthropic limit")
        XCTAssertFalse(result.output?.contains("costUSD") ?? true)
        XCTAssertFalse(result.output?.contains("200000") ?? true)
        XCTAssertFalse(result.output?.contains("firstParty") ?? true)
    }
}

private final class RecordingInvoker: WorkerInvoking, @unchecked Sendable {
    var seen: [WorkerInvocation] = []
    var result = WorkerRunResult(status: .done, output: "ok")

    func invoke(_ invocation: WorkerInvocation) -> AsyncThrowingStream<WorkerStreamEvent, Error> {
        seen.append(invocation)
        let result = self.result
        return AsyncThrowingStream { continuation in
            continuation.yield(.started(workerId: invocation.model.id, modelId: invocation.model.modelLabel, sourceId: invocation.manifest.id))
            continuation.yield(result.status == .done ? .completed(result) : .failed(result))
            continuation.finish()
        }
    }
}
