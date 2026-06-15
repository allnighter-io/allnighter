import Foundation
import AllnighterCore

/// Renders a council run to Markdown for viewing and export. `run.json` is the
/// only truth; every `.md` here is derived from it (regenerated on stage change).
public enum RunMarkdown {
    public static func masterPlan(_ run: CouncilRun) -> String {
        run.masterPlan ?? ""
    }

    /// A human-readable view of the structured `JudgeAnalysis`.
    public static func analysis(_ run: CouncilRun) -> String {
        guard let a = run.analysis else { return "" }
        var lines: [String] = ["# Council Analysis", ""]

        func points(_ title: String, _ items: [AnalysisPoint]) {
            guard !items.isEmpty else { return }
            lines.append("## \(title)")
            for p in items {
                let attrib = p.sourceSeatIds.isEmpty ? "" : " _(\(p.sourceSeatIds.joined(separator: ", ")))_"
                lines.append("- \(p.statement)\(attrib)")
            }
            lines.append("")
        }

        points("Consensus", a.consensus)

        if !a.contradictions.isEmpty {
            lines.append("## Conflicts")
            for c in a.contradictions {
                lines.append("- **\(c.topic)**")
                for pos in c.positions { lines.append("  - \(pos.seatId): \(pos.summary)") }
                lines.append("  - → \(c.recommendedResolution)")
            }
            lines.append("")
        }

        points("Unique insights", a.uniqueInsights)

        if !a.blindSpots.isEmpty {
            lines.append("## Blind spots & gaps")
            for b in a.blindSpots { lines.append("- \(b)") }
            lines.append("")
        }

        if !a.failedSeats.isEmpty {
            lines.append("## Seats that did not answer")
            for f in a.failedSeats { lines.append("- \(f.seatId): \(f.reason)") }
            lines.append("")
        }

        if let note = a.confidenceNote, !note.isEmpty {
            lines.append("## Confidence note")
            lines.append(note)
            lines.append("")
        }
        return lines.joined(separator: "\n")
    }

    /// The full export bundle, canonical order: prompt → members → analysis →
    /// plan (RB appends reviews → final spec → return).
    public static func bundle(_ run: CouncilRun, workers: [Worker]) -> String {
        let workerByID = Dictionary(workers.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        func sharesWorker(_ seat: PanelSeat) -> Bool {
            run.panel.filter { $0.workerId == seat.workerId }.count > 1
        }
        func seatName(_ seat: PanelSeat) -> String {
            let workerName = workerByID[seat.workerId]?.displayName ?? seat.workerId
            return seat.displayName(workerName: workerName, sharesWorker: sharesWorker(seat))
        }

        var lines: [String] = ["# Council Run", "", "## Prompt", "", run.prompt, ""]

        let analysisText = analysis(run)
        if !analysisText.isEmpty {
            lines.append(contentsOf: ["---", "", analysisText, ""])
        }

        if let plan = run.masterPlan, !plan.isEmpty {
            lines.append(contentsOf: ["---", "", plan, ""])
        }

        lines.append(contentsOf: ["---", "", "## Member answers", ""])
        for seat in run.panel {
            let member = run.member(seatId: seat.id)
            lines.append("### \(seatName(seat))")
            lines.append("")
            if let member, member.hasAnswer {
                lines.append(member.output ?? "")
            } else {
                let status = member?.status.rawValue ?? "no answer"
                lines.append("_\(status): \(member?.errorReason ?? "no answer")_")
            }
            lines.append("")
        }

        // Reviews (RB2), final spec (RB3), return review (RB5) — canonical order.
        let reviews = run.stages.filter { $0.purpose == .review && $0.status == .done }
        if !reviews.isEmpty {
            lines.append(contentsOf: ["---", "", "## Reviews", ""])
            for r in reviews {
                lines.append("### \(r.payload?.review?.lensId ?? r.promptProfileId ?? r.id)")
                lines.append(""); lines.append(r.payload?.markdown ?? ""); lines.append("")
            }
        }
        if let final = run.latestStage(.finalSpec)?.payload?.markdown {
            lines.append(contentsOf: ["---", "", "## Final Spec", "", final, ""])
        }
        if let ret = run.latestStage(.returnReview)?.payload?.markdown {
            lines.append(contentsOf: ["---", "", "## Return Review", "", ret, ""])
        }

        return lines.joined(separator: "\n")
    }

    /// Latest completed review per lens id (append-only stages → newest wins).
    public static func latestReviews(_ run: CouncilRun) -> [StageOutput] {
        var byLens: [String: StageOutput] = [:]
        for stage in run.stages where stage.purpose == .review {
            let lens = stage.payload?.review?.lensId ?? stage.promptProfileId ?? stage.id
            byLens[lens] = stage
        }
        return byLens.values.sorted { ($0.promptProfileId ?? $0.id) < ($1.promptProfileId ?? $1.id) }
    }

    public static func finalSpec(_ run: CouncilRun) -> String {
        run.latestStage(.finalSpec)?.payload?.markdown ?? ""
    }
}
