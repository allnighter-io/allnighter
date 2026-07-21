import Foundation
import AllnighterCore
#if canImport(CryptoKit)
import CryptoKit
#else
import Crypto
#endif

/// Canonical attachment bytes and indexes under `thread_<id>/draft_attachments/`
/// and `thread_<id>/attachments/`. All writes are atomic (temp + rename).
public struct ThreadAttachmentStore: Sendable {
    public let threadDirectory: URL
    public var policy: AttachmentPolicy
    public var ingestor: AttachmentIngestor

    public init(threadDirectory: URL, policy: AttachmentPolicy = .default) {
        self.threadDirectory = threadDirectory
        self.policy = policy
        self.ingestor = AttachmentIngestor(policy: policy)
    }

    public var lockURL: URL { threadDirectory.appendingPathComponent(".lock") }
    public var draftDirectory: URL { threadDirectory.appendingPathComponent("draft_attachments", isDirectory: true) }
    public var attachmentsDirectory: URL { threadDirectory.appendingPathComponent("attachments", isDirectory: true) }
    public var draftIndexURL: URL { draftDirectory.appendingPathComponent("draft_index.json") }
    public var attachmentIndexURL: URL { attachmentsDirectory.appendingPathComponent("attachments.json") }

    // MARK: - Draft index

    public func loadDraftIndex() -> DraftAttachmentIndex {
        guard let data = try? Data(contentsOf: draftIndexURL),
              let index = try? CoreJSON.decode(DraftAttachmentIndex.self, from: data) else {
            return DraftAttachmentIndex()
        }
        return index
    }

    @discardableResult
    public func saveDraftIndex(_ index: DraftAttachmentIndex) throws -> URL {
        try FileManager.default.createDirectory(at: draftDirectory, withIntermediateDirectories: true)
        return try atomicWrite(CoreJSON.encode(index), to: draftIndexURL)
    }

    // MARK: - Attachment index

    public func loadAttachmentIndex() -> AttachmentIndex {
        guard let data = try? Data(contentsOf: attachmentIndexURL),
              let index = try? CoreJSON.decode(AttachmentIndex.self, from: data) else {
            return AttachmentIndex()
        }
        return index
    }

    @discardableResult
    public func saveAttachmentIndex(_ index: AttachmentIndex) throws -> URL {
        try FileManager.default.createDirectory(at: attachmentsDirectory, withIntermediateDirectories: true)
        return try atomicWrite(CoreJSON.encode(index), to: attachmentIndexURL)
    }

    // MARK: - Ingest draft

    /// Ingest source bytes into a new draft with the next `sequence`.
    @discardableResult
    public func ingestDraft(
        data: Data,
        threadId: String,
        sourceKind: AttachmentSourceKind,
        declaredMIME: String? = nil,
        originalName: String? = nil,
        draftId: String,
        now: Date
    ) throws -> DraftAttachmentRef {
        var index = loadDraftIndex()
        if index.drafts.count >= policy.maxCount { throw AttachmentError.tooMany }

        let ingested = try ingestor.ingest(
            data: data, declaredMIME: declaredMIME, sourceKind: sourceKind, originalName: originalName
        )
        let sequence = index.nextSequence
        index.nextSequence += 1

        try FileManager.default.createDirectory(at: draftDirectory, withIntermediateDirectories: true)
        let pngURL = draftDirectory.appendingPathComponent("\(draftId).png")
        try atomicWrite(ingested.pngData, to: pngURL)

        let ref = DraftAttachmentRef(draftId: draftId, sequence: sequence, status: .ready)
        index.drafts.append(ref)
        try saveDraftIndex(index)
        _ = threadId // reserved for TurnAttachment on promote
        _ = now
        return ref
    }

    /// Ingest from a frozen temp file (CLI law §8).
    @discardableResult
    public func ingestDraft(
        frozenFileURL: URL,
        threadId: String,
        sourceKind: AttachmentSourceKind,
        draftId: String,
        now: Date
    ) throws -> DraftAttachmentRef {
        let data = try Data(contentsOf: frozenFileURL)
        return try ingestDraft(
            data: data, threadId: threadId, sourceKind: sourceKind,
            originalName: frozenFileURL.lastPathComponent, draftId: draftId, now: now
        )
    }

    // MARK: - Promote drafts → canonical attachments

