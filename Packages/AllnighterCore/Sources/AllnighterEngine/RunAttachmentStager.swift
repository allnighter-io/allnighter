import Foundation
#if canImport(CryptoKit)
import CryptoKit
#else
import Crypto
#endif
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

    /// A captured long-paste snippet to commit as a real `.txt` file the worker reads by
    /// path (so two snippets are two files, not two walls of inline prompt text).
    public struct TextSnippet: Sendable, Equatable {
        public var title: String
        public var body: String
        public init(title: String, body: String) {
            self.title = title
            self.body = body
        }
    }

    /// Commit `snippets` as durable `.txt` files in the thread's attachment dir, mirror
    /// them into the workspace so a CLI worker can open them, and return `.text`
    /// deliveries. `startSequence` keeps text after any images in the combined list.
    public func stageText(
        snippets: [TextSnippet],
        threadId: String,
        threadDirectory: URL,
        workingDir: String?,
        startSequence: Int = 0
    ) throws -> Staged {
        guard !snippets.isEmpty else { return .empty }

        let canonicalDir = threadDirectory.appendingPathComponent("attachments", isDirectory: true)
        try FileManager.default.createDirectory(at: canonicalDir, withIntermediateDirectories: true)

        var mirrorRoot: URL?
        if let workingDir, !workingDir.isEmpty {
            let root = URL(fileURLWithPath: workingDir)
                .appendingPathComponent(".allnighter/attachments/thread_\(threadId)", isDirectory: true)
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            mirrorRoot = root
        }

        var deliveries: [IncludedAttachmentDelivery] = []
        for (offset, snippet) in snippets.enumerated() {
            let attachmentId = idFactory()
            let data = Data(snippet.body.utf8)
            let sha = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
            let canonical = canonicalDir.appendingPathComponent("\(attachmentId).txt")
            try data.write(to: canonical)

            var deliveredPath = canonical.path
            if let mirrorRoot {
                let dest = mirrorRoot.appendingPathComponent("\(attachmentId).txt")
                if FileManager.default.fileExists(atPath: dest.path) {
                    try FileManager.default.removeItem(at: dest)
                }
                try FileManager.default.copyItem(at: canonical, to: dest)
                deliveredPath = ".allnighter/attachments/thread_\(threadId)/\(attachmentId).txt"
            }

            deliveries.append(IncludedAttachmentDelivery(
                attachmentId: attachmentId,
                sequence: startSequence + offset,
                canonicalPath: canonical.path,
                deliveredPathUsed: deliveredPath,
                storedSha256: sha,
                kind: .text))
        }

        var warnings: [String] = []
        if let workingDir, !workingDir.isEmpty {
            warnings.append(contentsOf: GitAttachmentHygiene.ensureIgnored(workingDir: workingDir))
        }
        return Staged(deliveries: deliveries, refs: [], warnings: warnings)
    }
}
