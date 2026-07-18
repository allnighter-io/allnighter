import XCTest
import AgentOSTeam
import AllnighterCore
@testable import AllnighterEngine

/// Concurrent Invocation Isolation F4 — wrong-document delivery: repro + gate.
///
/// REPRODUCED (this file's first test, RED before the gate): the runner trusted
/// `runner_request.json` blindly — it re-assembled the prompt from the DELIVERED
/// packet, never comparing it to the run's own minted journal, so a
/// cross-delivered packet (a concurrent orchestration's brief staged into
/// another run's dir) executed verbatim under the wrong run id. Verified RED on
/// 2026-07-18: `run A accepted and executed project B's context packet`.
///
/// THE GATE: every staged packet carries immutable `RunContextProvenance`
/// (resolved absolute root + content hash + thread/run id); the runner refuses
/// (CONTEXT_PROVENANCE_MISMATCH) any packet that is not its run's own request —
/// run-id match, hash recompute, then a cross-check against the minted journal.
final class RunContextProvenanceTests: XCTestCase {

    private static let planMarkdown = "# Plan\nAsync ok."

    private func makeService(support: URL) -> AsyncTeamService {
        let team = TeamPreset(
            id: "code_test", displayName: "Test", lane: .code, outputKind: .plan, defaultEffort: .low,
            isDefaultForLane: true,
            workerSpecs: [TeamWorkerSpec(id: "r1", skillId: "bug_reproducer", purpose: .answer)],
            lead: TeamLeadSpec(skillId: "plan_writer_build"),
            builtIn: true)
        let opus = Model(id: "model_opus", displayName: "Opus", modelLabel: "opus", driverId: "claude_code", role: .both)
        let registry = DriverRegistry([TestSupport.headlessManifest(id: "claude_code", command: "claude")])
        let mock = MockCommandRunner(scripts: [
            "claude": .init(stdout: Self.planMarkdown, delay: .milliseconds(200))
        ])
        var env = ProcessInfo.processInfo.environment
        env.removeValue(forKey: "ALLNIGHTER_TEAM_DEPTH")
        return AsyncTeamService(
            models: [opus],
            registry: registry,
            teams: [team],
            config: ToolConfig(maxConcurrentTeamRuns: 2, maxTeamRunDepth: 1),
            runStore: RunStore(rootDirectory: support.appendingPathComponent("Runs")),
            commandRunner: mock,
            governor: TeamGovernor(directory: support.appendingPathComponent("gov"), capacity: 2),
            idempotency: IdempotencyStore(fileURL: support.appendingPathComponent("idempotency.json")),
            environment: env
        )
    }

    private let readyBench = [Model(id: "model_opus", displayName: "Opus", modelLabel: "opus", driverId: "claude_code", role: .both)]

    /// Mirrors `AsyncTeamService.assemblePrompt` for small (untruncated)
    /// contexts: the journal's minted prompt is question + context section.
    private func assembledPrompt(question: String, context: String?) -> String {
        guard let context, !context.isEmpty else { return question }
        return question + "\n\n# Context\n" + context
    }

    private func request(
        question: String, context: String?, threadId: String?, repoRoot: String?
    ) -> AsyncTeamStartRequest {
        AsyncTeamStartRequest(
            question: question,
            lane: .code, teamPresetId: "code_test", effort: .low,
            context: context,
            threadId: threadId,
            repoRoot: repoRoot
        )
    }

    /// A packet staged exactly as `team start` stages it: provenance stamped
    /// over the given fields with the canonical resolved root.
    private func legitPacket(
        runId: String,
        question: String, context: String?, threadId: String?, repoRoot: String?
    ) -> AsyncTeamRunnerRequest {
        let req = request(question: question, context: context, threadId: threadId, repoRoot: repoRoot)
        return AsyncTeamRunnerRequest(
            request: req,
            origin: .cli,
            acceptedAt: Date(),
            provenance: RunContextProvenance.make(
                runId: runId, question: question, context: context,
                threadId: threadId,
                resolvedRepoRoot: repoRoot.flatMap { RunWriteLock.normalize($0) }
            )
        )
    }

    /// Stage a run journal exactly as `team start` mints it (its OWN request),
    /// then write an arbitrary packet into the run dir.
    private func stage(
        store: RunStore,
        runId: String,
        journal: (question: String, context: String?, threadId: String?, repoRoot: String?),
        packet: AsyncTeamRunnerRequest
    ) throws -> URL {
        let runDir = try store.runDirectory(forRunId: runId)
        let run = TeamRun(
            id: runId,
            prompt: assembledPrompt(question: journal.question, context: journal.context),
            status: .fanningOut,
            createdAt: Date(),
            threadId: journal.threadId,
            repoRoot: journal.repoRoot
        )
        try CoreJSON.encode(run).write(to: runDir.appendingPathComponent("run.json"), options: .atomic)
        try CoreJSON.encode(packet).write(
            to: runDir.appendingPathComponent(ProcessOwnership.runnerRequestFileName), options: .atomic)
        return runDir
    }

    private func makeSupport() -> URL {
        URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("f4-\(UUID().uuidString)", isDirectory: true)
    }

    // MARK: - The repro: a concurrent orchestration's brief in the WRONG run's dir

