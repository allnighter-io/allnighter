import Foundation
import AgentOSCLI

/// Shared usage presentation for live pilot/relay status and terminal receipts (OUR).
/// Never invents zeros; blames the CLI/source when tokens are absent.
public enum ObservedUsagePresentation {
    /// Compact tok / partial-side labels from driver-reported ints only.
    /// - Both sides: `12.4k tok` (sum when both present)
    /// - Input only: `input 12.4k tok`
    /// - Output only: `output 400 tok`
    /// - Empty: nil
    public static func compactTok(_ usage: ReportedTokenUsage?) -> String? {
        guard let usage, !usage.isEmpty else { return nil }
        switch (usage.inputTokens, usage.outputTokens) {
        case let (i?, o?):
            return ReportedTokenUsage.formatCompact(i + o) + " tok"
        case let (i?, nil):
            return "input \(ReportedTokenUsage.formatCompact(i)) tok"
        case let (nil, o?):
            return "output \(ReportedTokenUsage.formatCompact(o)) tok"
        case (nil, nil):
            return nil
        }
    }

    /// Wire shape for TeamRunJSON answer/outcome usage (absent when empty).
    public static func wireUsage(_ usage: ReportedTokenUsage?) -> TeamRunJSON.Outcome.TokenUsage? {
        guard let usage, !usage.isEmpty else { return nil }
        return TeamRunJSON.Outcome.TokenUsage(
            inputTokens: usage.inputTokens,
            outputTokens: usage.outputTokens
        )
    }

    /// Terminal / settled blame when tokens never arrived.
    public static func terminalBlame(sourceId: String?) -> String {
        let name = (sourceId?.isEmpty == false) ? sourceId! : "CLI"
        return "tokens not reported by \(name)"
    }

    /// Live / in-flight blame when tokens not yet on the journal.
    public static func runningBlame(sourceId: String?) -> String {
        let name = (sourceId?.isEmpty == false) ? sourceId! : "CLI"
        return "tokens not yet reported by \(name)"
    }

    /// Seat chip segment: compact tok, or blame, or nil when no source to name and no usage.
    public static func seatUsageSegment(
        usage: ReportedTokenUsage?,
        sourceId: String?,
        running: Bool
    ) -> String? {
        if let tok = compactTok(usage) { return tok }
        guard sourceId != nil || usage != nil else { return nil }
        return running ? runningBlame(sourceId: sourceId) : terminalBlame(sourceId: sourceId)
    }

    /// Single non-skipped seat with reported usage for outcome/headline compatibility.
    /// Multi-seat: nil (no sum, no first-answer copy).
    public static func singleSeatUsage(for run: TeamRun) -> ReportedTokenUsage? {
        let seats = run.answers.filter { $0.result.status != .skipped }
        guard seats.count == 1 else { return nil }
        guard let reported = seats[0].result.reportedTokenUsage, !reported.isEmpty else {
            return nil
        }
        return reported
    }

    /// Format measured duration for live lines (e.g. `2m 40s`, `18.4s`).
    public static func formatElapsed(seconds: Int) -> String {
        if seconds < 60 { return "\(seconds)s" }
        let m = seconds / 60
        let s = seconds % 60
        if s == 0 { return "\(m)m" }
        return "\(m)m \(s)s"
    }

    /// Format duration from ms for receipt chips.
    public static func formatDuration(ms: Int) -> String {
        if ms < 1000 { return "\(ms)ms" }
        let sec = Double(ms) / 1000.0
        if sec < 60 { return String(format: "%.1fs", sec) }
        return formatElapsed(seconds: Int(sec.rounded()))
    }

    /// Live pilot/relay usage for the active linked dev seat (OUR-S02).
    /// - nil `devRunId`: omit usage segment entirely (no fake CLI blame)
    /// - journal has usage: compact tok
    /// - non-terminal without usage: `not yet reported`
    /// - terminal without usage: `not reported` (settle / receipt path)
    public static func liveDevUsage(
        state: LoopState,
        runStore: some RunStoreReading,
        models: [Model] = []
    ) -> LiveUsageProjection? {
        guard let devRunId = state.rounds.last?.devRunId else { return nil }
        let run = runStore.load(runId: devRunId)
        let answer = run?.answers.first(where: { $0.result.status != .skipped })
            ?? run?.answers.first
        let usage = answer?.result.reportedTokenUsage
        let modelId = answer?.modelId
        let sourceId = modelId.flatMap { mid in
            if let m = models.first(where: { $0.id == mid }) { return m.driverId }
            return ModelCatalog.builtIns.first(where: { $0.id == mid })?.driverId
        } ?? modelId
        let terminal = run?.status.isTerminal == true
        let presentation: String
        if let tok = compactTok(usage) {
            presentation = tok
        } else if terminal {
            presentation = terminalBlame(sourceId: sourceId)
        } else {
            presentation = runningBlame(sourceId: sourceId)
        }
        return LiveUsageProjection(
            devRunId: devRunId,
            sourceId: sourceId,
            inputTokens: usage?.inputTokens,
            outputTokens: usage?.outputTokens,
            presentation: presentation
        )
    }

    /// Hero human/JSON live line segments (stream-primary; usage additive).
    public static func liveHeroLine(
        ownerAlive: Bool?,
        silenceAgeSeconds: Int?,
        elapsedSeconds: Int?,
        usagePresentation: String?
    ) -> String {
        var parts: [String] = []
        if let alive = ownerAlive {
            parts.append(alive ? "alive" : "dead")
        }
        if let silence = silenceAgeSeconds {
            if silence == 0 {
                parts.append("stream just now")
            } else {
                parts.append("stream \(formatElapsed(seconds: silence)) ago")
            }
        } else if ownerAlive == true {
            parts.append("no stream yet")
        } else if ownerAlive == false {
            parts.append("no stream")
        }
        if let elapsed = elapsedSeconds {
            parts.append(formatElapsed(seconds: elapsed))
        }
        if let usage = usagePresentation {
            parts.append(usage)
        }
        return parts.joined(separator: "  ·  ")
    }
}

/// Additive observed usage on live pilot/relay status (OUR-S02).
public struct LiveUsageProjection: Codable, Equatable, Sendable {
    public var devRunId: String
    public var sourceId: String?
    public var inputTokens: Int?
    public var outputTokens: Int?
    /// Compact tok or blame string (human + JSON parity).
    public var presentation: String

    public init(
        devRunId: String,
        sourceId: String? = nil,
        inputTokens: Int? = nil,
        outputTokens: Int? = nil,
        presentation: String
    ) {
        self.devRunId = devRunId
        self.sourceId = sourceId
        self.inputTokens = inputTokens
        self.outputTokens = outputTokens
        self.presentation = presentation
    }
}
