import Foundation
import AgentOSCLI

/// Provenance-scoped OpenCode readiness (Ollama local seats packet §6.1 / §7.2).
///
/// Driver `opencode` is shared by Zen, Go, and local Ollama seats. The driver
/// probe smokes OpenCode Zen. That remote result must never disable a seat whose
/// catalog label is `ollama/<tag>`. Local evidence is: the OpenCode binary is
/// present, plus Ollama reachable with that tag (`sourceId=ollama_local`).
/// Go / Zen seats keep the existing driver probe.
public enum OpenCodeLocalSeatReadiness {
    public static let driverId = OpenCodeModelGate.driverId

    public static func isLocalOpenCodeSeat(driverId: String, modelLabel: String) -> Bool {
        driverId == Self.driverId
            && OllamaLocalDoctorReport.isOllamaBackedSeat(modelLabel: modelLabel)
    }

    public static func isLocalOpenCodeSeat(_ def: ModelDefinition) -> Bool {
        isLocalOpenCodeSeat(driverId: def.driverId, modelLabel: def.modelLabel)
    }

    public static func isLocalOpenCodeSeat(_ model: Model) -> Bool {
        isLocalOpenCodeSeat(driverId: model.driverId, modelLabel: model.modelLabel)
    }

    /// Tag after `ollama/`. Nil when the label is not a local Ollama seat.
    public static func ollamaTag(from modelLabel: String) -> String? {
        guard OllamaLocalDoctorReport.isOllamaBackedSeat(modelLabel: modelLabel) else {
            return nil
        }
        let tag = String(modelLabel.dropFirst(OllamaLocalDoctorReport.catalogLabelPrefix.count))
        let trimmed = tag.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    /// Binary path when detect found an executable — including after a Zen/Go
    /// smoke failure. Absence of a path is missing CLI; a failed remote smoke is not.
    public static func installedBinaryPath(from record: ToolProbeRecord?) -> String? {
        installedBinaryPath(from: record, driverId: driverId)
    }

    /// Same rule for any driver record (Claude-local uses `claude_code`).
    public static func installedBinaryPath(
        from record: ToolProbeRecord?,
        driverId: String
    ) -> String? {
        guard let record, record.driverId == driverId else { return nil }
        switch record.status {
        case .notInstalled, .shimmedNeedsConfirm:
            return nil
        case .ready, .installedNotProbed, .installedNotSignedIn, .rateLimited, .probeFailed:
            return record.invocation?.resolvedPath
        }
    }

    /// True when local evidence admits the seat. Nil snapshot is unobserved —
    /// never inferred ready, and never borrowed from a Zen/Go probe.
    public static func isLocallyReady(
        modelLabel: String,
        binaryPath: String?,
        snapshot: OllamaLocalRuntimeObserver.Snapshot?
    ) -> Bool {
        guard binaryPath != nil, let snapshot else { return false }
        return tagIsPresentLocally(modelLabel: modelLabel, snapshot: snapshot)
    }

    public static func tagIsPresentLocally(
        modelLabel: String,
        snapshot: OllamaLocalRuntimeObserver.Snapshot
    ) -> Bool {
        guard let tag = ollamaTag(from: modelLabel) else { return false }
        guard snapshot.ollamaVersion != nil else { return false }
        if snapshot.localTags.contains(where: { namesMatch($0.name, tag: tag) }) {
            return true
        }
        return snapshot.residentModels.contains(where: { namesMatch($0.name, tag: tag) })
    }

    /// Local verify outcome. Never invokes OpenCode, Zen, or Go.
    public static func verify(
        modelLabel: String,
        driverId: String,
        probeRecord: ToolProbeRecord?,
        snapshot: OllamaLocalRuntimeObserver.Snapshot?,
        now: Date = Date()
    ) -> LocalVerify {
        verifyOllamaBackedSeat(
            isLocalSeat: isLocalOpenCodeSeat(driverId: driverId, modelLabel: modelLabel),
            modelLabel: modelLabel,
            driverId: driverId,
            probeRecord: probeRecord,
            snapshot: snapshot,
            now: now,
            unobservedDetail: "Ollama not observed — local seat does not use Zen/Go smoke"
        )
    }

    /// Shared local-evidence verify for OpenCode-local and Claude-local.
    /// Never spawns the agent body. A Claude-local `claude -p` token echo hangs
    /// (idle watchdog, no session bypassPermissions) while Ollama and the body
    /// themselves answer — that spawn is not evidence.
    public static func verifyOllamaBackedSeat(
        isLocalSeat: Bool,
        modelLabel: String,
        driverId: String,
        probeRecord: ToolProbeRecord?,
        snapshot: OllamaLocalRuntimeObserver.Snapshot?,
        now: Date = Date(),
        unobservedDetail: String
    ) -> LocalVerify {
        guard isLocalSeat else {
            return .notLocalSeat
        }
        guard installedBinaryPath(from: probeRecord, driverId: driverId) != nil else {
            return .missingCLI
        }
        guard let snapshot else {
            return .inconclusive(
                ModelSmokeResult(
                    status: .inconclusive,
                    detail: unobservedDetail,
                    checkedAt: now,
                    driverId: driverId,
                    label: modelLabel
                )
            )
        }
        guard snapshot.ollamaVersion != nil else {
            return .rejected(
                ModelSmokeResult(
                    status: .unrecognized,
                    detail: "Ollama not reachable",
                    checkedAt: now,
                    driverId: driverId,
                    label: modelLabel
                )
            )
        }
        guard tagIsPresentLocally(modelLabel: modelLabel, snapshot: snapshot) else {
            let tag = ollamaTag(from: modelLabel) ?? modelLabel
            return .rejected(
                ModelSmokeResult(
                    status: .unrecognized,
                    detail: "Ollama tag not present locally: \(tag)",
                    checkedAt: now,
                    driverId: driverId,
                    label: modelLabel
                )
            )
        }
        return .recognized(
            ModelSmokeResult(
                status: .recognized,
                detail: nil,
                checkedAt: now,
                driverId: driverId,
                label: modelLabel
            )
        )
    }

    public enum LocalVerify: Sendable, Equatable {
        case notLocalSeat
        case missingCLI
        case recognized(ModelSmokeResult)
        case rejected(ModelSmokeResult)
        case inconclusive(ModelSmokeResult)
    }

    private static func namesMatch(_ observed: String, tag: String) -> Bool {
        observed == tag || observed.hasSuffix("/\(tag)")
    }
}
