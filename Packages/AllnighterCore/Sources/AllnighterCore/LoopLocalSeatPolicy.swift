import Foundation

/// Loop seat casting for local Ollama-backed models (OCL-S07 / packet §2.4, §7.7).
///
/// Loop already has the shape: a lead plans, an execution seat mutates under the
/// per-root write lock. A local seat is a valid `--dev` pin. An explicit `--pm`
/// pin of a local Ollama-backed seat is also allowed: sensors inform, they never
/// block, and provenance is not a refuse-class. Disclose local provenance and
/// the served context window (if known) once, then proceed — same warn-and-allow
/// as an explicit `--model` pin below the context gate.
public enum LoopLocalSeatPolicy {
    public static func isOllamaBacked(_ model: Model) -> Bool {
        OllamaLocalDoctorReport.isOllamaBackedSeat(modelLabel: model.modelLabel)
    }

    /// One-shot disclosure when the Loop PM chair is a local Ollama seat.
    /// Never a refusal. Omit the window clause when it was not observed.
    public static func localLeadDisclosure(
        for model: Model,
        servedContextWindow: Int? = nil
    ) -> String? {
        guard isOllamaBacked(model) else { return nil }
        var sentences = [
            "\(model.displayName) runs on your Mac through Ollama."
        ]
        if let servedContextWindow {
            sentences.append(
                "This model has a \(LocalRuntimeAdvisory.formatContextSize(servedContextWindow)) context."
            )
        }
        sentences.append("You pinned it as the Loop lead.")
        return sentences.joined(separator: " ")
    }

    /// Served window from an observed `/api/ps` row. Nil when unobserved —
    /// never filled from advertised `context_length`.
    public static func servedContextWindow(
        for model: Model,
        snapshot: OllamaLocalRuntimeObserver.Snapshot?
    ) -> Int? {
        guard let snapshot,
              let tag = OpenCodeLocalSeatReadiness.ollamaTag(from: model.modelLabel)
        else { return nil }
        return snapshot.residentModels.first { observed in
            observed.name == tag || observed.name.hasSuffix("/\(tag)")
        }?.servedContextWindow
    }

    /// Dry-run / start warning when `--dev` is local. Failure is the common case.
    public static func localExecutionWarning(for model: Model) -> String? {
        guard isOllamaBacked(model) else { return nil }
        return "dev seat \(model.id) is a local Ollama seat (\(model.modelLabel)). Failure is the common case. Allnighter outcome facts (worker status, repo delta, proofs) — not the seat's report — are what the lead reviews. The local seat is not exempt from the per-root write lock."
    }
}
