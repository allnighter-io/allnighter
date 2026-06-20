import Foundation
import AllnighterCore
import AllnighterEngine

#if DEBUG
/// GUI fixture seeding for `ThreadsViewModel` — isolated from production routing.
@MainActor
struct ThreadsFixtureSeeder {
    let store: ThreadStore
    let runStore: RunStore
    let models: [Model]
    let registry: DriverRegistry
    let reload: () -> Void
    let select: (WorkThread) -> Void
    let setSelectedThreadId: (String?) -> Void
    let threads: () -> [WorkThread]

    func apply(_ fixture: String) {
        switch fixture {
        case "home-with-threads":
            seedFixtureThreads()
            setSelectedThreadId(nil)
        case "thread-with-turns":
            seedFixtureThreadWithTurns()
        case "thread-chat":
            seedFixtureChatExchange()
        case "thread-team-board":
            seedFixtureTeamBoard()
        case "thread-mutating-run":
            seedFixtureMutatingRun()
        case "thread-streaming":
            seedFixtureStreamingChat()
        case "thread-streaming-build":
            seedFixtureStreamingBuild()
        case "home-rail":
            seedFixtureRail()
            setSelectedThreadId(nil)
        case "home-rail-th2":
            seedFixtureRailControls()
            setSelectedThreadId(nil)
        case "home-rail-unr":
            seedFixtureUnreadMatrix()
        case "projects-rail":
            seedFixtureProjectsRail()
            reload()
            setSelectedThreadId(nil)
        default:
            break
        }
    }

    private func seedFixtureProjectsRail() {
        let base = Date()
        func mk(_ id: String, _ title: String, _ ago: TimeInterval, project: String?, pinned: Bool = false, unread: Bool = false) {
            guard (try? store.create(id: id, title: title, now: base.addingTimeInterval(-ago))) != nil else { return }
            if let project { _ = try? store.bindProject(threadId: id, projectId: project) }
            if pinned { _ = try? store.setPinned(threadId: id, pinned: true, now: base) }
            if unread {
                let t = ThreadTurn(id: "\(id)-t", threadId: id, kind: .workerChat, status: .done,
                                   createdAt: base, completedAt: base, author: .worker)
                _ = try? store.appendTurn(t, toThreadId: id, now: base)
            }
        }
        mk("pr-pin", "Redesign the profile screen now", 30, project: "prj_halo", pinned: true)
        mk("pr-halo-1", "Onboarding empty states", 720, project: "prj_halo", unread: true)
        mk("pr-halo-2", "Rate-limit the public API", 60, project: "prj_halo")
        mk("pr-halo-3", "Dark-mode token audit", 7200, project: "prj_halo")
        mk("pr-halo-4", "Fix the uploader client", 10000, project: "prj_halo")
        mk("pr-halo-5", "Refactor the settings screen", 12000, project: "prj_halo")
        mk("pr-web-1", "First page POC implementation", 300, project: "prj_web")
        mk("pr-un-1", "Token bucket vs sliding window", 900, project: nil)
    }

    private func seedFixtureRail() {
        let base = Date()
        func turn(_ tid: String, _ thread: String, _ kind: ThreadTurnKind, _ status: ThreadTurnStatus) -> ThreadTurn {
            ThreadTurn(id: tid, threadId: thread, kind: kind, status: status,
                       createdAt: base, completedAt: status.isTerminal ? base : nil, author: .worker)
        }

        if (try? store.create(id: "rail-design", title: "Redesign the onboarding flow", now: base.addingTimeInterval(-600))) != nil {
            _ = try? store.appendTurn(turn("rail-design-t", "rail-design", .designBoard, .done), toThreadId: "rail-design", now: base)
            _ = try? store.setPinned(threadId: "rail-design", pinned: true, now: base)
        }
        if (try? store.create(id: "rail-build", title: "Rate-limit the public API", now: base.addingTimeInterval(-120))) != nil {
            _ = try? store.appendTurn(turn("rail-build-t1", "rail-build", .teamRun, .done), toThreadId: "rail-build", now: base)
            _ = try? store.appendTurn(turn("rail-build-t2", "rail-build", .mutatingRun, .running), toThreadId: "rail-build", now: base)
        }
        if (try? store.create(id: "rail-build2", title: "Refactor the uploader client", now: base.addingTimeInterval(-300))) != nil {
            _ = try? store.appendTurn(turn("rail-build2-t", "rail-build2", .mutatingRun, .done), toThreadId: "rail-build2", now: base)
        }
        _ = try? store.create(id: "rail-chat", title: "Token bucket vs sliding window", now: base.addingTimeInterval(-900))
        reload()
    }

