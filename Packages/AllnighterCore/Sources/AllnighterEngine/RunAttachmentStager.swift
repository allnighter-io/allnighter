import Foundation
import AllnighterCore

/// Stages user-attached images for a *run* (single-worker default chat OR a team
/// fan-out) and returns the canonical `IncludedAttachmentDelivery` list to hand to
/// `RunService`/`CatalogRunCoordinator`, plus the `TurnAttachmentRef`s so the GUI can
/// link them to the user turn (thumbnail in the conversation).
///
/// This is the run-path twin of `ThreadSendCoordinator.prepareSend`'s ingest+stage
/// block: it commits each frozen image into the thread's canonical `ThreadAttachmentStore`,
/// mirrors them into `<workingDir>/.allnighter/attachments/…` (so a CLI worker can open
/// the path relative to its cwd), and verifies stored hashes. It deliberately does NOT
/// append turns, resolve a worker, or build a context packet — the run path owns those.
public struct RunAttachmentStager: Sendable {
    public struct Staged: Sendable, Equatable {
        public var deliveries: [IncludedAttachmentDelivery]
        public var refs: [TurnAttachmentRef]
        public var warnings: [String]

        public init(deliveries: [IncludedAttachmentDelivery], refs: [TurnAttachmentRef], warnings: [String]) {
            self.deliveries = deliveries
            self.refs = refs
            self.warnings = warnings
        }

        public static let empty = Staged(deliveries: [], refs: [], warnings: [])
    }

    private let idFactory: @Sendable () -> String
    private let now: @Sendable () -> Date

    public init(
        idFactory: @escaping @Sendable () -> String = { UUID().uuidString },
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.idFactory = idFactory
        self.now = now
    }

    /// Commit `images` into the thread's attachment store and stage workspace mirrors.
    /// `threadDirectory` is the thread's on-disk directory (from `ThreadStore`).
    /// `workingDir` is the run's repo root — when present, deliveries get a relative
    /// `.allnighter/…` path the worker can open from its cwd.
    public func stage(
        images: [ThreadSendCoordinator.ImageInput],
        threadId: String,
        threadDirectory: URL,
        workingDir: String?
    ) throws -> Staged {
        guard !images.isEmpty else { return .empty }

        let store = ThreadAttachmentStore(threadDirectory: threadDirectory)
        let flock = try ThreadFlockLock.acquire(lockURL: store.lockURL)
        defer { _ = flock }

        let timestamp = now()
        var committed: [TurnAttachment] = []
        var refs: [TurnAttachmentRef] = []
        var nextSequence = store.loadDraftIndex().nextSequence

        for image in images {
            let ingested = try store.ingestor.ingest(
                fileURL: image.frozenFileURL,
                sourceKind: image.sourceKind,
                originalName: image.originalName
            )
            let attachmentId = idFactory()
            let (record, ref) = try store.commitIngested(
                ingested: ingested,
                attachmentId: attachmentId,
                threadId: threadId,
                sourceKind: image.sourceKind,
                sequence: nextSequence,
                originalName: image.originalName,
                now: timestamp
            )
            nextSequence += 1
            committed.append(record)
            refs.append(ref)
        }

        refs.sort { $0.sequence < $1.sequence }

        var deliveries: [IncludedAttachmentDelivery] = refs.compactMap { ref in
            guard let attachment = committed.first(where: { $0.id == ref.attachmentId }) else { return nil }
            let canonical = store.canonicalURL(for: attachment).path
            return IncludedAttachmentDelivery(
                attachmentId: ref.attachmentId,
                sequence: ref.sequence,
                canonicalPath: canonical,
                deliveredPathUsed: canonical,
                storedSha256: attachment.storedSha256
            )
        }
        for offset in deliveries.indices { deliveries[offset].sequence = offset }

        try store.verifyHashes(for: committed)

        var warnings: [String] = []
        if let workingDir, !workingDir.isEmpty {
            warnings = try WorkspaceAttachmentStaging.stage(
                attachments: committed,
                deliveries: &deliveries,
                threadId: threadId,
                workingDir: workingDir,
                canonicalURL: store.canonicalURL(for:)
            )
        }

        return Staged(deliveries: deliveries, refs: refs, warnings: warnings)
    }
}
