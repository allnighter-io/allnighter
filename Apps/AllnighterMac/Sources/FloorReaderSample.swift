#if DEBUG
import Foundation
import AllnighterCore

/// A designer-mock TeamRun for the Factory Floor reader GUI proof (DEBUG only —
/// never real data). Mirrors the handoff's CAST: a Lead synthesis + workers, each
/// with rich markdown so the renderer is exercised (headings, lists, bold, quote).
enum FloorReaderSample {
    static let run: TeamRun = {
        let now = Date(timeIntervalSince1970: 1_750_000_000)
        let workers = [
            Worker(id: "model_opus#0", modelId: "model_opus", instanceIndex: 0, skillId: "insight_writer", skillName: "Lead", purpose: .plan),
            Worker(id: "model_grok#0", modelId: "model_grok", instanceIndex: 0, skillId: "signal_source_reader", skillName: "Signal Scout", purpose: .answer),
            Worker(id: "model_gemini#0", modelId: "model_gemini", instanceIndex: 0, skillId: "signal_landscape_scanner", skillName: "Market Analyst", purpose: .answer),
            Worker(id: "model_chatgpt#0", modelId: "model_chatgpt", instanceIndex: 0, skillId: "signal_product_ideas", skillName: "Build Strategist", purpose: .answer),
            Worker(id: "model_sonnet#0", modelId: "model_sonnet", instanceIndex: 0, skillId: "signal_product_ideas", skillName: "Copy Strategist", purpose: .answer),
            Worker(id: "model_grok#1", modelId: "model_grok", instanceIndex: 1, skillId: "signal_skeptic", skillName: "Skeptic", purpose: .review),
        ]
        let answers = [
            WorkerAnswer(workerId: "model_opus#0", modelId: "model_opus", status: .done, output: "", finishedAt: now),
            WorkerAnswer(workerId: "model_grok#0", modelId: "model_grok", status: .done, output: scout, finishedAt: now),
            WorkerAnswer(workerId: "model_gemini#0", modelId: "model_gemini", status: .done, output: market, finishedAt: now),
            WorkerAnswer(workerId: "model_chatgpt#0", modelId: "model_chatgpt", status: .done, output: build, finishedAt: now),
            WorkerAnswer(workerId: "model_sonnet#0", modelId: "model_sonnet", status: .done, output: copy, finishedAt: now),
            WorkerAnswer(workerId: "model_grok#1", modelId: "model_grok", status: .done, output: skeptic, finishedAt: now),
        ]
        let plan = StageOutput(id: "stage_plan", purpose: .plan, status: .done, payload: .plan(markdown: lead))
        return TeamRun(
            id: "floor_sample", prompt: "Developers keep saying agents lose the thread after a break. How does this apply to Allnighter?",
            status: .complete, origin: .gui, presetId: "signal_post_to_project",
            workers: workers, workerAnswers: answers, stages: [plan], createdAt: now,
            lane: .signal, teamDisplayName: "Post-to-Project Signal", outputKind: .insight)
    }()

    static let lead = """
    ## The move: claim "I became the project manager" this week

    Six of us looked at this from different angles. We converge on one thing — the market is describing your exact thesis in its own words, and **nobody owns the framing yet**.

    ### What each of us found
    - **Scout:** the pain is live and accelerating — 12 posts in 48h, not saturated.
    - **Market:** IDEs won't chase it; it lives above the repo.
    - **Build:** there is a one-day proof — a Return Review demo.
    - **Copy:** the line writes itself — *"The agent did the work. I became the project manager."*
    - **Skeptic:** not late, but the window is days, not weeks.

    ### The move
    Draft the founder thread today, built on the "I became the PM" line. Hold the Return Review demo as the proof to ship next.

    > Confidence: high on timing, medium on durability. If you don't move this week, re-check saturation before posting.
    """

    static let scout = """
    ## 12 public posts, 48 hours, still climbing

    The complaint cluster is **"lost context / babysitting / what changed?"** — developers describing agents that do the work but forget the thread.

    ### Signal
    - 12 sourced posts in 48h
    - 3 threads with real engagement (one at ~40k views)
    - Volume is **rising**, not plateaued

    Not saturated. No single account owns the framing yet.
    """

    static let market = """
    ## This lives above the repo — open whitespace

    - **IDEs (Cursor, Copilot):** own *inside* the file; won't chase coordination.
    - **Agent frameworks:** technical, not founder-facing.
    - **PM tools:** own human-to-human, not human-to-agent.

    The coordination layer *between you and your agents* is unowned.
    """

    static let build = "## One-day proof exists\n\nA **Return Review demo** shows the agent's work coming back for verification — buildable in a day, and it *is* the \"I became the PM\" story made concrete."
    static let copy = "## The line writes itself\n\n> The agent did the work. **I became the project manager.**\n\nNine words. Put it at the top of the thread."
    static let skeptic = "## Move now, eyes open\n\nNot late — but the window is **days, not weeks**. Re-check saturation before posting if you slip past this week."
}
#endif