    private func seedFixtureRailControls() {
        let base = Date()
        func workerDone(_ id: String, threadId: String, at: Date) -> ThreadTurn {
            ThreadTurn(id: id, threadId: threadId, kind: .workerChat, status: .done,
                       createdAt: at, completedAt: at, author: .worker, text: "reply", workerId: "model_opus")
        }

        if (try? store.create(id: "th2-pinned", title: "Pinned planning thread", now: base.addingTimeInterval(-300))) != nil {
            _ = try? store.setPinned(threadId: "th2-pinned", pinned: true, now: base)
        }
        if (try? store.create(id: "th2-unread", title: "Unread worker reply", now: base.addingTimeInterval(-60))) != nil {
            _ = try? store.appendTurn(workerDone("th2-unread-w", threadId: "th2-unread", at: base), toThreadId: "th2-unread", now: base)
        }
        if (try? store.create(id: "th2-archived", title: "Archived finished thread", now: base.addingTimeInterval(-900))) != nil {
            _ = try? store.appendTurn(workerDone("th2-arch-w", threadId: "th2-archived", at: base.addingTimeInterval(-800)),
                                     toThreadId: "th2-archived", now: base)
            _ = try? store.setPinned(threadId: "th2-archived", pinned: true, now: base)
            _ = try? store.archiveThread(threadId: "th2-archived")
        }
        reload()
    }

    private func seedFixtureUnreadMatrix() {
        let base = Date()
        let workerId = models.first?.id ?? "model_opus"

        func userTurn(_ id: String, threadId: String, at: Date, text: String = "question") -> ThreadTurn {
            ThreadTurn(
                id: id, threadId: threadId, kind: .userMessage, status: .done,
                createdAt: at, completedAt: at, author: .user, text: text
            )
        }

        func workerTurn(
            _ id: String, threadId: String, at: Date, status: ThreadTurnStatus,
            text: String = "reply"
        ) -> ThreadTurn {
            ThreadTurn(
                id: id, threadId: threadId, kind: .workerChat, status: status,
                createdAt: at, completedAt: status.isTerminal ? at : nil,
                author: .worker, text: text, workerId: workerId
            )
        }

        if (try? store.create(id: "unr-idle", title: "Read — idle", now: base.addingTimeInterval(-500))) != nil {
            _ = try? store.appendTurn(userTurn("unr-idle-u", threadId: "unr-idle", at: base.addingTimeInterval(-480)),
                                     toThreadId: "unr-idle", now: base.addingTimeInterval(-480))
            _ = try? store.appendTurn(workerTurn("unr-idle-w", threadId: "unr-idle", at: base.addingTimeInterval(-470), status: .done),
                                     toThreadId: "unr-idle", now: base.addingTimeInterval(-470))
            _ = try? store.markRead(threadId: "unr-idle", throughTurnId: "unr-idle-w", now: base.addingTimeInterval(-469))
        }

        if (try? store.create(id: "unr-reply", title: "Unread — worker reply", now: base.addingTimeInterval(-400))) != nil {
            _ = try? store.appendTurn(userTurn("unr-reply-u", threadId: "unr-reply", at: base.addingTimeInterval(-390)),
                                     toThreadId: "unr-reply", now: base.addingTimeInterval(-390))
            _ = try? store.appendTurn(workerTurn("unr-reply-w", threadId: "unr-reply", at: base.addingTimeInterval(-380), status: .done,
                                                  text: "Token bucket — allows bursts while holding the average."),
                                     toThreadId: "unr-reply", now: base.addingTimeInterval(-380))
        }

        if (try? store.create(id: "unr-attention", title: "Unread — failed worker", now: base.addingTimeInterval(-350))) != nil {
            _ = try? store.appendTurn(userTurn("unr-attention-u", threadId: "unr-attention", at: base.addingTimeInterval(-340)),
                                     toThreadId: "unr-attention", now: base.addingTimeInterval(-340))
            _ = try? store.appendTurn(workerTurn("unr-attention-w", threadId: "unr-attention", at: base.addingTimeInterval(-330),
                                                  status: .failed, text: "The worker failed."),
                                     toThreadId: "unr-attention", now: base.addingTimeInterval(-330))
        }

        if (try? store.create(id: "unr-running", title: "Running — no unread", now: base.addingTimeInterval(-300))) != nil {
            _ = try? store.appendTurn(userTurn("unr-running-u", threadId: "unr-running", at: base.addingTimeInterval(-290)),
                                     toThreadId: "unr-running", now: base.addingTimeInterval(-290))
            _ = try? store.appendTurn(workerTurn("unr-running-w", threadId: "unr-running", at: base.addingTimeInterval(-280), status: .running),
                                     toThreadId: "unr-running", now: base.addingTimeInterval(-280))
        }

        if (try? store.create(id: "unr-running-unread", title: "Running + unread", now: base.addingTimeInterval(-250))) != nil {
            _ = try? store.appendTurn(userTurn("unr-run-unread-u", threadId: "unr-running-unread", at: base.addingTimeInterval(-240)),
                                     toThreadId: "unr-running-unread", now: base.addingTimeInterval(-240))
            _ = try? store.appendTurn(workerTurn("unr-run-unread-w1", threadId: "unr-running-unread", at: base.addingTimeInterval(-230),
                                                  status: .done, text: "Earlier reply you have not opened."),
                                     toThreadId: "unr-running-unread", now: base.addingTimeInterval(-230))
            _ = try? store.appendTurn(workerTurn("unr-run-unread-w2", threadId: "unr-running-unread", at: base.addingTimeInterval(-220), status: .running),
                                     toThreadId: "unr-running-unread", now: base.addingTimeInterval(-220))
        }

        if (try? store.create(id: "unr-selected", title: "Selected unread (below fold)", now: base.addingTimeInterval(-200))) != nil {
            for index in 0..<12 {
                let at = base.addingTimeInterval(Double(-190 + index))
                _ = try? store.appendTurn(
                    userTurn("unr-selected-u\(index)", threadId: "unr-selected", at: at,
                             text: "Earlier context message \(index + 1)."),
                    toThreadId: "unr-selected", now: at
                )
            }
            let unreadAt = base.addingTimeInterval(-60)
            _ = try? store.appendTurn(
                workerTurn("unr-selected-w", threadId: "unr-selected", at: unreadAt, status: .done,
                           text: "Unread reply below the visible viewport."),
                toThreadId: "unr-selected", now: unreadAt
            )
        }

        reload()
        if let selected = threads().first(where: { $0.id == "unr-selected" }) {
            select(selected)
        }
    }

