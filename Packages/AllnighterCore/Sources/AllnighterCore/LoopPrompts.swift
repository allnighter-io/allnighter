import Foundation

/// PM-turn prompt (docs/phases/PM_Relay.md §2, §4). Round 1 has no dev report; round N
/// carries the previous dev turn's report verbatim plus the exact commit range to review.
/// The prompt teaches loop mechanics only — batching, gating, and review depth are the
/// PM's judgment call (§3), never prescribed here.
public enum RelayPMPrompt {
    public struct Context: Sendable, Equatable {
        /// Repo-relative path to the spec doc — the PM re-reads it fresh from disk.
        /// `nil` for a brief-only loop (LVC-S02b) — `brief` is the anchor instead.
        public var docPath: String?
        /// The founder's kickoff sentence, verbatim — rendered as the work's anchor on
        /// EVERY round when `docPath` is `nil` (unlike `kickoffMessage` below, which is
        /// consume-once and only ever appears on round 1).
        public var brief: String
        public var roundNumber: Int
        /// git HEAD when this round began (read-only, via `GitObserver`).
        public var baselineHead: String
        /// git HEAD after the dev's turn. Nil on round 1 — there is no dev turn yet.
        public var currentHead: String?
        /// The previous dev turn's report, verbatim. Nil on round 1.
        public var devReport: String?
        /// Injected on `--resume` after an escalation — the founder's answer.
        public var founderNote: String?
        /// Injected exactly once, on the FIRST spawned PM turn after `LoopCoordinator.
        /// adopt` (`docs/phases/Pilot_Relay.md` §5, PL-S06 "adopt (unattended handover)"):
        /// tells the incoming spawned PM that earlier rounds on this SAME relay ran in
        /// Pilot mode (a live session held the seat directly, no `pmRunId`), so it reads
        /// the round log as its own relay's history rather than a stranger's. `nil` on
        /// every other round, including later rounds of the same adopted relay.
        public var adoptionNote: String?
        /// ATL-S01: founder kickoff brief for the first PM turn only — verbatim,
        /// never paraphrased. Cleared on the coordinator after first assemble.
        public var kickoffMessage: String?
        public var maxRounds: Int
        public var roundsRemaining: Int

        public init(
            docPath: String?,
            brief: String = "",
            roundNumber: Int,
            baselineHead: String,
            currentHead: String? = nil,
            devReport: String? = nil,
            founderNote: String? = nil,
            adoptionNote: String? = nil,
            kickoffMessage: String? = nil,
            maxRounds: Int,
            roundsRemaining: Int
        ) {
            self.docPath = docPath
            self.brief = brief
            self.roundNumber = roundNumber
            self.baselineHead = baselineHead
            self.currentHead = currentHead
            self.devReport = devReport
            self.founderNote = founderNote
            self.adoptionNote = adoptionNote
            self.kickoffMessage = kickoffMessage
            self.maxRounds = maxRounds
            self.roundsRemaining = roundsRemaining
        }
    }

    public static func assemble(context: Context) -> String {
        var parts = [
            "# Loop — round \(context.roundNumber) (PM seat)",
            anchorParagraph(context: context),
            memoryPointerLine(),
            "You have \(context.roundsRemaining) of \(context.maxRounds) rounds left before this relay stops itself. Plan the remaining work with that ceiling in mind — escalate rather than let it run out silently.",
        ]

        // ATL-S01: after rounds-remaining, before founderNote / dev-report blocks.
        // Emptiness uses trim; the body is the stored string verbatim (never paraphrased).
        if let kickoffMessage = context.kickoffMessage,
           !kickoffMessage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            parts.append("## Kickoff brief (founder)\n\(kickoffMessage)")
        }

        if let founderNote = context.founderNote, !founderNote.isEmpty {
            parts.append("## Founder note (injected on resume)\n\(founderNote)")
        }

        if let adoptionNote = context.adoptionNote, !adoptionNote.isEmpty {
            parts.append("## Adopted from Pilot (unattended handover)\n\(adoptionNote)")
        }

