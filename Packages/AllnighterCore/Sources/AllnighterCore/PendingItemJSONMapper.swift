import Foundation
import CryptoKit

/// Derives execution-lane keys and projects internal `PendingItem` to `PendingItemJSON`.
public enum PendingItemDerivation {
    public static let laneKeyVersion = "v1"

    /// `v1:hash(workerId, normalizedWorkingDir || "unknown-dir", sessionBinding || "unknown-session")`
    public static func executionLaneKey(workerId: String, workingDir: String?, sessionBinding: String? = nil) -> String {
        let dir = normalizedWorkingDir(workingDir)
        let session = sessionBinding ?? "unknown-session"
        let material = "\(laneKeyVersion):\(workerId):\(dir):\(session)"
        let digest = SHA256.hash(data: Data(material.utf8))
        let hex = digest.map { String(format: "%02x", $0) }.joined()
        return "\(laneKeyVersion):\(hex.prefix(16))"
    }

    public static func normalizedWorkingDir(_ path: String?) -> String {
        guard let path, !path.isEmpty else { return "unknown-dir" }
        let expanded = (path as NSString).expandingTildeInPath
        return URL(fileURLWithPath: expanded).standardizedFileURL.path
    }

    public static func defaultIntent(for kind: PendingItemKind) -> PendingExecutionIntent {
        switch kind {
        case .workerChat, .followUp, .returnReview, .teamRun: return .ask
        case .workOrder, .dispatch: return .execute
        }
    }

    public static func title(from prompt: String) -> String {
        let trimmed = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return "Pending item" }
        let firstLine = trimmed.split(separator: "\n", maxSplits: 1).first.map(String.init) ?? trimmed
        if firstLine.count <= 80 { return firstLine }
        return String(firstLine.prefix(77)) + "..."
    }

    public static func promptExcerpt(_ prompt: String, limit: Int = 160) -> String {
        let trimmed = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.count <= limit { return trimmed }
        return String(trimmed.prefix(limit - 1)) + "…"
    }

    public static func blockedReason(for item: PendingItem, laneHeadId: String?) -> String? {
        if item.status == .draft { return nil }
        if item.status == .cancelled || item.status == .done || item.status == .failed { return nil }
        if item.kind == .dispatch || item.kind == .workOrder, item.execution?.intent == .execute {
            // Mutating dispatch deferred from Pending M1.
            if item.kind == .dispatch { return "mutationDeferred" }
        }
        if let laneHeadId, laneHeadId != item.id, item.execution?.intent == .execute {
            return "executionLaneBusy"
        }
        if item.resume != nil { return item.resume?.reason.rawValue }
        return nil
    }

    public static func needsAttention(blockedReason: String?) -> Bool {
        guard let blockedReason else { return false }
        return blockedReason != "executionLaneBusy"
    }

    public static func nextWakeAt(for item: PendingItem) -> Date? {
        item.resume?.observedResetAt ?? item.resume?.wakeAfter
    }
}

public enum PendingItemJSONMapper {
    public struct Context: Sendable {
        public var pendingStorePath: String
        public var traceId: String
        public var executionLaneHeadItemId: String?
        public var userReorderedExecutionLane: Bool?

        public init(
            pendingStorePath: String,
            traceId: String = UUID().uuidString,
            executionLaneHeadItemId: String? = nil,
            userReorderedExecutionLane: Bool? = nil
        ) {
            self.pendingStorePath = pendingStorePath
            self.traceId = traceId
            self.executionLaneHeadItemId = executionLaneHeadItemId
            self.userReorderedExecutionLane = userReorderedExecutionLane
        }
    }

