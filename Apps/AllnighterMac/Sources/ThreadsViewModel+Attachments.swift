import AppKit
import Foundation
import AllnighterCore
import AllnighterEngine
import AgentOSTeam

@MainActor
extension ThreadsViewModel {
    // MARK: - Routing composer (Attachments & Desktop)

    func runDirectory(forRunId runId: String) -> URL? {
        try? runStore.runDirectory(forRunId: runId)
    }

    func resolvedAttachments(threadId: String, turn: ThreadTurn) -> [ResolvedThreadAttachment] {
        guard let dir = try? store.threadDirectory(forThreadId: threadId) else { return [] }
        let attachmentStore = ThreadAttachmentStore(threadDirectory: dir)
        return ThreadAttachmentResolver.resolve(refs: turn.attachmentRefs, store: attachmentStore)
    }

    struct HarvestedImages {
        var refs: [TurnAttachmentRef]
        /// The settled caption with captured paths stripped (nil when nothing to clean).
        var cleanedCaption: String?
    }

    /// Capture images a worker produced (referenced by path in its run output / answer /
    /// settled text) into the thread's canonical attachment store, returning refs to stamp
    /// on the settled turn plus the caption with those paths removed. Real bytes only — a
    /// path with no valid image behind it is skipped.
    func harvestWorkerImages(run: TeamRun, settledText: String?, reasoningText: String?, threadId: String) -> HarvestedImages {
        guard let dir = try? store.threadDirectory(forThreadId: threadId) else { return HarvestedImages(refs: []) }
        // Caption candidates in display priority: the settled turn text first (what the row
        // shows), then the worker answers, then any plan markdown. These are the only texts
        // the cleaned caption may be sourced from.
        var captionTexts: [String] = []
        if let t = settledText, !t.isEmpty { captionTexts.append(t) }
        for answer in run.answers where !(answer.output ?? "").isEmpty {
            captionTexts.append(answer.output ?? "")
        }
        for stage in run.stages where !(stage.payload?.markdown ?? "").isEmpty {
            captionTexts.append(stage.payload?.markdown ?? "")
        }
        // Scan texts also include the worker's reasoning: workers frequently name the image
        // they produced ONLY in their thinking ("The path is given: …/1.jpg") and leave the
        // final answer as a bare "Here's your image:". Reasoning is scanned for capture but
        // is never used as the displayed caption.
        var scanTexts = captionTexts
        if let r = reasoningText, !r.isEmpty { scanTexts.append(r) }
        let runDir = try? runStore.runDirectory(forRunId: run.id)
        let candidates = WorkerOutputImageHarvest.candidates(in: scanTexts, runDirectory: runDir)
        // Codex stores generated images only in its session rollout log (no file, no answer
        // path); locate that rollout by the thread's working dir + the answer's time window.
        let repoRoot = threads.first(where: { $0.id == threadId })?.workingDir
        let dataCandidates = WorkerOutputImageHarvest.codexRolloutDataCandidates(
            run: run, models: models, repoRoot: repoRoot)
        guard !candidates.isEmpty || !dataCandidates.isEmpty else { return HarvestedImages(refs: []) }

        let attachmentStore = ThreadAttachmentStore(threadDirectory: dir)
        var refs = WorkerOutputImageHarvest.commit(
            imageURLs: candidates.map(\.url),
            threadId: threadId,
            store: attachmentStore,
            startSequence: 0,
            idFactory: { UUID().uuidString },
            now: Date()
        )
        refs.append(contentsOf: WorkerOutputImageHarvest.commit(
            dataCandidates: dataCandidates,
            threadId: threadId,
            store: attachmentStore,
            startSequence: refs.count,
            idFactory: { UUID().uuidString },
            now: Date()
        ))
        guard !refs.isEmpty else { return HarvestedImages(refs: []) }

        // Clean the caption the row will show — the first text holding a captured path, else
        // the settled text. The row prefers `turn.text` when the turn carries captured images.
        guard !candidates.isEmpty else { return HarvestedImages(refs: refs) }
        let tokens = candidates.map(\.token)
        let base = captionTexts.first { text in tokens.contains { text.contains($0) } } ?? settledText ?? ""
        let cleaned = WorkerOutputImageHarvest.cleanedCaption(from: base, removing: tokens)
        return HarvestedImages(refs: refs, cleanedCaption: cleaned.isEmpty ? nil : cleaned)
    }

    func attachmentThumb(for resolved: ResolvedThreadAttachment) -> NSImage? {
        if let cached = attachmentThumbCache[resolved.attachmentId] { return cached }
        guard !resolved.missing else { return nil }
        guard let image = NSImage(contentsOfFile: resolved.canonicalPath) else { return nil }
        attachmentThumbCache[resolved.attachmentId] = image
        return image
    }

    func openAttachmentPath(_ path: String) {
        guard !path.isEmpty else { return }
        NSWorkspace.shared.open(URL(fileURLWithPath: path))
    }

    /// Reveal the canonical file in Finder (select it), so the user can move/rename/copy it.
    func revealAttachmentInFinder(_ path: String) {
        guard !path.isEmpty else { return }
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
    }

    /// Copy the image bytes to the pasteboard (paste straight into another app).
    func copyAttachmentImage(_ resolved: ResolvedThreadAttachment) {
        guard let image = attachmentThumb(for: resolved)
            ?? NSImage(contentsOfFile: resolved.canonicalPath) else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.writeObjects([image])
    }
}
