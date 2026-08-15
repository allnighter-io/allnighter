import Foundation

/// LR-S02a — mint a seated local row from a live overlay candidate.
///
/// Claude Code body only in this slice: persist `origin: .discovered` and
/// enable. OpenCode `opencode.json` merge + leftover-serve reclaim are S02b.
public enum LocalRuntimeSeatMint {
    /// Resolve `candidateID` from the live overlay (`candidateID(tag:)` +
    /// `/api/tags` snapshot). `get()` will not find it. `--body` on an
    /// already-seated id refuses. Prints belong to the caller — this returns
    /// `Assessment.disclosures` as the policy already writes them.
    public static func enable(
        candidateID: ModelID,
        bodyDriverId: String,
        snapshot: OllamaLocalRuntimeObserver.Snapshot?,
        now: Date = Date()
    ) throws -> OllamaLocalSeatEnablePolicy.Assessment {
        if ModelCatalog.get(candidateID) != nil {
            throw ModelCatalogError.invalid(
                "\(candidateID) is already seated — omit --body and run: alln models enable \(candidateID)"
            )
        }
        let overlay = ModelListProjector.overlayDefinitions(
            from: snapshot,
            seated: ModelCatalog.list(),
            now: now
        )
        guard let candidate = overlay.first(where: { $0.id == candidateID }) else {
            throw ModelCatalogError.notFound(candidateID)
        }
        let tag = OpenCodeLocalSeatReadiness.ollamaTag(from: candidate.modelLabel)
        let served = tag.flatMap { name in
            snapshot?.residentModels.first { $0.name == name }?.servedContextWindow
        }
        // No G1 store in this packet. Nil discloses the existing "has not passed G1" line.
        let assessment = OllamaLocalSeatEnablePolicy.assessExplicitEnable(
            candidate: candidate,
            bodyDriverId: bodyDriverId,
            g1Passed: nil,
            servedContextWindow: served
        )
        if let refusal = assessment.refusal {
            throw ModelCatalogError.invalid(refusal)
        }
        guard assessment.permitsEnable, var seat = assessment.boundSeat else {
            throw ModelCatalogError.invalid("explicit enable refused")
        }
        if ModelCatalog.get(seat.id) != nil {
            throw ModelCatalogError.invalid(
                "\(seat.id) is already seated — omit --body and run: alln models enable \(seat.id)"
            )
        }
        seat.origin = .discovered
        try ModelCatalog.saveDiscovered(seat)
        try ModelCatalog.setEnabled(seat.id, true)
        return assessment
    }
}
