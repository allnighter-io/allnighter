import AppKit
import Foundation
import AllnighterCore
import AllnighterEngine
import AgentOSTeam

@MainActor
extension ThreadsViewModel {
    // MARK: - GUI fixtures

    func applyFixture(_ fixture: String) {
        #if DEBUG
        if fixture == "thread-empty" {
            _ = newThread(title: Self.newChatTitle)
            return
        }
        if fixture == "thread-live-artifact" {
            seedLiveArtifactFixture()
            return
        }
        ThreadsFixtureSeeder(
            store: store,
            runStore: runStore,
            models: models,
            registry: registry,
            reload: { self.reload() },
            select: { self.select($0) },
            setSelectedThreadId: { self.selectedThreadId = $0 },
            threads: { self.threads }
        ).apply(fixture)
        #endif
    }

    #if DEBUG
    /// GUI proof: running team board with live artifact seats (TRR-S01c).
    private func seedLiveArtifactFixture() {
        let threadId = "fixture-live-artifact"
        let runId = "fixture-live-artifact-run"
        _ = try? store.create(id: threadId, title: "API rate limiting strategy", now: Date())

        let picks = Array(models.filter(\.enabled).prefix(3))
        let m0 = picks.indices.contains(0) ? picks[0].id : "model_opus"
        let m1 = picks.indices.contains(1) ? picks[1].id : "model_grok"
        let m2 = picks.indices.contains(2) ? picks[2].id : "model_gemini"
        let w0 = Agent(
            id: Agent.makeID(modelId: m0, instanceIndex: 0), modelId: m0, instanceIndex: 0,
            skillId: "reader", skillName: "Reader", purpose: .answer)
        let w1 = Agent(
            id: Agent.makeID(modelId: m1, instanceIndex: 0), modelId: m1, instanceIndex: 0,
            skillId: "scout", skillName: "Scout", purpose: .answer)
        let w2 = Agent(
            id: Agent.makeID(modelId: m2, instanceIndex: 1), modelId: m2, instanceIndex: 1,
            skillId: "lead", skillName: "Lead", purpose: .plan)

        let started = Date().addingTimeInterval(-12)
        let run = TeamRun(
            id: runId,
            prompt: "Per-user rate limiting for the public API — recommend an approach and trade-offs.",
            status: .fanningOut,
            origin: .gui,
            presetId: "code_spec_review",
            workers: [w0, w1, w2],
            answers: [
                TeamAnswer(
                    memberId: w0.id, modelId: m0, role: "answer",
                    result: WorkerRunResult(
                        status: .running,
                        output: "Token bucket fits burst traffic while holding sustained rate…",
                        timing: RunTiming(startedAt: started))),
                TeamAnswer(memberId: w1.id, modelId: m1, role: "answer",
                           result: WorkerRunResult(status: .queued)),
                TeamAnswer(memberId: w2.id, modelId: m2, role: "plan",
                           result: WorkerRunResult(status: .queued)),
            ],
            createdAt: Date(),
            teamDisplayName: "Spec Review"
        )
        _ = try? runStore.save(run, models: models)

        let user = ThreadTurn(
            id: "fixture-live-artifact-user", threadId: threadId, kind: .userMessage, status: .done,
            createdAt: Date(), completedAt: Date(), author: .user,
            text: "Per-user rate limiting for the public API — send it to the team and recommend an approach."
        )
        let board = ThreadTurn(
            id: "fixture-live-artifact-board", threadId: threadId, kind: .teamRun, status: .running,
            createdAt: Date(), author: .worker, runId: runId
        )
        _ = try? store.appendTurn(user, toThreadId: threadId, now: Date())
        _ = try? store.appendTurn(board, toThreadId: threadId, now: Date())
        reload()
        selectedThreadId = threadId

        let context = ArtifactProjector.Context(models: models)
        var state = LiveArtifactProjector.seed(run: run, context: context)
        let events: [RunEvent] = [
            RunEvent(
                id: "fixture-la-e1", seq: 1, ts: started,
                kind: RunEventKind.workerStatusChanged,
                payload: [
                    "workerId": .string(w0.id),
                    "to": .string(WorkerAnswerStatus.running.rawValue),
                ]),
            RunEvent(
                id: "fixture-la-e2", seq: 2, ts: started.addingTimeInterval(3),
                kind: RunEventKind.workerAnswerDelta,
                payload: [
                    "workerId": .string(w0.id),
                    "text": .string("**Token bucket** — allows controlled bursts up to bucket size."),
                ]),
            RunEvent(
                id: "fixture-la-e3", seq: 3, ts: started.addingTimeInterval(5),
                kind: RunEventKind.workerStatusChanged,
                payload: [
                    "workerId": .string(w1.id),
                    "to": .string(WorkerAnswerStatus.running.rawValue),
                ]),
        ]
        for event in events { _ = LiveArtifactProjector.apply(event, to: &state) }
        liveArtifactByRunId[runId] = state
        _ = bumpPublishGeneration()
    }
    #endif
}
