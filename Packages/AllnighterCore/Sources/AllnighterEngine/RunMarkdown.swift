import Foundation
import AllnighterCore

/// Renders a team run to Markdown for viewing and export. `run.json` is the
/// only truth; every `.md` here is derived from it (regenerated on stage change).
public enum RunMarkdown {
    public static func plan(_ run: TeamRun) -> String {
        run.plan ?? ""
    }

    /// A human-readable view of the structured `PlanAnalysis`.
    public static func analysis(_ run: TeamRun) -> String {
        guard let a = run.analysis else { return "" }
        var lines: [String] = ["# Team Analysis", ""]

        func points(_ title: String, _ items: [AnalysisPoint]) {
            guard !items.isEmpty else { return }
            lines.append("## \(title)")
            for p in items {
                let attrib = p.sourceAgentIds.isEmpty ? "" : " _(\(p.sourceAgentIds.joined(separator: ", ")))_"
                lines.append("- \(p.statement)\(attrib)")
            }
            lines.append("")
        }

        points("Consensus", a.consensus)

        if !a.contradictions.isEmpty {
            lines.append("## Conflicts")
            for c in a.contradictions {
                lines.append("- **\(c.topic)**")
                for pos in c.positions { lines.append("  - \(pos.agentId): \(pos.summary)") }
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

        if !a.failedWorkers.isEmpty {
            lines.append("## Workers that did not answer")
            for f in a.failedWorkers { lines.append("- \(f.agentId): \(f.reason)") }
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
    public static func bundle(_ run: TeamRun, models: [Model]) -> String {
        let workerByID = Dictionary(models.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        func sharesModel(_ seat: Agent) -> Bool {
            run.workers.filter { $0.modelId == seat.modelId }.count > 1
        }
        func seatName(_ seat: Agent) -> String {
            let modelName = workerByID[seat.modelId]?.displayName ?? seat.modelId
            return seat.displayName(modelName: modelName, sharesModel: sharesModel(seat))
        }

        var lines: [String] = ["# Team Run", "", "## Prompt", "", run.prompt, ""]

        let analysisText = analysis(run)
        if !analysisText.isEmpty {
            lines.append(contentsOf: ["---", "", analysisText, ""])
        }

        if let plan = run.plan, !plan.isEmpty {
            lines.append(contentsOf: ["---", "", plan, ""])
        }

        lines.append(contentsOf: ["---", "", "## Agent answers", ""])
        for seat in run.workers {
            let member = run.workerAnswer(workerId: seat.id)
            lines.append("### \(seatName(seat))")
            lines.append("")
            // VSI-S05: show durable text even when the seat did not finish `.done`
            // (`hasAnswer` requires done — that hid killed/failed partials).
            if let output = member?.output, !output.isEmpty {
                lines.append(output)
            } else {
                let status = member?.result.status.rawValue ?? "no answer"
                lines.append("_\(status): \(member?.result.errorReason ?? "no answer")_")
            }
            lines.append("")
        }

        // Reviews (RB2) and final spec (RB3) — canonical order.
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
        return lines.joined(separator: "\n")
    }

    /// Latest completed review per lens id (append-only stages → newest wins).
    public static func latestReviews(_ run: TeamRun) -> [StageOutput] {
        var byLens: [String: StageOutput] = [:]
        for stage in run.stages where stage.purpose == .review {
            let lens = stage.payload?.review?.lensId ?? stage.promptProfileId ?? stage.id
            byLens[lens] = stage
        }
        return byLens.values.sorted { ($0.promptProfileId ?? $0.id) < ($1.promptProfileId ?? $1.id) }
    }

    public static func finalSpec(_ run: TeamRun) -> String {
        run.latestStage(.finalSpec)?.payload?.markdown ?? ""
    }
}