        if let devReport = context.devReport {
            let headForRange = context.currentHead ?? "HEAD"
            parts.append(
                """
                ## The dev's round \(max(context.roundNumber - 1, 1)) report
                What follows, between the markers, is the dev's report — verbatim, unedited.
                \(devReportBlock(devReport, round: max(context.roundNumber - 1, 1)))
                """
            )
            parts.append(
                """
                ## Review the actual work, not just the report
                - Diff the real commits yourself: `git log \(context.baselineHead)..\(headForRange)` \
                and `git diff \(context.baselineHead)..\(headForRange)`. The report's prose is a \
                claim, not proof — check it against what actually landed.
                - Read any artifacts the report names (screenshots, logs, output files) at the \
                paths it gives.
                - Weigh the report's claims against what you find. Approve what holds, flag what \
                doesn't, and fix small things yourself if that's faster than bouncing them back — \
                both are fine.
                """
            )
            parts.append(
                """
                ## Decide
                Either write the next handover, declare the relay done (only if the doc's own \
                acceptance criteria are actually met), or escalate with one specific question the \
                founder must answer.
                """
            )
        } else {
            parts.append(
                """
                ## Round 1 — no dev report yet
                Review the doc and the current state of the repo yourself. Decide the first unit \
                of work and write the first handover for the dev.
                """
            )
        }

        parts.append(
            """
            ## This loop carries transport only
            Batching, gating, how deep to review, and whether to fix something yourself versus \
            send it back — all of that is your judgment call, made fresh each round. Nothing here \
            prescribes a process; different rounds can call for different depths.
            """
        )

        parts.append(
            """
            ## Honesty
            Never claim work you haven't verified. Never fake-green a check. Declare done only \
            when the doc's own acceptance criteria are actually met — not when it feels close.
            """
        )

        parts.append(verdictContractBlock())

        return parts.joined(separator: "\n\n")
    }

    /// LVC-S02b: the doc lives at `docPath` when there is one; a brief-only loop
    /// (`docPath` nil) has no doc to reread, so this anchors every round on the
    /// founder's brief instead — never a fabricated path.
    private static func anchorParagraph(context: Context) -> String {
        if let docPath = context.docPath {
            return """
            You are the project manager driving delivery of the spec doc for this repo. \
            The doc lives at `\(docPath)` — read it fresh from disk right now, plus \
            anything it links to. Do not rely on any memory of it from an earlier round; the \
            doc or the repo may have moved. You run at the repo root with full read access.
            """
        }
        return """
        You are the project manager driving delivery for this repo. There is no spec doc for \
        this loop — the work is defined by the founder's brief: "\(context.brief)". Judge \
        progress against that brief and the actual repo state each round; there is nothing \
        else to reread. You run at the repo root with full read access.
        """
    }
}

/// Dev-turn prompt (docs/phases/PM_Relay.md §2, §4.1). Deliberately thin: a short standing
/// preamble wrapped around the PM's handover, passed through untouched — the dev sees
/// exactly what the founder would have pasted. No verdict contract; the dev's report is
/// free prose.
public enum LoopDevPrompt {
    public struct Context: Sendable, Equatable {
        /// The PM's handover text, verbatim — never paraphrased or decorated.
        public var handover: String
        /// `nil` for a brief-only loop (LVC-S02b) — `brief` is the anchor instead.
        public var docPath: String?
        /// The founder's kickoff sentence, verbatim — rendered when `docPath` is `nil`.
        public var brief: String
        public var roundNumber: Int
        /// Agent display name for the provenance trailer (FR4).
        public var workerDisplayName: String

        public init(
            handover: String, docPath: String?, brief: String = "", roundNumber: Int,
            workerDisplayName: String
        ) {
            self.handover = handover
            self.docPath = docPath
            self.brief = brief
            self.roundNumber = roundNumber
            self.workerDisplayName = workerDisplayName
        }
    }

    public static func assemble(context: Context) -> String {
        let parts = [
            "# Loop — round \(context.roundNumber) (dev seat)",
            anchorParagraph(context: context),
            memoryPointerLine(),
            ProvenanceConvention.commitTrailerAsk(displayName: context.workerDisplayName),
            """
            ## The PM's order
            What follows, between the markers, is the PM's handover — verbatim, unedited.
            \(handoverBlock(context.handover))
            """,
        ]
        return parts.joined(separator: "\n\n")
    }