    func testWrongDocumentDelivery_crossDeliveredPacketIsRejected() async throws {
        let support = makeSupport()
        defer { try? FileManager.default.removeItem(at: support) }
        let store = RunStore(rootDirectory: support.appendingPathComponent("Runs"))
        let service = makeService(support: support)

        let repoA = support.appendingPathComponent("repoA").path
        let repoB = support.appendingPathComponent("repoB").path

        // Run A's journal carries A's own request — minted at accept time.
        // The packet in A's dir is B's own legitimate packet (wrong delivery).
        let runDirA = try stage(
            store: store, runId: "run-a",
            journal: (question: "fix project A", context: "project A's own context",
                      threadId: "thread-a", repoRoot: repoA),
            packet: legitPacket(
                runId: "run-b",
                question: "review the relay brief", context: "PROJECT B ORCHESTRATION BRIEF",
                threadId: "thread-b", repoRoot: repoB
            )
        )

        let outcome = await service.executeRunner(runId: "run-a", readyModels: readyBench)
        guard case .failure(let refusal) = outcome else {
            return XCTFail("WRONG-DOCUMENT DELIVERY: run A accepted and executed project B's context packet")
        }
        XCTAssertEqual(refusal.code, "CONTEXT_PROVENANCE_MISMATCH")

        // The journal was never executed against B's context.
        let journal = try XCTUnwrap(store.loadRaw(runId: "run-a"))
        XCTAssertEqual(journal.status, .fanningOut, "refused run must not have executed")
        XCTAssertEqual(journal.prompt, assembledPrompt(question: "fix project A", context: "project A's own context"))
        XCTAssertEqual(journal.threadId, "thread-a")
        // Refusal is a typed handshake, not a silent death.
        let handshake = try XCTUnwrap(ProcessOwnership.readRunnerReady(in: runDirA))
        XCTAssertEqual(handshake.outcome, .refused)
        XCTAssertEqual(handshake.refusalCode, "CONTEXT_PROVENANCE_MISMATCH")
    }

    // MARK: - Content swapped under the RIGHT run id (hash honestly recomputed)

    func testWrongDocumentDelivery_contentSwappedUnderOwnRunIdIsRejected() async throws {
        let support = makeSupport()
        defer { try? FileManager.default.removeItem(at: support) }
        let store = RunStore(rootDirectory: support.appendingPathComponent("Runs"))
        let service = makeService(support: support)
        let repoA = support.appendingPathComponent("repoA").path

        // Packet claims run A and its hash matches its (B's) content — the
        // packet-internal checks pass; only the journal cross-check can catch it.
        let swapped = legitPacket(
            runId: "run-a",
            question: "review the relay brief", context: "PROJECT B ORCHESTRATION BRIEF",
            threadId: "thread-b", repoRoot: repoA
        )
        _ = try stage(
            store: store, runId: "run-a",
            journal: (question: "fix project A", context: "project A's own context",
                      threadId: "thread-a", repoRoot: repoA),
            packet: swapped
        )

        let outcome = await service.executeRunner(runId: "run-a", readyModels: readyBench)
        guard case .failure(let refusal) = outcome else {
            return XCTFail("content-swapped packet under the run's own id executed")
        }
        XCTAssertEqual(refusal.code, "CONTEXT_PROVENANCE_MISMATCH")
        let journal = try XCTUnwrap(store.loadRaw(runId: "run-a"))
        XCTAssertEqual(journal.status, .fanningOut)
        XCTAssertEqual(journal.threadId, "thread-a")
    }

    // MARK: - Hash tampering (content edited, stale hash kept)

    func testWrongDocumentDelivery_tamperedContentWithStaleHashIsRejected() async throws {
        let support = makeSupport()
        defer { try? FileManager.default.removeItem(at: support) }
        let store = RunStore(rootDirectory: support.appendingPathComponent("Runs"))
        let service = makeService(support: support)
        let repoA = support.appendingPathComponent("repoA").path

        // Take A's legit packet, then rewrite the question in flight — the
        // stamped hash no longer matches the delivered bytes.
        var tampered = legitPacket(
            runId: "run-a",
            question: "fix project A", context: "project A's own context",
            threadId: "thread-a", repoRoot: repoA
        )
        tampered.request.question = "review the relay brief"
        _ = try stage(
            store: store, runId: "run-a",
            journal: (question: "fix project A", context: "project A's own context",
                      threadId: "thread-a", repoRoot: repoA),
            packet: tampered
        )

        let outcome = await service.executeRunner(runId: "run-a", readyModels: readyBench)
        guard case .failure(let refusal) = outcome else {
            return XCTFail("tampered packet with a stale hash executed")
        }
        XCTAssertEqual(refusal.code, "CONTEXT_PROVENANCE_MISMATCH")
    }

    // MARK: - Positive control: the run's own packet executes

    func testLegitimatePacketExecutesWithOwnContext() async throws {
        let support = makeSupport()
        defer { try? FileManager.default.removeItem(at: support) }
        let store = RunStore(rootDirectory: support.appendingPathComponent("Runs"))
        let service = makeService(support: support)
        let repoA = support.appendingPathComponent("repoA").path

        let runDirA = try stage(
            store: store, runId: "run-a",
            journal: (question: "fix project A", context: "project A's own context",
                      threadId: "thread-a", repoRoot: repoA),
            packet: legitPacket(
                runId: "run-a",
                question: "fix project A", context: "project A's own context",
                threadId: "thread-a", repoRoot: repoA
            )
        )

        let outcome = await service.executeRunner(runId: "run-a", readyModels: readyBench)
        guard case .success = outcome else {
            return XCTFail("the run's own packet must execute: \(outcome)")
        }
        let handshake = try XCTUnwrap(ProcessOwnership.readRunnerReady(in: runDirA))
        XCTAssertEqual(handshake.outcome, .accepted)
        // The journal kept its own context through execution.
        let journal = try XCTUnwrap(store.loadRaw(runId: "run-a"))
        XCTAssertEqual(journal.prompt, assembledPrompt(question: "fix project A", context: "project A's own context"))
        XCTAssertEqual(journal.threadId, "thread-a")
        XCTAssertEqual(RunWriteLock.normalize(journal.repoRoot), RunWriteLock.normalize(repoA))
    }
}