    private func seedFixtureThreads() {
        let base = Date()
        let titles = [
            "Token bucket vs sliding window",
            "Redesign the profile screen",
            "Rate-limit the public API",
        ]
        for (index, title) in titles.enumerated() {
            _ = try? store.create(
                id: "fixture-\(index)",
                title: title,
                now: base.addingTimeInterval(TimeInterval(-index * 120))
            )
        }
        reload()
    }

    private func seedFixtureThreadWithTurns() {
        let id = "fixture-thread"
        _ = try? store.create(id: id, title: "Token bucket vs sliding window", now: Date())
        let turn = ThreadTurn(
            id: "fixture-turn-1",
            threadId: id,
            kind: .userMessage,
            status: .done,
            createdAt: Date(),
            completedAt: Date(),
            author: .user,
            text: "For per-user API rate limiting — token bucket or sliding window? Short answer + why."
        )
        _ = try? store.appendTurn(turn, toThreadId: id, now: Date())
        reload()
        setSelectedThreadId(id)
    }

    private func seedFixtureChatExchange() {
        let id = "fixture-chat"
        _ = try? store.create(id: id, title: "Token bucket vs sliding window", now: Date())
        let workerId = models.first { $0.id == "model_opus" }?.id ?? models.first?.id ?? "model_opus"
        let user = ThreadTurn(
            id: "fixture-chat-user", threadId: id, kind: .userMessage, status: .done,
            createdAt: Date(), completedAt: Date(), author: .user,
            text: "For per-user API rate limiting — token bucket or sliding window? Short answer + why."
        )
        let reply = ThreadTurn(
            id: "fixture-chat-reply", threadId: id, kind: .workerChat, status: .done,
            createdAt: Date(), completedAt: Date(), author: .worker,
            text: "**Token bucket.** It allows short bursts (up to the bucket size) while holding the long-run average to the refill rate — which is what per-user API limits actually want. Sliding-window log is more precise but stores every timestamp per user (memory + GC churn); sliding-window counter approximates it but still smooths bursts away. For rate limiting, allow the burst: token bucket, refill = your sustained rate, capacity = your burst budget.",
            workerId: workerId
        )
        _ = try? store.appendTurn(user, toThreadId: id, now: Date())
        _ = try? store.appendTurn(reply, toThreadId: id, now: Date())
        reload()
        setSelectedThreadId(id)
    }

