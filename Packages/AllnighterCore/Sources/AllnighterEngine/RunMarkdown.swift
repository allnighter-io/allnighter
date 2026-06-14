import Foundation
import AllnighterCore

/// Renders a council run to Markdown for viewing and export.
public enum RunMarkdown {
    public static func masterPlan(_ run: CouncilRun) -> String {
        run.synthesis?.masterPlanMarkdown ?? ""
    }

    /// The full export bundle: prompt + every member answer (or failure reason)
    /// + the master plan. One file, ready for the clipboard or notes app.
    public static func bundle(_ run: CouncilRun, workers: [Worker]) -> String {
        let nameByID = Dictionary(uniqueKeysWithValues: workers.map { ($0.id, $0.displayName) })
        func name(_ id: String) -> String { nameByID[id] ?? id }

        var lines: [String] = ["# Council Run", "", "## Prompt", "", run.prompt, ""]

        if let plan = run.synthesis?.masterPlanMarkdown, !plan.isEmpty {
            lines.append(contentsOf: ["---", "", plan, ""])
        }

        lines.append(contentsOf: ["---", "", "## Member answers", ""])
        for member in run.members {
            lines.append("### \(name(member.workerId))")
            lines.append("")
            if member.hasAnswer {
                lines.append(member.output ?? "")
            } else {
                lines.append("_\(member.status.rawValue): \(member.errorReason ?? "no answer")_")
            }
            lines.append("")
        }

        return lines.joined(separator: "\n")
    }
}
