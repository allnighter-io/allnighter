import Foundation

/// Loop seat casting for local Ollama-backed models (OCL-S07 / packet §2.4).
///
/// Loop already has the shape: a lead plans, an execution seat mutates under the
/// per-root write lock. A local seat is a valid `--dev` pin. It is not a valid
/// `--pm` occupant — the lead stays a frontier model or `caller`.
public enum LoopLocalSeatPolicy {
    public static let errorCode = "LOOP_LOCAL_SEAT_CANNOT_LEAD"

    public static func isOllamaBacked(_ model: Model) -> Bool {
        OllamaLocalDoctorReport.isOllamaBackedSeat(modelLabel: model.modelLabel)
    }

    public static func pmRefusal(for model: Model) -> String? {
        guard isOllamaBacked(model) else { return nil }
        return "local Ollama seat \(model.id) (\(model.modelLabel)) cannot hold the Loop PM chair — pin a frontier model or `--pm caller`; use this seat as `--dev`"
    }

    /// Dry-run / start warning when `--dev` is local. Failure is the common case.
    public static func localExecutionWarning(for model: Model) -> String? {
        guard isOllamaBacked(model) else { return nil }
        return "dev seat \(model.id) is a local Ollama seat (\(model.modelLabel)). Failure is the common case. Allnighter outcome facts (worker status, repo delta, proofs) — not the seat's report — are what the lead reviews. The local seat is not exempt from the per-root write lock."
    }
}
