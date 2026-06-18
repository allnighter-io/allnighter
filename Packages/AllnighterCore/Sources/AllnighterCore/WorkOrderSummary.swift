import Foundation

/// Prediction-free rendering of the work order the user chose. Structural facts
/// only — no seconds, quota, calls-as-estimate, or "est." prefix.
public enum WorkOrderSummary {
    /// Team composer shape: workers, plan writer, analysis depth, optional lenses.
    public static func teamSummary(
        workerCount: Int,
        planWriterLabel: String?,
        synthesis: SynthesisConfig,
        lensCount: Int = 0
    ) -> String {
        var parts: [String] = ["\(workerCount) worker\(workerCount == 1 ? "" : "s")"]
        if let planWriterLabel, !planWriterLabel.isEmpty {
            parts.append("\(planWriterLabel) plan writer")
        }
        let stageShape = synthesis.analysisDepth == .combined
            ? "combined analysis + plan"
            : "separate analysis + plan"
        parts.append(stageShape)
        if lensCount > 0 {
            parts.append("\(lensCount) lens\(lensCount == 1 ? "" : "es")")
        }
        return parts.joined(separator: " · ")
    }

    /// Design lane shape: requested mockup count and engines.
    public static func designSummary(outputCount: Int, engineNames: [String]) -> String {
        let engines = engineNames.joined(separator: ", ")
        return "\(outputCount) mockup\(outputCount == 1 ? "" : "s") · \(engines)"
    }
}
