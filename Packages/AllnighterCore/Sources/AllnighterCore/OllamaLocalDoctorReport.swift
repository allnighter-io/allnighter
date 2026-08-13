import Foundation

/// Maps `OllamaLocalRuntimeObserver` into `alln doctor` checks and the
/// `alln models` readiness word. One projection — doctor checks and model
/// rows share the same two words, scoped per seat.
///
/// Readiness only: `Available` | `Unavailable`. A seat is Available when
/// Ollama is reachable and that seat's tag is pulled locally. Ollama down
/// makes every local seat Unavailable — no special case. Failure to observe
/// is not Available; never a guessed Available. Not a capacity source —
/// never a strip row, never `benchSourceOrder`. No latency / warm-cold word.
public enum OllamaLocalDoctorReport {
    public static let catalogLabelPrefix = "ollama/"
    public static let reachableCheckName = "source.ollama_local.reachable"
    public static let modelsCheckName = "source.ollama_local.models"
    public static let readinessCheckName = "source.ollama_local.readiness"
    public static let availableWord = "Available"
    public static let unavailableWord = "Unavailable"

    public static let checkNames: [String] = [
        reachableCheckName,
        modelsCheckName,
        readinessCheckName,
    ]

    /// Live loopback observe is production-only. Tests must inject a transport
    /// or receive `nil` (omit the checks) — never open a socket to Ollama.
    public static func snapshotIfAllowed(
        transport: (any OllamaLocalRuntimeClient.Transport)?,
        observedAt: Date,
        isTestHost: Bool
    ) -> OllamaLocalRuntimeObserver.Snapshot? {
        if let transport {
            return OllamaLocalRuntimeObserver.observe(
                transport: transport,
                observedAt: observedAt
            )
        }
        if isTestHost {
            return nil
        }
        return OllamaLocalRuntimeObserver.observe(
            transport: OllamaLocalRuntimeClient.URLSessionTransport(),
            observedAt: observedAt
        )
    }

    public static func checks(
        from snapshot: OllamaLocalRuntimeObserver.Snapshot,
        localSeatLabels: [String] = []
    ) -> [DoctorResult.Check] {
        [
            reachableCheck(snapshot),
            modelsCheck(snapshot),
            readinessCheck(snapshot, localSeatLabels: localSeatLabels),
        ]
    }

    /// Same word a models row prints for this local seat. Doctor lists
    /// `tag: <word>` using this function — never a parallel mapping.
    public static func readinessWord(
        from snapshot: OllamaLocalRuntimeObserver.Snapshot,
        modelLabel: String
    ) -> String {
        isAvailable(from: snapshot, modelLabel: modelLabel)
            ? availableWord
            : unavailableWord
    }

    /// Reachable Ollama plus this seat's tag pulled locally. Version/tags
    /// observe failures are not Available. A `/api/ps` failure does not
    /// invent unavailability of a tag already observed in `/api/tags` —
    /// ps still runs for served context, not for this word.
    public static func isAvailable(
        from snapshot: OllamaLocalRuntimeObserver.Snapshot,
        modelLabel: String
    ) -> Bool {
        guard snapshot.ollamaVersion != nil else { return false }
        switch snapshot.observeFailure {
        case .some(.version), .some(.unparseableVersion), .some(.tags), .some(.unparseableTags):
            return false
        default:
            break
        }
        return OpenCodeLocalSeatReadiness.tagIsPresentLocally(
            modelLabel: modelLabel,
            snapshot: snapshot
        )
    }

    /// Body-agnostic: catalog label `ollama/<tag>` is a local Ollama seat.
    public static func isOllamaBackedSeat(modelLabel: String) -> Bool {
        modelLabel.hasPrefix(catalogLabelPrefix)
    }

    private static func reachableCheck(
        _ snapshot: OllamaLocalRuntimeObserver.Snapshot
    ) -> DoctorResult.Check {
        let detail: String
        if let version = snapshot.ollamaVersion {
            detail = "reachable (\(version))"
        } else {
            detail = "not reachable"
        }
        return .init(
            name: reachableCheckName,
            status: .ok,
            detail: detail
        )
    }

    private static func modelsCheck(
        _ snapshot: OllamaLocalRuntimeObserver.Snapshot
    ) -> DoctorResult.Check {
        let names = snapshot.localTags.map(\.name)
        let detail = names.isEmpty ? "none" : names.joined(separator: ", ")
        return .init(
            name: modelsCheckName,
            status: .ok,
            detail: detail
        )
    }

    private static func readinessCheck(
        _ snapshot: OllamaLocalRuntimeObserver.Snapshot,
        localSeatLabels: [String]
    ) -> DoctorResult.Check {
        .init(
            name: readinessCheckName,
            status: .ok,
            detail: readinessDetail(from: snapshot, localSeatLabels: localSeatLabels)
        )
    }

    static func readinessDetail(
        from snapshot: OllamaLocalRuntimeObserver.Snapshot,
        localSeatLabels: [String]
    ) -> String {
        var seen = Set<String>()
        var labels: [String] = []
        let fromTags = snapshot.localTags.map { catalogLabelPrefix + $0.name }
        for label in fromTags + localSeatLabels {
            guard isOllamaBackedSeat(modelLabel: label),
                  let tag = OpenCodeLocalSeatReadiness.ollamaTag(from: label)
            else { continue }
            if seen.insert(tag).inserted {
                labels.append(label)
            }
        }
        if labels.isEmpty {
            return unavailableWord
        }
        return labels.map { label in
            let tag = OpenCodeLocalSeatReadiness.ollamaTag(from: label) ?? label
            return "\(tag): \(readinessWord(from: snapshot, modelLabel: label))"
        }.joined(separator: "; ")
    }
}