    /// Promote ready drafts in sequence order. Returns committed attachments and refs.
    public func promoteDrafts(
        draftIds: [String],
        threadId: String,
        now: Date
    ) throws -> (attachments: [TurnAttachment], refs: [TurnAttachmentRef]) {
        var draftIndex = loadDraftIndex()
        let selected = draftIds.compactMap { id in draftIndex.drafts.first { $0.draftId == id } }
        guard selected.count == draftIds.count else {
            throw AttachmentError.attachmentNotFound(draftIds.first { id in !draftIndex.drafts.contains { $0.draftId == id } } ?? "?")
        }
        for draft in selected where draft.status != .ready {
            throw AttachmentError.draftNotReady(draft.draftId)
        }

        var attachmentIndex = loadAttachmentIndex()
        if attachmentIndex.attachments.count + selected.count > policy.maxCount {
            throw AttachmentError.tooMany
        }

        let ordered = selected.sorted { $0.sequence < $1.sequence }
        var committed: [TurnAttachment] = []
        var refs: [TurnAttachmentRef] = []

        try FileManager.default.createDirectory(at: attachmentsDirectory, withIntermediateDirectories: true)

        for draft in ordered {
            let draftPNG = draftDirectory.appendingPathComponent("\(draft.draftId).png")
            let data = try Data(contentsOf: draftPNG)
            let ingested = try ingestor.ingest(
                data: data, declaredMIME: "image/png", sourceKind: .paste, originalName: draft.draftId
            )

            let attachmentId = draft.draftId
            let storagePath = "attachments/\(attachmentId).png"
            let destURL = attachmentsDirectory.appendingPathComponent("\(attachmentId).png")
            try atomicWrite(ingested.pngData, to: destURL)

            let record = TurnAttachment(
                id: attachmentId,
                threadId: threadId,
                createdAt: now,
                storagePath: storagePath,
                mimeType: ingested.mimeType,
                byteSize: ingested.byteSize,
                storedSha256: ingested.storedSha256,
                sourceSha256: ingested.sourceSha256,
                originalWidth: ingested.originalWidth,
                originalHeight: ingested.originalHeight,
                storedWidth: ingested.storedWidth,
                storedHeight: ingested.storedHeight,
                originalName: nil,
                sourceKind: .paste,
                wasDownscaled: ingested.wasDownscaled
            )
            attachmentIndex.attachments.append(record)
            refs.append(TurnAttachmentRef(attachmentId: attachmentId, sequence: draft.sequence))
            committed.append(record)
            try? FileManager.default.removeItem(at: draftPNG)
        }

        draftIndex.drafts.removeAll { draftIds.contains($0.draftId) }
        try saveDraftIndex(draftIndex)
        try saveAttachmentIndex(attachmentIndex)
        return (committed, refs)
    }

    /// Commit pre-ingested PNG bytes directly (CLI/MCP frozen path).
    @discardableResult
    public func commitIngested(
        ingested: IngestedAttachment,
        attachmentId: String,
        threadId: String,
        sourceKind: AttachmentSourceKind,
        sequence: Int,
        originalName: String?,
        now: Date
    ) throws -> (TurnAttachment, TurnAttachmentRef) {
        var attachmentIndex = loadAttachmentIndex()
        if attachmentIndex.attachments.count >= policy.maxCount { throw AttachmentError.tooMany }

        try FileManager.default.createDirectory(at: attachmentsDirectory, withIntermediateDirectories: true)
        let storagePath = "attachments/\(attachmentId).png"
        let destURL = attachmentsDirectory.appendingPathComponent("\(attachmentId).png")
        try atomicWrite(ingested.pngData, to: destURL)

        let record = TurnAttachment(
            id: attachmentId,
            threadId: threadId,
            createdAt: now,
            storagePath: storagePath,
            mimeType: ingested.mimeType,
            byteSize: ingested.byteSize,
            storedSha256: ingested.storedSha256,
            sourceSha256: ingested.sourceSha256,
            originalWidth: ingested.originalWidth,
            originalHeight: ingested.originalHeight,
            storedWidth: ingested.storedWidth,
            storedHeight: ingested.storedHeight,
            originalName: originalName,
            sourceKind: sourceKind,
            wasDownscaled: ingested.wasDownscaled
        )
        attachmentIndex.attachments.append(record)
        try saveAttachmentIndex(attachmentIndex)
        let ref = TurnAttachmentRef(attachmentId: attachmentId, sequence: sequence)
        return (record, ref)
    }

    // MARK: - Lookup and validation

    public func attachment(for id: String) -> TurnAttachment? {
        loadAttachmentIndex().attachments.first { $0.id == id }
    }

    public func canonicalURL(for attachment: TurnAttachment) -> URL {
        attachmentsDirectory.appendingPathComponent("\(attachment.id).png")
    }

    public func verifyHash(for attachment: TurnAttachment) throws {
        let url = canonicalURL(for: attachment)
        let data = try Data(contentsOf: url)
        let hash = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        guard hash == attachment.storedSha256 else { throw AttachmentError.hashMismatch }
    }

    public func verifyHashes(for attachments: [TurnAttachment]) throws {
        for attachment in attachments { try verifyHash(for: attachment) }
    }

    // MARK: - Orphan recovery

    /// Reconcile index entries with on-disk PNG files. Removes index rows whose
    /// bytes are missing; drops unindexed PNG orphans from the attachments folder.
    @discardableResult
    public func recoverOrphans() throws -> (removedIndexRows: Int, removedFiles: Int) {
        var index = loadAttachmentIndex()
        var removedRows = 0
        var removedFiles = 0

        index.attachments.removeAll { attachment in
            let url = canonicalURL(for: attachment)
            let exists = FileManager.default.fileExists(atPath: url.path)
            if !exists { removedRows += 1 }
            return !exists
        }

        if let files = try? FileManager.default.contentsOfDirectory(at: attachmentsDirectory, includingPropertiesForKeys: nil) {
            let indexed = Set(index.attachments.map(\.id))
            for file in files where file.pathExtension == "png" {
                let id = file.deletingPathExtension().lastPathComponent
                if !indexed.contains(id) {
                    try? FileManager.default.removeItem(at: file)
                    removedFiles += 1
                }
            }
        }

        try saveAttachmentIndex(index)
        return (removedRows, removedFiles)
    }

    // MARK: - Atomic write helper

    @discardableResult
    private func atomicWrite(_ data: Data, to url: URL) throws -> URL {
        try data.write(to: url, options: .atomic)
        return url
    }
}