    public static func map(_ item: PendingItem, context: Context) -> PendingItemJSON {
        let execution = item.execution ?? PendingExecution(intent: PendingItemDerivation.defaultIntent(for: item.kind))
        let blocked = PendingItemDerivation.blockedReason(for: item, laneHeadId: context.executionLaneHeadItemId)
        let iso = ISO8601DateFormatter()

        return PendingItemJSON(
            contractVersion: ContractRegistry.contractVersion,
            pendingItem: .init(
                id: item.id,
                status: mapStatus(item.status),
                title: item.title,
                kind: mapKind(item.kind),
                origin: mapOrigin(item.origin),
                threadId: item.threadId,
                promptExcerpt: PendingItemDerivation.promptExcerpt(item.prompt),
                createdAt: iso.string(from: item.createdAt),
                updatedAt: iso.string(from: item.updatedAt),
                nextWakeAt: PendingItemDerivation.nextWakeAt(for: item).map { iso.string(from: $0) },
                blockedReason: blocked,
                needsAttention: PendingItemDerivation.needsAttention(blockedReason: blocked)
            ),
            target: .init(
                workerIds: item.target.workerIds,
                teamPresetId: item.target.teamPresetId,
                preferredWorkerIds: item.target.preferredWorkerIds,
                fallbackWorkerIds: item.target.fallbackWorkerIds,
                requiredWorkerIds: item.target.requiredWorkerIds,
                minWorkers: item.target.minWorkers
            ),
            policy: .init(
                selection: item.policy.selection.rawValue,
                attentionMode: item.policy.attentionMode.rawValue,
                drainMode: item.policy.drainMode.rawValue,
                maxAttempts: item.policy.maxAttempts,
                retryFloorSeconds: item.policy.retryFloorSeconds,
                allowDegraded: item.policy.allowDegraded,
                requireKnownAvailable: item.policy.requireKnownAvailable,
                createSuggestedFollowUps: item.policy.createSuggestedFollowUps
            ),
            execution: .init(
                intent: execution.intent.rawValue,
                executionLaneKey: execution.executionLaneKey,
                executionLaneKeyVersion: execution.executionLaneKeyVersion,
                executionLanePolicy: execution.executionLanePolicy.rawValue,
                executionLaneOrder: execution.executionLaneOrder,
                executionLaneHeadItemId: context.executionLaneHeadItemId,
                executionLaneBlockedByItemId: blocked == "executionLaneBusy" ? context.executionLaneHeadItemId : nil,
                executionLanePausedReason: nil
            ),
            safety: .init(
                workingDir: item.safety.workingDir,
                requiresTrustedDevice: item.safety.requiresTrustedDevice,
                privacyLabel: item.safety.privacyLabel
            ),
            admission: nil,
            attempts: item.attempts.map { attempt in
                .init(
                    attemptId: attempt.attemptId,
                    createdAt: iso.string(from: attempt.createdAt),
                    startedAt: attempt.startedAt.map { iso.string(from: $0) },
                    completedAt: attempt.completedAt.map { iso.string(from: $0) },
                    workerIds: attempt.workerIds,
                    status: attempt.status.rawValue,
                    executionLaneKey: attempt.executionLaneKey,
                    reason: attempt.reason
                )
            },
            nextActions: nextActions(for: item),
            audit: .init(
                traceId: context.traceId,
                pendingStorePath: context.pendingStorePath,
                userReorderedExecutionLane: context.userReorderedExecutionLane
            )
        )
    }

    private static func nextActions(for item: PendingItem) -> [PendingItemJSON.NextAction] {
        switch item.status {
        case .draft:
            return [
                .init(kind: .submitPending, command: "alln pending submit \(item.id)", label: "Submit to Pending"),
                .init(kind: .showPending, command: "alln pending show \(item.id) --json", label: "Show item"),
            ]
        case .pending, .running:
            return [
                .init(kind: .runPending, command: "alln pending run \(item.id) --json", label: "Run now"),
                .init(kind: .cancelPending, command: "alln pending cancel \(item.id)", label: "Cancel"),
                .init(kind: .showPending, command: "alln pending show \(item.id) --json", label: "Show item"),
            ]
        case .done, .failed, .cancelled:
            return [.init(kind: .showPending, command: "alln pending show \(item.id) --json", label: "Show item")]
        }
    }

    private static func mapStatus(_ status: PendingItemStatus) -> PendingItemJSON.ItemInfo.Status {
        PendingItemJSON.ItemInfo.Status(rawValue: status.rawValue) ?? .draft
    }

    private static func mapKind(_ kind: PendingItemKind) -> PendingItemJSON.ItemInfo.Kind {
        PendingItemJSON.ItemInfo.Kind(rawValue: kind.rawValue) ?? .workerChat
    }

    private static func mapOrigin(_ origin: PendingOrigin) -> PendingItemJSON.ItemInfo.Origin {
        PendingItemJSON.ItemInfo.Origin(rawValue: origin.rawValue) ?? .cli
    }
}