    /// A worker_chat turn mid-stream: status `.running` with partial text already
    /// flowed in (STR-S08). Proves the live render — partial text + a streaming
    /// affordance — vs. the bare "running…" placeholder.
    private func seedFixtureStreamingChat() {
        let id = "fixture-streaming"
        _ = try? store.create(id: id, title: "Explain backpressure", now: Date())
        let workerId = models.first { $0.id == "model_grok" }?.id ?? models.first?.id ?? "model_grok"
        let user = ThreadTurn(
            id: "fixture-streaming-user", threadId: id, kind: .userMessage, status: .done,
            createdAt: Date(), completedAt: Date(), author: .user,
            text: "Explain backpressure in streaming systems in two sentences.")
        let reply = ThreadTurn(
            id: "fixture-streaming-reply", threadId: id, kind: .workerChat, status: .running,
            createdAt: Date(), author: .worker,
            text: "Backpressure is how a fast producer is slowed to a rate its slower consumer can actually keep up with, so queues don't grow without bound. The consumer signals demand upstream — pull-based or via a bounded buffer that blocks the produc",
            workerId: workerId)
        _ = try? store.appendTurn(user, toThreadId: id, now: Date())
        _ = try? store.appendTurn(reply, toThreadId: id, now: Date())
        reload()
        setSelectedThreadId(id)
    }

    /// A mutating (Auto/execution) run mid-stream: the `mutatingRun` turn is
    /// `.running` with partial text already streamed in — the path the default Auto
    /// run actually takes (RunService), proving the live render vs. bare "Working…".
    private func seedFixtureStreamingBuild() {
        let id = "fixture-streaming-build"
        _ = try? store.create(id: id, title: "Add a health endpoint", now: Date(),
                              workingDir: "/Users/you/code/app")
        let workerId = models.first { $0.id == "model_cursor_composer_25" }?.id ?? models.first?.id ?? "model_cursor_composer_25"
        let user = ThreadTurn(
            id: "fixture-streaming-build-user", threadId: id, kind: .userMessage, status: .done,
            createdAt: Date(), completedAt: Date(), author: .user,
            text: "Add a /health endpoint that returns 200 OK and run the tests.")
        let run = ThreadTurn(
            id: "fixture-streaming-build-turn", threadId: id, kind: .mutatingRun, status: .running,
            createdAt: Date(), author: .worker,
            text: "I'll add a `/health` route. Looking at the router setup in `app/server.swift`… adding a handler that returns `Response(status: .ok, body: \"OK\")`, wiring it into the route table, then I'll run `swift test` to confir",
            workerId: workerId, runId: "fixture-streaming-build-run")
        _ = try? store.appendTurn(user, toThreadId: id, now: Date())
        _ = try? store.appendTurn(run, toThreadId: id, now: Date())
        reload()
        setSelectedThreadId(id)
    }