    /// Mirrors `RelayPMPrompt.anchorParagraph` — see its comment.
    private static func anchorParagraph(context: Context) -> String {
        if let docPath = context.docPath {
            return """
            You are the developer on this repo. The spec doc is `\(docPath)`; the PM \
            reviewed it and the repo state and wrote the order below. Do the work the order \
            describes. Commit through your own tooling as the order implies — this loop does no \
            git of its own. When you're done, end your reply with a delivery report: what you \
            did, what you committed, what you verified, and what remains. Be honest — no \
            fake-green.
            """
        }
        return """
        You are the developer on this repo. There is no spec doc for this loop — the founder's \
        brief was: "\(context.brief)". The PM reviewed the repo state and wrote the order below. \
        Do the work the order describes. Commit through your own tooling as the order implies — \
        this loop does no git of its own. When you're done, end your reply with a delivery \
        report: what you did, what you committed, what you verified, and what remains. Be \
        honest — no fake-green.
        """
    }
}

/// The one-re-ask nudge (§4.1) when a PM turn's verdict tail was missing or malformed. Asks
/// for the SAME review conclusion re-emitted with a valid tail — never a redo of the review.
public enum RelayReaskPrompt {
    public static func assemble(previousOutput: String, parseError: LoopVerdictParser.ExtractError) -> String {
        let parts = [
            "# Loop — verdict re-ask",
            """
            Your last reply didn't end with a usable `LoopVerdict` tail: \(describe(parseError))
            """,
            """
            ## What you just wrote (for reference — verbatim, unedited)
            \(previousOutputBlock(previousOutput))
            """,
            verdictContractBlock(),
            """
            ## What to do
            Do not redo the review. Re-emit the SAME conclusion you already reached, ending this \
            reply with exactly one valid ```json fenced `LoopVerdict` object per the contract above.
            """,
        ]
        return parts.joined(separator: "\n\n")
    }

    private static func describe(_ error: LoopVerdictParser.ExtractError) -> String {
        switch error {
        case .noVerdictFound:
            return "no JSON object anywhere in the reply carried a `verdict` key — the tail was missing entirely."
        case .unknownVerdict(let raw):
            return "the `verdict` value `\"\(raw)\"` isn't one of `continue`, `done`, `escalate`."
        case .continueWithoutHandover:
            return "`verdict: \"continue\"` was sent but `handover` was missing or empty — it's required whenever the relay continues."
        }
    }
}

// MARK: - Shared building blocks

/// One read seam for folder-native memory (`docs/phases/Folder_Native_Memory.md`).
private func memoryPointerLine() -> String {
    """
    If MEMORY.md exists at the repo root, read it before anything else; when a memory line \
    changes what you do, cite it in your report (e.g. honored MEMORY: <line>). If reality \
    contradicts a line, say so explicitly — do not silently work around it.
    """
}

/// The `LoopVerdict` contract, restated identically wherever the PM needs to see it. Kept
/// as one source of truth so the PM prompt and the re-ask prompt never drift apart.
private func verdictContractBlock() -> String {
    """
    ## End every reply with exactly one LoopVerdict
    Everything above is free prose. End this reply with exactly one ```json fenced object — \
    the only structure in this loop:

    - `verdict`: `"continue"` | `"done"` | `"escalate"`
    - `handover`: required when `verdict` is `"continue"` — the verbatim text for the dev's \
    next turn. It is sent to the dev untouched, so write it as the actual order, not a summary.
    - `note`: closing summary when `"done"`; the specific question the founder must answer \
    when `"escalate"`.

    Example:
    ```json
    {"verdict": "continue", "handover": "Add a test for the empty-list case, then re-run the suite."}
    ```
    """
}

/// Sentinel markers for embedding verbatim third-party text (dev reports, handovers, prior
/// PM output) inside a prompt. Plain text lines rather than ``` fences on purpose: the
/// embedded content itself may contain ```json fences (a dev report quoting a LoopVerdict
/// example, a code sample with triple backticks) — nesting fences would either terminate
/// early at the embedded content's own closing fence or force escaping that mutates the
/// "verbatim" guarantee. A unique-enough text sentinel needs no escaping and can never be
/// truncated by anything the embedded content contains.
private func devReportBlock(_ text: String, round: Int) -> String {
    """
    ----- DEV REPORT (VERBATIM, ROUND \(round)) BEGIN -----
    \(text)
    ----- DEV REPORT END -----
    """
}

private func handoverBlock(_ text: String) -> String {
    """
    ----- PM HANDOVER (VERBATIM) BEGIN -----
    \(text)
    ----- PM HANDOVER END -----
    """
}

private func previousOutputBlock(_ text: String) -> String {
    """
    ----- PREVIOUS PM OUTPUT (VERBATIM) BEGIN -----
    \(text)
    ----- PREVIOUS PM OUTPUT END -----
    """
}
