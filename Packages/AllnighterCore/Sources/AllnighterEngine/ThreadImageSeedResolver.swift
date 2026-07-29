import Foundation
import AllnighterCore

/// At most one reference image for design continuity on a chat send (v1).
public struct ThreadImageSeed: Sendable, Equatable {
    public enum Source: Sendable, Equatable {
        case existingAttachment(TurnAttachmentRef, TurnAttachment)
        case boardImage(runId: String, modelId: String, imageFileURL: URL)
    }

    public var source: Source

    public init(source: Source) {
        self.source = source
    }
}

/// Resolves the seed image for follow-up chat tweaks (prior worker image or picked board).
public struct ThreadImageSeedResolver: Sendable {
    private let runStore: RunStore

    public init(runStore: RunStore = RunStore()) {
        self.runStore = runStore
    }

    public func hasPriorImageContext(thread: WorkThread, attachmentStore: ThreadAttachmentStore) -> Bool {
        resolveSeed(thread: thread, attachmentStore: attachmentStore) != nil
    }

    public func resolveSeed(thread: WorkThread, attachmentStore: ThreadAttachmentStore) -> ThreadImageSeed? {
        if let existing = latestWorkerGeneratedRef(thread: thread, attachmentStore: attachmentStore) {
            return ThreadImageSeed(source: .existingAttachment(existing.ref, existing.attachment))
        }
        if let board = latestChosenBoardImage(thread: thread) {
            return ThreadImageSeed(source: .boardImage(
                runId: board.runId, modelId: board.modelId, imageFileURL: board.imageURL
            ))
        }
        return nil
    }

    private func latestWorkerGeneratedRef(
        thread: WorkThread,
        attachmentStore: ThreadAttachmentStore
    ) -> (ref: TurnAttachmentRef, attachment: TurnAttachment)? {
        let kinds: Set<ThreadTurnKind> = [.workerChat, .userDecision]
        for turn in thread.turns.reversed() where kinds.contains(turn.kind) {
            for ref in turn.attachmentRefs.sorted(by: { $0.sequence < $1.sequence }) {
                guard let attachment = attachmentStore.attachment(for: ref.attachmentId),
                      attachment.sourceKind == .workerGenerated else { continue }
                return (ref, attachment)
            }
        }
        return nil
    }

    private func latestChosenBoardImage(thread: WorkThread) -> (runId: String, modelId: String, imageURL: URL)? {
        for turn in thread.turns.reversed() where turn.kind == .designBoard {
            guard let runId = turn.runId,
                  let run = runStore.load(runId: runId),
                  let board = run.latestStage(.board)?.payload?.board,
                  let chosen = board.chosen,
                  let option = board.options.first(where: { $0.agentId == chosen.agentId }),
                  let relative = option.imagePath,
                  option.hasImage else { continue }
            guard let runDir = try? runStore.runDirectory(forRunId: runId) else { continue }
            let imageURL = runDir.appendingPathComponent(relative)
            guard WorkerImageCapture.isValidImage(at: imageURL) else { continue }
            return (runId, chosen.agentId, imageURL)
        }
        return nil
    }
}