    private func seedFixtureTeamBoard() {
        let id = "fixture-team"
        _ = try? store.create(id: id, title: "Rate-limit the public API", now: Date())

        let picks = models.filter { $0.enabled }.prefix(2)
        let m0 = picks.first?.id ?? "model_opus"
        let m1 = picks.dropFirst().first?.id ?? "model_grok"
        let w0 = Worker(id: Worker.makeID(modelId: m0, instanceIndex: 0), modelId: m0,
                        instanceIndex: 0, skillId: "answer", skillName: "Answer", purpose: .answer)
        let w1 = Worker(id: Worker.makeID(modelId: m1, instanceIndex: 0), modelId: m1,
                        instanceIndex: 0, skillId: "answer", skillName: "Answer", purpose: .answer)
        let writer = Worker(id: Worker.makeID(modelId: m0, instanceIndex: 1), modelId: m0,
                            instanceIndex: 1, skillId: "plan_writer", skillName: "Plan writer", purpose: .plan)

        var run = TeamRun(
            id: "fixture-team-run", prompt: "Per-user rate limiting for the public API — recommend an approach.",
            status: .complete, origin: .gui, presetId: "build_panel",
            workers: [w0, w1, writer],
            workerAnswers: [
                WorkerAnswer(workerId: w0.id, modelId: m0, status: .done,
                             output: "**Token bucket.** Allows controlled bursts up to the bucket size while holding the long-run average to the refill rate — the right fit for per-user API limits.",
                             durationMs: 4200),
                WorkerAnswer(workerId: w1.id, modelId: m1, status: .done,
                             output: "**Sliding-window counter.** Smoother than fixed windows and cheap to store (two counters per user); slightly approximates the boundary but avoids the double-burst edge of fixed windows.",
                             durationMs: 5100),
            ],
            createdAt: Date()
        )
        run.stages = [StageOutput(
            id: "fixture-team-plan", purpose: .plan, producedByWorkerId: writer.id,
            promptProfileId: "plan_writer", status: .done,
            payload: .plan(markdown: "**Recommendation: token bucket**, refill = sustained rate, capacity = burst budget. It satisfies the burst requirement both answers agreed on; the sliding-window counter is the fallback if memory per user must stay flat. Minority view (worker 2) preserved: prefer sliding-window if exact boundary fairness matters more than bursts."),
            startedAt: Date(), finishedAt: Date()
        )]
        _ = try? runStore.save(run, models: models)

        let user = ThreadTurn(
            id: "fixture-team-user", threadId: id, kind: .userMessage, status: .done,
            createdAt: Date(), completedAt: Date(), author: .user,
            text: "Per-user rate limiting for the public API — send it to the team and recommend an approach."
        )
        let board = ThreadTurn(
            id: "fixture-team-board", threadId: id, kind: .teamRun, status: .done,
            createdAt: Date(), completedAt: Date(), author: .worker, runId: run.id
        )
        _ = try? store.appendTurn(user, toThreadId: id, now: Date())
        _ = try? store.appendTurn(board, toThreadId: id, now: Date())
        reload()
        setSelectedThreadId(id)
    }

    private func seedFixtureMutatingRun() {
        let id = "fixture-mutating-run"
        _ = try? store.create(id: id, title: "Add retry to the upload client", now: Date(),
                              workingDir: "/Users/you/code/uploader")
        let workerId = models.first { $0.id == "model_claude_code" }?.id
            ?? models.first { registry.manifest(for: $0)?.kind == .headlessCLI }?.id
            ?? models.first?.id ?? "model_claude_code"

        var run = TeamRun(id: "fixture-mutating-run-run", prompt: "Add retry to the upload client",
                          status: .complete, origin: .gui,
                          workers: [Worker(id: Worker.makeID(modelId: workerId, instanceIndex: 0),
                                           modelId: workerId, instanceIndex: 0,
                                           skillId: "first_principles_builder", purpose: .answer)],
                          workerAnswers: [
                              WorkerAnswer(
                                  workerId: Worker.makeID(modelId: workerId, instanceIndex: 0),
                                  modelId: workerId, status: .done,
                                  output: "Added exponential backoff (3 attempts, jitter) to `UploadClient.send`. Updated tests: `UploadClientTests.testRetriesOnTransient` passes. Ran `swift test` — 42 passing."
                              )
                          ],
                          createdAt: Date(),
                          mutating: true)
        run.stages = [StageOutput(
            id: "fixture-mutating-run-stage", purpose: .plan, producedByWorkerId: workerId,
            status: .done,
            payload: .plan(markdown: "Added exponential backoff (3 attempts, jitter) to `UploadClient.send`. Updated tests: `UploadClientTests.testRetriesOnTransient` passes. Ran `swift test` — 42 passing."),
            startedAt: Date(), finishedAt: Date()
        )]
        _ = try? runStore.save(run, models: models)

        let user = ThreadTurn(
            id: "fixture-mutating-run-user", threadId: id, kind: .userMessage, status: .done,
            createdAt: Date(), completedAt: Date(), author: .user,
            text: "Add exponential backoff retry to the upload client and run the tests."
        )
        let mutatingRun = ThreadTurn(
            id: "fixture-mutating-run-turn", threadId: id, kind: .mutatingRun, status: .done,
            createdAt: Date(), completedAt: Date(), author: .worker,
            workerId: workerId, runId: run.id, stageId: "fixture-mutating-run-stage"
        )
        _ = try? store.appendTurn(user, toThreadId: id, now: Date())
        _ = try? store.appendTurn(mutatingRun, toThreadId: id, now: Date())
        reload()
        setSelectedThreadId(id)
    }
}
#endif
