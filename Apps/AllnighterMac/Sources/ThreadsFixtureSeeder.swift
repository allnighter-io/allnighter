import Foundation
import AllnighterCore
import AgentOSTeam
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
        case "thread-chat", "thread-copy-footer":
            seedFixtureChatExchange()
        case "thread-team-board":
            seedFixtureTeamBoard()
        case "thread-mutating-run":
            seedFixtureMutatingRun()
        case "thread-streaming":
            seedFixtureStreamingChat()
        case "thread-streaming-build":
            seedFixtureStreamingBuild()
        case "thread-thinking-history":
            seedFixtureThinkingHistory()
        case "thread-user-image-attachment":
            seedFixtureUserImageAttachment()
        case "thread-agent-image-reply":
            seedFixtureAgentImageReply()
        case "thread-worker-image-reply":
            seedFixtureWorkerImageReply()
        case "thread-design-board-fanout":
            seedFixtureDesignBoardFanout()
        case "home-thread-states":
            seedFixtureThreadStates()
            setSelectedThreadId(nil)
        case "home-rail":
            seedFixtureRail()
            setSelectedThreadId(nil)
        case "home-rail-th2":
            seedFixtureRailControls()
            setSelectedThreadId(nil)
        case "home-rail-unr":
            seedFixtureUnreadMatrix()
        case "home-rail-loops-attention":
            // ATL-S05: mixed rail — escalated (amber), running (no amber),
            // founder-stopped with unread (no amber), plus ordinary unread.
            seedFixtureLoopsAttentionRail()
            setSelectedThreadId(nil)
        case "projects-rail":
            seedFixtureProjectsRail()
            reload()
            setSelectedThreadId(nil)
        case "relay-launch", "relay-launch-kickoff":
            // R-S08: same project-grouped sidebar as "projects-rail" — the launch sheet
            // (opened by RootView via GUIFixture.opensRelayLaunch) renders on top of it.
            seedFixtureProjectsRail()
            reload()
            setSelectedThreadId(nil)
        case "thread-relay-escalated":
            seedFixtureRelayEscalated()
        case "relay-thread-status", "relay-thread-stop-confirm":
            seedFixtureRelayRunning()
        case "relay-thread-stopped":
            seedFixtureRelayFounderStopped()
        case "capacity-strip", "capacity-strip-refreshing":
            // CAP-S10: seed a few threads so the main pane is HomeNewRunPane
            // (capacity strip + composer), with no selection.
            seedFixtureThreads()
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

    /// The 4 row states side by side: Draft (quiet dotted, no bold/amber) · Running
    /// (blue) · Replied/unread (the only amber, bold). Pending's neutral dot needs an
    /// armed item bound to a thread (production path), so it isn't seeded here.
    private func seedFixtureThreadStates() {
        let base = Date()
        // Draft — created via "+", never sent. Nothing has happened: dotted ring only.
        _ = try? store.create(id: "st-draft", title: "Testing this out", now: base.addingTimeInterval(-30))
        // Running — a mutating run in flight (blue, the only motion).
        if (try? store.create(id: "st-running", title: "Rate-limit the public API", now: base.addingTimeInterval(-120))) != nil {
            let t = ThreadTurn(id: "st-running-t", threadId: "st-running", kind: .mutatingRun, status: .running,
                               createdAt: base, completedAt: nil, author: .worker)
            _ = try? store.appendTurn(t, toThreadId: "st-running", now: base)
        }
        // Replied — an unread worker reply (the only amber, bold title).
        if (try? store.create(id: "st-replied", title: "Unread worker reply", now: base.addingTimeInterval(-60))) != nil {
            let t = ThreadTurn(id: "st-replied-t", threadId: "st-replied", kind: .workerChat, status: .done,
                               createdAt: base, completedAt: base, author: .worker)
            _ = try? store.appendTurn(t, toThreadId: "st-replied", now: base)
        }
        reload()
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
                       createdAt: at, completedAt: at, author: .worker, text: "reply", modelId: "model_opus")
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
        let modelId = models.first?.id ?? "model_opus"

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
                author: .worker, text: text, modelId: modelId
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
        let modelId = models.first { $0.id == "model_opus" }?.id ?? models.first?.id ?? "model_opus"
        let user = ThreadTurn(
            id: "fixture-chat-user", threadId: id, kind: .userMessage, status: .done,
            createdAt: Date(), completedAt: Date(), author: .user,
            text: "For per-user API rate limiting — token bucket or sliding window? Short answer + why."
        )
        let reply = ThreadTurn(
            id: "fixture-chat-reply", threadId: id, kind: .workerChat, status: .done,
            createdAt: Date(), completedAt: Date(), author: .worker,
            text: "**Token bucket.** It allows short bursts (up to the bucket size) while holding the long-run average to the refill rate — which is what per-user API limits actually want. Sliding-window log is more precise but stores every timestamp per user (memory + GC churn); sliding-window counter approximates it but still smooths bursts away. For rate limiting, allow the burst: token bucket, refill = your sustained rate, capacity = your burst budget.",
            modelId: modelId
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
        let modelId = models.first { $0.id == "model_grok" }?.id ?? models.first?.id ?? "model_grok"
        let user = ThreadTurn(
            id: "fixture-streaming-user", threadId: id, kind: .userMessage, status: .done,
            createdAt: Date(), completedAt: Date(), author: .user,
            text: "Explain backpressure in streaming systems in two sentences.")
        let reply = ThreadTurn(
            id: "fixture-streaming-reply", threadId: id, kind: .workerChat, status: .running,
            createdAt: Date(), author: .worker,
            text: "Backpressure is how a fast producer is slowed to a rate its slower consumer can actually keep up with, so queues don't grow without bound. The consumer signals demand upstream — pull-based or via a bounded buffer that blocks the produc",
            modelId: modelId)
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
        let modelId = models.first { $0.id == "model_cursor_composer_25" }?.id ?? models.first?.id ?? "model_cursor_composer_25"
        let user = ThreadTurn(
            id: "fixture-streaming-build-user", threadId: id, kind: .userMessage, status: .done,
            createdAt: Date(), completedAt: Date(), author: .user,
            text: "Add a /health endpoint that returns 200 OK and run the tests.")
        var run = ThreadTurn(
            id: "fixture-streaming-build-turn", threadId: id, kind: .mutatingRun, status: .running,
            createdAt: Date(), author: .worker,
            text: "I'll add a `/health` route. Looking at the router setup in `app/server.swift`… adding a handler that returns `Response(status: .ok, body: \"OK\")`, wiring it into the route table, then I'll run `swift test` to confir",
            modelId: modelId, runId: "fixture-streaming-build-run")
        run.reasoningText = "The user wants a /health endpoint returning 200. Let me find the router — likely app/server.swift. I should match the existing handler style and add a test so I don't regress the suite. Checking how routes are registered first…"
        _ = try? store.appendTurn(user, toThreadId: id, now: Date())
        _ = try? store.appendTurn(run, toThreadId: id, now: Date())
        reload()
        setSelectedThreadId(id)
    }

    /// Two reasoning turns: a PRIOR completed turn (thinking collapsed to one line)
    /// and the LATEST running turn (thinking expanded + streaming). Proves the
    /// collapse-on-prior / expand-on-latest rule.
    private func seedFixtureThinkingHistory() {
        let id = "fixture-thinking-history"
        _ = try? store.create(id: id, title: "Rate limiting", now: Date())
        let modelId = models.first { $0.id == "model_grok" }?.id ?? models.first?.id ?? "model_grok"
        let now = Date()

        let q1 = ThreadTurn(id: "th-u1", threadId: id, kind: .userMessage, status: .done,
                            createdAt: now.addingTimeInterval(-60), completedAt: now.addingTimeInterval(-60),
                            author: .user, text: "Token bucket or sliding window?")
        var a1 = ThreadTurn(id: "th-a1", threadId: id, kind: .workerChat, status: .done,
                            createdAt: now.addingTimeInterval(-58), completedAt: now.addingTimeInterval(-55),
                            author: .worker,
                            text: "**Token bucket** — it allows short bursts while holding the long-run average to the refill rate.",
                            modelId: modelId)
        a1.reasoningText = "Per-user rate limiting. Trade-off is burst tolerance vs memory; sliding-window log stores every timestamp, token bucket is O(1) and allows bursts…"

        let q2 = ThreadTurn(id: "th-u2", threadId: id, kind: .userMessage, status: .done,
                            createdAt: now.addingTimeInterval(-8), completedAt: now.addingTimeInterval(-8),
                            author: .user, text: "What refill rate should I pick?")
        var a2 = ThreadTurn(id: "th-a2", threadId: id, kind: .workerChat, status: .running,
                            createdAt: now.addingTimeInterval(-6), author: .worker,
                            text: "Set the refill rate to your sustained per-user limit and the bucket capacity to the burst you're willing to al",
                            modelId: modelId)
        a2.reasoningText = "Refill rate = sustained rate. Capacity = burst budget. I'll give concrete numbers so they can map it to their SLOs…"

        for turn in [q1, a1, q2, a2] {
            _ = try? store.appendTurn(turn, toThreadId: id, now: turn.createdAt)
        }
        reload()
        setSelectedThreadId(id)
    }

    private func seedFixtureTeamBoard() {
        let id = "fixture-team"
        _ = try? store.create(id: id, title: "Rate-limit the public API", now: Date())

        let picks = models.filter { $0.enabled }.prefix(2)
        let m0 = picks.first?.id ?? "model_opus"
        let m1 = picks.dropFirst().first?.id ?? "model_grok"
        let w0 = Agent(id: Agent.makeID(modelId: m0, instanceIndex: 0), modelId: m0,
                        instanceIndex: 0, skillId: "answer", skillName: "Answer", purpose: .answer)
        let w1 = Agent(id: Agent.makeID(modelId: m1, instanceIndex: 0), modelId: m1,
                        instanceIndex: 0, skillId: "answer", skillName: "Answer", purpose: .answer)
        let writer = Agent(id: Agent.makeID(modelId: m0, instanceIndex: 1), modelId: m0,
                            instanceIndex: 1, skillId: "plan_writer", skillName: "Plan writer", purpose: .plan)

        var run = TeamRun(
            id: "fixture-team-run", prompt: "Per-user rate limiting for the public API — recommend an approach.",
            status: .complete, origin: .gui, presetId: "build_panel",
            workers: [w0, w1, writer],
            answers: [
                TeamAnswer(memberId: w0.id, modelId: m0, role: "answer",
                          result: WorkerRunResult(status: .done,
                             output: "**Token bucket.** Allows controlled bursts up to the bucket size while holding the long-run average to the refill rate — the right fit for per-user API limits.",
                             timing: RunTiming(durationMs: 4200))),
                TeamAnswer(memberId: w1.id, modelId: m1, role: "answer",
                          result: WorkerRunResult(status: .done,
                             output: "**Sliding-window counter.** Smoother than fixed windows and cheap to store (two counters per user); slightly approximates the boundary but avoids the double-burst edge of fixed windows.",
                             timing: RunTiming(durationMs: 5100))),
            ],
            createdAt: Date()
        )
        run.stages = [StageOutput(
            id: "fixture-team-plan", purpose: .plan, producedByAgentId: writer.id,
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
        let modelId = models.first { $0.id == "model_claude_code" }?.id
            ?? models.first { registry.manifest(for: $0)?.kind == .headlessCLI }?.id
            ?? models.first?.id ?? "model_claude_code"

        var run = TeamRun(id: "fixture-mutating-run-run", prompt: "Add retry to the upload client",
                          status: .complete, origin: .gui,
                          workers: [Agent(id: Agent.makeID(modelId: modelId, instanceIndex: 0),
                                           modelId: modelId, instanceIndex: 0,
                                           skillId: "first_principles_builder", purpose: .answer)],
                          answers: [
                              TeamAnswer(
                                  memberId: Agent.makeID(modelId: modelId, instanceIndex: 0),
                                  modelId: modelId, role: "answer",
                                  result: WorkerRunResult(status: .done,
                                     output: "Added exponential backoff (3 attempts, jitter) to `UploadClient.send`. Updated tests: `UploadClientTests.testRetriesOnTransient` passes. Ran `swift test` — 42 passing.")
                              )
                          ],
                          createdAt: Date(),
                          mutating: true)
        run.stages = [StageOutput(
            id: "fixture-mutating-run-stage", purpose: .plan, producedByAgentId: modelId,
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
            modelId: modelId, runId: run.id, stageId: "fixture-mutating-run-stage"
        )
        _ = try? store.appendTurn(user, toThreadId: id, now: Date())
        _ = try? store.appendTurn(mutatingRun, toThreadId: id, now: Date())
        reload()
        setSelectedThreadId(id)
    }

    /// ATL-S05 proof: one project rail with the three relay lifecycle states side by
    /// side plus ordinary unread. Exactly 4 rows so the rail's default "show 4"
    /// does not hide the founder-stopped case under "N more". Must actually paint:
    /// - escalated → amber (needs you)
    /// - running → blue / no amber
    /// - founder-stopped WITH unread turns → no amber (the actual bug)
    /// - ordinary unread → amber (regression guard)
    private func seedFixtureLoopsAttentionRail() {
        let base = Date()
        let projectId = "prj_halo"
        let (pmModelId, devModelId) = relayFixtureSeatIds()

        func bind(_ id: String) {
            _ = try? store.bindProject(threadId: id, projectId: projectId)
        }

        // 1) Escalated — waiting on the human (the only amber relay). Newest.
        do {
            let id = "fixture-loop-escalated"
            let state = RelayState(
                id: id,
                projectRoot: "/Users/you/code/allnighter",
                docPath: "docs/phases/SPEC.md",
                pmModelId: pmModelId,
                devModelId: devModelId,
                status: .escalated,
                rounds: [
                    RelayRound(
                        roundNumber: 1, baselineHead: "aaa", headAfterDev: "bbb",
                        startedAt: base.addingTimeInterval(-400),
                        finishedAt: base.addingTimeInterval(-300),
                        outcome: .escalated
                    )
                ],
                createdAt: base.addingTimeInterval(-500),
                note: "Should seat labels show the driver name too?"
            )
            saveRelayFixtureState(state)
            guard (try? store.create(
                id: id, title: "PM Relay: SPEC", now: base.addingTimeInterval(-500),
                workingDir: state.projectRoot
            )) != nil else { return }
            bind(id)
            appendRelayFixtureTurns(
                id: id, pmModelId: pmModelId, devModelId: devModelId, base: base.addingTimeInterval(-500),
                pmText: "Reviewed — need a founder call on seat labels.",
                devText: "Shipped status chrome."
            )
            let escalation = ThreadTurn(
                id: "\(id)_escalate1", threadId: id, kind: .systemEvent, status: .running,
                createdAt: base.addingTimeInterval(-280), author: .system,
                text: state.note, systemEvent: .relayEscalated
            )
            // Final mutation sets updatedAt — control rail sort order here.
            _ = try? store.appendTurn(escalation, toThreadId: id, now: base.addingTimeInterval(-1))
        }

        // 2) Running — live loop, no attention colour.
        do {
            let id = "fixture-loop-running"
            let state = RelayState(
                id: id,
                projectRoot: "/Users/you/code/allnighter",
                docPath: "docs/phases/Agent_Team_Loop.md",
                pmModelId: pmModelId,
                devModelId: devModelId,
                status: .running,
                rounds: [
                    RelayRound(
                        roundNumber: 1, baselineHead: "ccc", headAfterDev: "ddd",
                        startedAt: base.addingTimeInterval(-200),
                        finishedAt: base.addingTimeInterval(-100),
                        outcome: .continued
                    )
                ],
                createdAt: base.addingTimeInterval(-250),
                note: "Round 1 complete — PM reviewing."
            )
            saveRelayFixtureState(state)
            guard (try? store.create(
                id: id, title: "PM Relay: Agent Team Loop", now: base.addingTimeInterval(-250),
                workingDir: state.projectRoot
            )) != nil else { return }
            bind(id)
            appendRelayFixtureTurns(
                id: id, pmModelId: pmModelId, devModelId: devModelId, base: base.addingTimeInterval(-250),
                pmText: "Continue with stop affordance wiring.",
                devText: "Implementing now."
            )
            let live = ThreadTurn(
                id: "\(id)_dev2", threadId: id, kind: .workerChat, status: .running,
                createdAt: base.addingTimeInterval(-40), author: .worker,
                text: "Working…", modelId: devModelId
            )
            _ = try? store.appendTurn(live, toThreadId: id, now: base.addingTimeInterval(-2))
        }

        // 3) Founder-stopped WITH unread turns — must NOT be amber (the bug).
        do {
            let id = "fixture-loop-stopped"
            let finished = base.addingTimeInterval(-60)
            let state = RelayState(
                id: id,
                projectRoot: "/Users/you/code/allnighter",
                docPath: "docs/phases/SPEC.md",
                pmModelId: pmModelId,
                devModelId: devModelId,
                status: .stopped,
                rounds: [
                    RelayRound(
                        roundNumber: 1, baselineHead: "eee", headAfterDev: "fff",
                        startedAt: base.addingTimeInterval(-900),
                        finishedAt: base.addingTimeInterval(-800),
                        outcome: .continued
                    )
                ],
                createdAt: base.addingTimeInterval(-1000),
                finishedAt: finished,
                note: "Founder stopped the loop.",
                stoppedReason: RelayState.founderStoppedReason
            )
            saveRelayFixtureState(state)
            guard (try? store.create(
                id: id, title: "PM Relay: SPEC (stopped)", now: base.addingTimeInterval(-1000),
                workingDir: state.projectRoot
            )) != nil else { return }
            bind(id)
            appendRelayFixtureTurns(
                id: id, pmModelId: pmModelId, devModelId: devModelId, base: base.addingTimeInterval(-1000),
                pmText: "Should we keep the copy-status affordance?",
                devText: "Shipped status panel fields."
            )
            // Unread worker reply — hasUnread true, but railAttention stays `.none`.
            let unread = ThreadTurn(
                id: "\(id)_unread", threadId: id, kind: .workerChat, status: .done,
                createdAt: finished, completedAt: finished, author: .worker,
                text: "Final note you have not opened.", modelId: pmModelId
            )
            _ = try? store.appendTurn(unread, toThreadId: id, now: base.addingTimeInterval(-3))
            let stopped = ThreadTurn(
                id: "\(id)_stopped", threadId: id, kind: .systemEvent, status: .done,
                createdAt: finished, completedAt: finished, author: .system,
                text: RelayState.founderStoppedReason, systemEvent: .relayStopped
            )
            _ = try? store.appendTurn(stopped, toThreadId: id, now: base.addingTimeInterval(-3))
        }

        // 4) Ordinary unread — still amber (regression guard).
        if (try? store.create(
            id: "fixture-loop-ordinary-unread", title: "Unread worker reply",
            now: base.addingTimeInterval(-120)
        )) != nil {
            bind("fixture-loop-ordinary-unread")
            let t = ThreadTurn(
                id: "fixture-loop-ordinary-unread-w", threadId: "fixture-loop-ordinary-unread",
                kind: .workerChat, status: .done,
                createdAt: base.addingTimeInterval(-100), completedAt: base.addingTimeInterval(-100),
                author: .worker, text: "Ordinary unread still gets amber.", modelId: pmModelId
            )
            _ = try? store.appendTurn(t, toThreadId: "fixture-loop-ordinary-unread", now: base.addingTimeInterval(-4))
        }

        reload()
    }

    /// R-S08 proof: a PM Relay thread (id == relayId, `RelayThreadProjector`'s identity
    /// rule) two rounds in, with round 2's PM turn escalated and still OPEN — the one
    /// actionable system-event row (`RelayEscalationRow` in ThreadView.swift). Built
    /// directly from `ThreadTurn`s in the SAME shape `RelayThreadProjector.sync` produces
    /// (`.workerChat` PM/dev turns, an open `.systemEvent`/`.relayEscalated` turn) — no
    /// `RelayCoordinator`/`RelayState` involved, this is pure UI-fixture data.
    private func seedFixtureRelayEscalated() {
        let id = "fixture-relay-escalated"
        let pmModelId = models.first { $0.id == "model_claude_code" }?.id
            ?? models.first { registry.manifest(for: $0)?.kind == .headlessCLI }?.id
            ?? models.first?.id ?? "model_claude_code"
        let devModelId = models.first { $0.id == "model_codex" }?.id
            ?? models.first { registry.manifest(for: $0)?.kind == .headlessCLI && $0.id != pmModelId }?.id
            ?? pmModelId
        let base = Date().addingTimeInterval(-600)

        guard (try? store.create(
            id: id, title: "PM Relay: Spec Review", now: base, workingDir: "/Users/you/code/allnighter"
        )) != nil else { return }

        func turn(_ suffix: String, modelId: String, text: String, at offset: TimeInterval) -> ThreadTurn {
            ThreadTurn(
                id: "\(id)_\(suffix)", threadId: id, kind: .workerChat, status: .done,
                createdAt: base.addingTimeInterval(offset), completedAt: base.addingTimeInterval(offset + 20),
                author: .worker, text: text, modelId: modelId
            )
        }
        _ = try? store.appendTurn(turn(
            "pm1", modelId: pmModelId,
            text: "Reviewed baseline..HEAD — nothing to fix yet. Handover: implement §6 R-S08 per the slice table.",
            at: 0
        ), toThreadId: id, now: base)
        _ = try? store.appendTurn(turn(
            "dev1", modelId: devModelId,
            text: "Built the launch surface + escalation row. Committed 3f2a91c. Tests green (152/152).",
            at: 40
        ), toThreadId: id, now: base)
        // Round 2's PM turn escalated — an OPEN system event, the one actionable row.
        let escalation = ThreadTurn(
            id: "\(id)_escalate2", threadId: id, kind: .systemEvent, status: .running,
            createdAt: base.addingTimeInterval(90), author: .system,
            text: "Two seat pickers both resolve to \"Model\" in the composer — should the relay's PM/dev seat labels say the driver name too, or is the model name enough?",
            systemEvent: .relayEscalated
        )
        _ = try? store.appendTurn(escalation, toThreadId: id, now: base)
        reload()
        setSelectedThreadId(id)
    }

    /// ATL-S04: running relay thread with store-backed status chrome (Status pill + Stop).
    private func seedFixtureRelayRunning() {
        let id = "fixture-relay-running"
        let (pmModelId, devModelId) = relayFixtureSeatIds()
        let base = Date().addingTimeInterval(-600)
        let round = RelayRound(
            roundNumber: 1,
            baselineHead: "abc123",
            headAfterDev: "def456",
            startedAt: base.addingTimeInterval(30),
            finishedAt: base.addingTimeInterval(120),
            outcome: .continued
        )
        let state = RelayState(
            id: id,
            projectRoot: "/Users/you/code/allnighter",
            docPath: "docs/phases/Agent_Team_Loop.md",
            pmModelId: pmModelId,
            devModelId: devModelId,
            status: .running,
            rounds: [round],
            createdAt: base,
            note: "Round 1 complete — PM reviewing dev report."
        )
        saveRelayFixtureState(state)

        guard (try? store.create(
            id: id, title: "PM Relay: Agent Team Loop", now: base, workingDir: state.projectRoot
        )) != nil else { return }
        appendRelayFixtureTurns(
            id: id, pmModelId: pmModelId, devModelId: devModelId, base: base,
            pmText: "Reviewed round 1 — continue with Stop affordance wiring.",
            devText: "Implemented relay status chrome. Tests green."
        )
        reload()
        setSelectedThreadId(id)
    }

    /// ATL-S04: founder-stopped relay — open escalation turn exists but Answer & resume
    /// is gated off by `RelayState.isResumable` (inference ban negative test).
    private func seedFixtureRelayFounderStopped() {
        let id = "fixture-relay-stopped"
        let (pmModelId, devModelId) = relayFixtureSeatIds()
        let base = Date().addingTimeInterval(-900)
        let finished = Date().addingTimeInterval(-60)
        let round = RelayRound(
            roundNumber: 1,
            baselineHead: "abc123",
            headAfterDev: "def456",
            startedAt: base.addingTimeInterval(30),
            finishedAt: base.addingTimeInterval(120),
            outcome: .continued
        )
        let state = RelayState(
            id: id,
            projectRoot: "/Users/you/code/allnighter",
            docPath: "docs/phases/Agent_Team_Loop.md",
            pmModelId: pmModelId,
            devModelId: devModelId,
            status: .stopped,
            rounds: [round],
            createdAt: base,
            finishedAt: finished,
            note: "Founder stopped the loop.",
            stoppedReason: RelayState.founderStoppedReason
        )
        saveRelayFixtureState(state)
        let pmTurn = PMTurnJSON(
            kind: .relay,
            subjectId: id,
            sequence: 1,
            round: 1,
            createdAt: finished,
            reason: "stopped",
            lifecycleStatus: "stopped",
            report: "Loop abandoned after round 1.",
            nextCommands: [RelayStatusLoader.statusCommand(relayId: id)]
        )
        try? PMTurnStore().save(pmTurn)

        guard (try? store.create(
            id: id, title: "PM Relay: Agent Team Loop (stopped)", now: base, workingDir: state.projectRoot
        )) != nil else { return }
        appendRelayFixtureTurns(
            id: id, pmModelId: pmModelId, devModelId: devModelId, base: base,
            pmText: "Should we add a copy-status affordance?",
            devText: "Shipped status panel fields."
        )
        let escalation = ThreadTurn(
            id: "\(id)_escalate", threadId: id, kind: .systemEvent, status: .running,
            createdAt: base.addingTimeInterval(200), author: .system,
            text: "Should we add a copy-status affordance?",
            systemEvent: .relayEscalated
        )
        _ = try? store.appendTurn(escalation, toThreadId: id, now: base)
        reload()
        setSelectedThreadId(id)
    }

    private func relayFixtureSeatIds() -> (pm: String, dev: String) {
        let pmModelId = models.first { $0.id == "model_claude_code" }?.id
            ?? models.first { registry.manifest(for: $0)?.kind == .headlessCLI }?.id
            ?? models.first?.id ?? "model_claude_code"
        let devModelId = models.first { $0.id == "model_codex" }?.id
            ?? models.first { registry.manifest(for: $0)?.kind == .headlessCLI && $0.id != pmModelId }?.id
            ?? pmModelId
        return (pmModelId, devModelId)
    }

    private func saveRelayFixtureState(_ state: RelayState) {
        try? RelayStateStore().save(state)
    }

    private func appendRelayFixtureTurns(
        id: String, pmModelId: String, devModelId: String, base: Date,
        pmText: String, devText: String
    ) {
        func turn(_ suffix: String, modelId: String, text: String, at offset: TimeInterval) -> ThreadTurn {
            ThreadTurn(
                id: "\(id)_\(suffix)", threadId: id, kind: .workerChat, status: .done,
                createdAt: base.addingTimeInterval(offset), completedAt: base.addingTimeInterval(offset + 20),
                author: .worker, text: text, modelId: modelId
            )
        }
        _ = try? store.appendTurn(turn("pm1", modelId: pmModelId, text: pmText, at: 0), toThreadId: id, now: base)
        _ = try? store.appendTurn(turn("dev1", modelId: devModelId, text: devText, at: 40), toThreadId: id, now: base)
    }

    private func seedFixtureUserImageAttachment() {
        let id = "fixture-user-image"
        _ = try? store.create(id: id, title: "Screenshot for profile refresh", now: Date())
        do {
            let ref = try commitFixtureAttachment(
                threadId: id, attachmentId: "fixture-user-img", sequence: 0, sourceKind: .paste
            )
            let turn = ThreadTurn(
                id: "fixture-user-image-turn", threadId: id, kind: .userMessage, status: .done,
                createdAt: Date(), completedAt: Date(), author: .user,
                text: "Make this profile feel premium and clean.",
                attachmentRefs: [ref]
            )
            _ = try? store.appendTurn(turn, toThreadId: id, now: Date())
        } catch {}
        reload()
        setSelectedThreadId(id)
    }

    /// The founder's reported case: a single agent run ("Agent (Grok Build)" → a
    /// `mutatingRun` turn) that produced an image. The image was captured into thread
    /// attachments at settlement, so the agent reply shows a preview chip — not just a path.
    private func seedFixtureAgentImageReply() {
        let id = "fixture-agent-image"
        let modelId = models.first { $0.id == "model_grok" }?.id ?? models.first?.id ?? "model_grok"
        _ = try? store.create(id: id, title: "Generate an image of a super cute adorable cat", now: Date())
        let user = ThreadTurn(
            id: "fixture-agent-image-user", threadId: id, kind: .userMessage, status: .done,
            createdAt: Date(), completedAt: Date(), author: .user,
            text: "Generate an image of me of a super cute adorable cat."
        )
        _ = try? store.appendTurn(user, toThreadId: id, now: Date())
        do {
            let ref = try commitFixtureAttachment(
                threadId: id, attachmentId: "fixture-agent-img", sequence: 0,
                sourceKind: .workerGenerated
            )
            let reply = ThreadTurn(
                id: "fixture-agent-image-reply", threadId: id, kind: .mutatingRun, status: .done,
                createdAt: Date(), completedAt: Date(), author: .worker,
                text: "Done! I've generated a super cute adorable cat for you.",
                modelId: modelId,
                attachmentRefs: [ref]
            )
            _ = try? store.appendTurn(reply, toThreadId: id, now: Date())
        } catch {}
        reload()
        setSelectedThreadId(id)
    }

    private func seedFixtureWorkerImageReply() {
        let id = "fixture-worker-image"
        let modelId = models.first { $0.id == "model_grok" }?.id ?? models.first?.id ?? "model_grok"
        _ = try? store.create(id: id, title: "Draw a cute cat", now: Date())
        let user = ThreadTurn(
            id: "fixture-worker-image-user", threadId: id, kind: .userMessage, status: .done,
            createdAt: Date(), completedAt: Date(), author: .user,
            text: "Draw a cute cat."
        )
        _ = try? store.appendTurn(user, toThreadId: id, now: Date())
        do {
            let ref = try commitFixtureAttachment(
                threadId: id, attachmentId: "fixture-worker-img", sequence: 0,
                sourceKind: .workerGenerated
            )
            let reply = ThreadTurn(
                id: "fixture-worker-image-reply", threadId: id, kind: .workerChat, status: .done,
                createdAt: Date(), completedAt: Date(), author: .worker,
                text: "Here's the photorealistic cat you asked for.",
                modelId: modelId,
                attachmentRefs: [ref]
            )
            _ = try? store.appendTurn(reply, toThreadId: id, now: Date())
        } catch {}
        reload()
        setSelectedThreadId(id)
    }

    private func seedFixtureDesignBoardFanout() {
        let id = "fixture-design-board"
        _ = try? store.create(id: id, title: "Profile screen options", now: Date())
        let m0 = models.first?.id ?? "model_grok"
        let m1 = models.dropFirst().first?.id ?? "model_gemini"
        let w0 = Agent(id: Agent.makeID(modelId: m0, instanceIndex: 0), modelId: m0,
                        instanceIndex: 0, skillId: "bold", skillName: "Bold", purpose: .answer)
        let w1 = Agent(id: Agent.makeID(modelId: m1, instanceIndex: 0), modelId: m1,
                        instanceIndex: 0, skillId: "minimal", skillName: "Minimal", purpose: .answer)
        let runId = "fixture-design-run"
        do {
            let runDir = try runStore.runDirectory(forRunId: runId)
            let path0 = "option_\(w0.id).png"
            let path1 = "option_\(w1.id).png"
            try FixturePNG.write(to: runDir.appendingPathComponent(path0), hue: 0.08)
            try FixturePNG.write(to: runDir.appendingPathComponent(path1), hue: 0.55)

            var run = TeamRun(
                id: runId, prompt: "Make this profile feel premium and clean.",
                status: .complete, origin: .gui, presetId: "design_design",
                workers: [w0, w1],
                answers: [
                    TeamAnswer(memberId: w0.id, modelId: m0, role: "answer",
                              result: WorkerRunResult(status: .done, output: path0, timing: RunTiming(durationMs: 8000))),
                    TeamAnswer(memberId: w1.id, modelId: m1, role: "answer",
                              result: WorkerRunResult(status: .done, output: path1, timing: RunTiming(durationMs: 9000))),
                ],
                createdAt: Date(),
                lane: .design,
                outputKind: .designBoard
            )
            run.stages = [
                StageOutput(
                    id: "fixture-design-board-stage", purpose: .board, status: .done,
                    payload: .board(BoardPayload(
                        targetShape: .mobile,
                        options: [
                            DesignOption(agentId: w0.id, modelId: m0, persona: "bold", imagePath: path0, status: .done),
                            DesignOption(agentId: w1.id, modelId: m1, persona: "minimal", imagePath: path1, status: .done),
                            DesignOption(agentId: "failed-seat", modelId: m1, persona: "editorial",
                                         status: .failed, failureReason: "Image gen timed out"),
                        ],
                        chosen: ChosenOption(agentId: w1.id, persona: "minimal")
                    )),
                    startedAt: Date(), finishedAt: Date()
                )
            ]
            _ = try? runStore.save(run, models: models)

            let user = ThreadTurn(
                id: "fixture-design-user", threadId: id, kind: .userMessage, status: .done,
                createdAt: Date(), completedAt: Date(), author: .user,
                text: "Make this profile feel premium and clean."
            )
            let board = ThreadTurn(
                id: "fixture-design-board-turn", threadId: id, kind: .designBoard, status: .done,
                createdAt: Date(), completedAt: Date(), author: .worker, runId: runId
            )
            _ = try? store.appendTurn(user, toThreadId: id, now: Date())
            _ = try? store.appendTurn(board, toThreadId: id, now: Date())
        } catch {}
        reload()
        setSelectedThreadId(id)
    }

    private func commitFixtureAttachment(
        threadId: String,
        attachmentId: String,
        sequence: Int,
        sourceKind: AttachmentSourceKind
    ) throws -> TurnAttachmentRef {
        let dir = try store.threadDirectory(forThreadId: threadId)
        let attachmentStore = ThreadAttachmentStore(threadDirectory: dir)
        let png = try FixturePNG.data(hue: sourceKind == .workerGenerated ? 0.62 : 0.12)
        let ingested = try AttachmentIngestor().ingest(
            data: png, declaredMIME: "image/png", sourceKind: sourceKind
        )
        let (_, ref) = try attachmentStore.commitIngested(
            ingested: ingested,
            attachmentId: attachmentId,
            threadId: threadId,
            sourceKind: sourceKind,
            sequence: sequence,
            originalName: nil,
            now: Date()
        )
        return ref
    }
}

private enum FixturePNG {
    static let base64 =
        "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg=="

    static func data(hue: CGFloat = 0) throws -> Data {
        _ = hue
        guard let data = Data(base64Encoded: base64) else {
            throw AttachmentError.decodeFailed
        }
        return data
    }

    static func write(to url: URL, hue: CGFloat = 0) throws {
        try data(hue: hue).write(to: url)
    }
}
#endif
