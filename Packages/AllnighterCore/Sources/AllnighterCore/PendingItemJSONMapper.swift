import Foundation

/// Projects internal `PendingItem` to `PendingItemJSON`.
public enum PendingItemDerivation {
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

    public static func blockedReason(for item: PendingItem) -> String? {
        if item.status == .draft { return nil }
        if item.status == .cancelled || item.status == .done || item.status == .failed { return nil }
        if item.resume != nil { return item.resume?.reason.rawValue }
        return nil
    }

    public static func needsAttention(blockedReason: String?) -> Bool {
        blockedReason != nil
    }

    public static func nextWakeAt(for item: PendingItem) -> Date? {
        item.resume?.observedResetAt ?? item.resume?.wakeAfter
    }
}

public enum PendingItemJSONMapper {
    public struct Context: Sendable {
        public var pendingStorePath: String
        public var traceId: String

        public init(
            pendingStorePath: String,
            traceId: String = UUID().uuidString
        ) {
            self.pendingStorePath = pendingStorePath
            self.traceId = traceId
        }
    }

    public static func map(_ item: PendingItem, context: Context) -> PendingItemJSON {
        let blocked = PendingItemDerivation.blockedReason(for: item)
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
                preferredModelIds: item.target.preferredModelIds,
                fallbackModelIds: item.target.fallbackModelIds,
                requiredModelIds: item.target.requiredModelIds,
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
            safety: .init(
                workingDir: item.safety.workingDir,
                requiresTrustedDevice: item.safety.requiresTrustedDevice,
                privacyLabel: item.safety.privacyLabel
            ),
            admission: nil,
            capacityObservation: item.resume?.capacityObservation.map {
                CapacityObservationJSONMapper.map($0, iso: iso)
            },
            attempts: item.attempts.map { attempt in
                .init(
                    attemptId: attempt.attemptId,
                    createdAt: iso.string(from: attempt.createdAt),
                    startedAt: attempt.startedAt.map { iso.string(from: $0) },
                    completedAt: attempt.completedAt.map { iso.string(from: $0) },
                    workerIds: attempt.workerIds,
                    status: attempt.status.rawValue,
                    reason: attempt.reason,
                    transcriptRef: attempt.transcriptRef
                )
            },
            nextActions: nextActions(for: item),
            audit: .init(traceId: context.traceId, pendingStorePath: context.pendingStorePath)
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

    /// Deterministic preview / iOS fixture builder (same module as nested JSON types).
    public static func previewItem(
        id: String,
        prompt: String,
        status: PendingItemJSON.ItemInfo.Status = .pending,
        modelId: String? = nil,
        teamPresetId: String? = nil,
        origin: PendingItemJSON.ItemInfo.Origin = .ios,
        now: Date = Date()
    ) -> PendingItemJSON {
        let iso = ISO8601DateFormatter()
        let stamp = iso.string(from: now)
        let workerIds = modelId.map { [$0] } ?? []
        return PendingItemJSON(
            contractVersion: ContractRegistry.contractVersion,
            pendingItem: .init(
                id: id,
                status: status,
                title: PendingItemDerivation.title(from: prompt),
                kind: .workerChat,
                origin: origin,
                threadId: nil,
                promptExcerpt: PendingItemDerivation.promptExcerpt(prompt),
                createdAt: stamp,
                updatedAt: stamp,
                nextWakeAt: nil,
                blockedReason: nil,
                needsAttention: false
            ),
            target: .init(
                workerIds: workerIds,
                teamPresetId: teamPresetId,
                preferredModelIds: workerIds,
                fallbackModelIds: [],
                requiredModelIds: [],
                minWorkers: nil
            ),
            policy: .init(
                selection: "selectedOnly",
                attentionMode: "present",
                drainMode: "drainWhenReady",
                maxAttempts: nil,
                retryFloorSeconds: nil,
                allowDegraded: false,
                requireKnownAvailable: false,
                createSuggestedFollowUps: false
            ),
            safety: .init(
                workingDir: nil,
                requiresTrustedDevice: false,
                privacyLabel: nil
            ),
            audit: .init(traceId: "preview", pendingStorePath: "/preview")
        )
    }
}
