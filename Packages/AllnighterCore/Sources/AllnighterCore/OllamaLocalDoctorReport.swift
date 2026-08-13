import Foundation

/// Maps `OllamaLocalRuntimeObserver` into `alln doctor` checks and the
/// `alln models` readiness word. One projection — doctor checks and model
/// rows share the same three words.
///
/// Readiness only: three words (`Unavailable` | `Idle` | `Busy`). Not a
/// capacity source — never a strip row, never `benchSourceOrder`.
public enum OllamaLocalDoctorReport {
    public static let catalogLabelPrefix = "ollama/"
    public static let reachableCheckName = "source.ollama_local.reachable"
    public static let modelsCheckName = "source.ollama_local.models"
    public static let readinessCheckName = "source.ollama_local.readiness"

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
        from snapshot: OllamaLocalRuntimeObserver.Snapshot
    ) -> [DoctorResult.Check] {
        [
            reachableCheck(snapshot),
            modelsCheck(snapshot),
            readinessCheck(snapshot),
        ]
    }

    /// Same word doctor prints as `source.ollama_local.readiness`.
    public static func readinessWord(
        from snapshot: OllamaLocalRuntimeObserver.Snapshot
    ) -> String {
        readinessCheck(snapshot).detail
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
        _ snapshot: OllamaLocalRuntimeObserver.Snapshot
    ) -> DoctorResult.Check {
        .init(
            name: readinessCheckName,
            status: .ok,
            detail: snapshot.readiness.rawValue
        )
    }
}
