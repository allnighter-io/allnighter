import Foundation
import AllnighterCore

/// Resolves `TurnAttachmentRef` rows through `ThreadAttachmentStore` for CLI, MCP,
/// and Mac timeline presenters.
public enum ThreadAttachmentResolver {
    public static func resolve(
        refs: [TurnAttachmentRef],
        store: ThreadAttachmentStore
    ) -> [ResolvedThreadAttachment] {
        refs.sorted { $0.sequence < $1.sequence }.map { resolveOne($0, store: store) }
    }

    public static func project(
        thread: WorkThread,
        threadDirectory: URL,
        contractVersion: String
    ) -> ThreadGetResponse {
        let store = ThreadAttachmentStore(threadDirectory: threadDirectory)
        let turns = thread.turns.map { turn in
            ThreadTurnProjection(
                turn: turn,
                resolvedAttachments: resolve(refs: turn.attachmentRefs, store: store)
            )
        }
        return ThreadGetResponse(thread: thread, turns: turns, contractVersion: contractVersion)
    }

    public static func attachmentGet(
        threadId: String,
        attachmentId: String,
        threadDirectory: URL
    ) -> ThreadAttachmentGetResponse? {
        let store = ThreadAttachmentStore(threadDirectory: threadDirectory)
        guard let attachment = store.attachment(for: attachmentId) else { return nil }
        let resolved = resolveOne(
            TurnAttachmentRef(attachmentId: attachmentId, sequence: 0),
            store: store,
            known: attachment
        )
        return ThreadAttachmentGetResponse(resolved: resolved, threadId: threadId)
    }

    private static func resolveOne(
        _ ref: TurnAttachmentRef,
        store: ThreadAttachmentStore,
        known: TurnAttachment? = nil
    ) -> ResolvedThreadAttachment {
        guard let attachment = known ?? store.attachment(for: ref.attachmentId) else {
            return ResolvedThreadAttachment(
                attachmentId: ref.attachmentId,
                sequence: ref.sequence,
                canonicalPath: "",
                storedSha256: "",
                mimeType: "image/png",
                sourceKind: .paste,
                byteSize: 0,
                missing: true,
                error: "ATTACHMENT_NOT_FOUND"
            )
        }

        let path = store.canonicalURL(for: attachment).path
        guard FileManager.default.fileExists(atPath: path) else {
            return row(attachment, ref: ref, path: path, missing: true, error: "ATTACHMENT_BYTES_MISSING")
        }
        do {
            try store.verifyHash(for: attachment)
        } catch {
            return row(attachment, ref: ref, path: path, missing: true, error: "ATTACHMENT_HASH_MISMATCH")
        }
        return row(attachment, ref: ref, path: path, missing: false, error: nil)
    }

    private static func row(
        _ attachment: TurnAttachment,
        ref: TurnAttachmentRef,
        path: String,
        missing: Bool,
        error: String?
    ) -> ResolvedThreadAttachment {
        ResolvedThreadAttachment(
            attachmentId: ref.attachmentId,
            sequence: ref.sequence,
            canonicalPath: path,
            storedSha256: attachment.storedSha256,
            mimeType: attachment.mimeType,
            sourceKind: attachment.sourceKind,
            byteSize: attachment.byteSize,
            storedWidth: attachment.storedWidth,
            storedHeight: attachment.storedHeight,
            originalName: attachment.originalName,
            missing: missing,
            error: error
        )
    }
}
