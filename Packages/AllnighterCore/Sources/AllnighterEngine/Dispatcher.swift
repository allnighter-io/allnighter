import Foundation
import AllnighterCore

/// Builds an `ImplementationBrief` from a run and renders the brief + a
/// self-contained execution prompt.
public enum BriefBuilder {
    public static func build(run: CouncilRun, executionWorkerId: String, workingDirectory: String) -> ImplementationBrief? {
        let finalSpec = run.latestStage(.finalSpec)?.payload?.finalSpec
        let source: ImplementationBrief.SourceArtifact = finalSpec != nil ? .finalSpec : .masterPlan
        guard let spec = finalSpec?.markdown ?? run.masterPlan else { return nil }

        var summary = ""
        if let a = run.analysis {
            let consensus = a.consensus.prefix(5).map { "- \($0.statement)" }.joined(separator: "\n")
            let conflicts = a.contradictions.prefix(5).map { "- \($0.topic): \($0.recommendedResolution)" }.joined(separator: "\n")
            summary = ["## Consensus\n\(consensus)", conflicts.isEmpty ? "" : "## Resolved conflicts\n\(conflicts)"]
                .filter { !$0.isEmpty }.joined(separator: "\n\n")
        }
        return ImplementationBrief(
            sourceRunId: run.id, sourceArtifact: source,
            executionWorkerId: executionWorkerId, workingDirectory: workingDirectory,
            prompt: run.prompt, spec: spec, judgmentSummary: summary, decisions: finalSpec
        )
    }
}

/// Builds an `ImplementationBrief` from a chosen design option (Design2). The
/// executor restyles the EXISTING code to match the chosen image — our ICP is
/// redesign, not build-from-scratch. Carries the chosen image + the "before"
/// screenshot as absolute paths the agent reads in place (RB4 context-exclusion).
public enum DesignBriefBuilder {
    public static func build(
        run: CouncilRun,
        chosenSeatId: String,
        executionWorkerId: String,
        workingDirectory: String,
        runFolder: URL
    ) -> ImplementationBrief? {
        guard let board = run.latestStage(.board)?.payload?.board,
              let option = board.options.first(where: { $0.seatId == chosenSeatId }),
              option.hasImage, let imageRel = option.imagePath else { return nil }

        let imageAbs = runFolder.appendingPathComponent(imageRel).path
        let beforeAbs = board.screenshotPath.map { runFolder.appendingPathComponent($0).path }
        let persona = DesignPersonaLibrary.displayName(for: option.persona)
        let intent = "Adopt the \(persona) design direction shown in the chosen image. \(run.prompt)"

        return ImplementationBrief(
            sourceRunId: run.id, sourceArtifact: .designImage,
            executionWorkerId: executionWorkerId, workingDirectory: workingDirectory,
            prompt: run.prompt, spec: intent, judgmentSummary: "",
            designImagePath: imageAbs, beforeScreenshotPath: beforeAbs
        )
    }
}

public enum BriefMarkdown {
    public static func brief(_ b: ImplementationBrief) -> String {
        if b.isDesignBuild { return designBrief(b) }
        var lines = [
            "# Implementation Brief", "",
            "- Source run: \(b.sourceRunId)",
            "- Source artifact: \(b.sourceArtifact.rawValue)\(b.isLessReviewed ? " (less reviewed — built from the master plan, not a final spec)" : "")",
            "- Execution worker: \(b.executionWorkerId)",
            "- Working directory: \(b.workingDirectory)", "",
            "## Original prompt", "", b.prompt, ""
        ]
        if !b.judgmentSummary.isEmpty { lines.append(contentsOf: ["## Panel judgment", "", b.judgmentSummary, ""]) }
        lines.append(contentsOf: ["## Spec", "", b.spec, ""])
        if let d = b.decisions {
            if !d.reviewDecisions.isEmpty {
                lines.append("## Analysis decisions")
                lines.append(contentsOf: d.reviewDecisions.map { "- \($0.lensId): \($0.decision.rawValue.uppercased()) — \($0.reason)" })
                lines.append("")
            }
        }
        lines.append(contentsOf: ["## Direct-dispatch boundary", "", b.boundaryLabel, ""])
        return lines.joined(separator: "\n")
    }

    public static func executionPrompt(_ b: ImplementationBrief) -> String {
        if b.isDesignBuild { return designExecutionPrompt(b) }
        return """
        You are implementing the following spec in the working directory \(b.workingDirectory).

        \(b.boundaryLabel)

        # Original request
        \(b.prompt)

        # Specification\(b.isLessReviewed ? " (master plan — less reviewed)" : "")
        \(b.spec)

        Implement it. Run the spec's proof commands / Works Test to verify. Report what you changed and the proof results.
        """
    }

    // MARK: - Design build (Design2)

    static func designBrief(_ b: ImplementationBrief) -> String {
        var lines = [
            "# Design Build Brief", "",
            "- Source run: \(b.sourceRunId)",
            "- Source: chosen design image",
            "- Execution worker: \(b.executionWorkerId)",
            "- Working directory: \(b.workingDirectory)",
            "- Design image: \(b.designImagePath ?? "—")"
        ]
        if let before = b.beforeScreenshotPath { lines.append("- Before (original): \(before)") }
        lines.append(contentsOf: ["", "## Intent", "", b.spec, "",
                                  "## Direct-dispatch boundary", "", b.boundaryLabel, ""])
        return lines.joined(separator: "\n")
    }

    /// The design execution prompt: restyle the EXISTING code to match the chosen
    /// image (a look, not a spec). The agent reads the image by absolute path.
    static func designExecutionPrompt(_ b: ImplementationBrief) -> String {
        let before = b.beforeScreenshotPath.map {
            "The current screen (the \"before\") is at: \($0)\n"
        } ?? ""
        return """
        You are restyling an EXISTING screen in the working directory \(b.workingDirectory) to match a chosen design.

        \(b.boundaryLabel)

        # The design to match
        Look at the design image at: \(b.designImagePath ?? "")
        \(before)
        # What to do
        \(b.spec)

        This is a redesign, not a build-from-scratch. Find the existing component(s) for this screen in the working
        directory and MODIFY them to adopt the new look — reuse the existing components, data wiring, and the repo's
        styling system (e.g. its Tailwind/theme tokens). Treat the image as the visual target, not a literal spec:
        match the layout, hierarchy, spacing, and color direction; keep the screen's real content and behavior.
        Report which files you changed.
        """
    }
}

/// RB4: dispatches a brief to an executor CLI. Gated on a Doctor health check by
/// the caller; reveal-only writes artifacts without invoking. Judgment stays out:
/// this never creates worktrees/branches/commits. Context-exclusion holds because
/// run artifacts live under Application Support, never copied into the working dir.
public struct Dispatcher: Sendable {
    private let workerRunner: WorkerRunner
    private let idFactory: @Sendable () -> String
    private let now: @Sendable () -> Date
    private let transcriptCapBytes: Int

    public init(
        workerRunner: WorkerRunner,
        transcriptCapBytes: Int = 64_000,
        idFactory: @escaping @Sendable () -> String = { UUID().uuidString },
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.workerRunner = workerRunner
        self.transcriptCapBytes = transcriptCapBytes
        self.idFactory = idFactory
        self.now = now
    }

    /// Writes brief + execution prompt to `artifactsDir`, then either reveals
    /// (manual/unhealthy/opt-in) or invokes the worker, returning the dispatch
    /// `StageOutput` with an embedded `ExecutionReturn`.
    public func dispatch(
        brief: ImplementationBrief,
        worker: Worker,
        manifest: DriverManifest?,
        healthy: Bool,
        revealOnly: Bool,
        dispatchIndex: Int,
        artifactsDir: URL,
        dispatchTimeout: Duration = .seconds(600)
    ) async -> StageOutput {
        // Write artifacts (versioned to avoid collision on re-dispatch).
        try? FileManager.default.createDirectory(at: artifactsDir, withIntermediateDirectories: true)
        let index = String(format: "%02d", dispatchIndex)
        try? Data(BriefMarkdown.brief(brief).utf8).write(to: artifactsDir.appendingPathComponent("implementation_brief.md"))
        let execPrompt = BriefMarkdown.executionPrompt(brief)
        try? Data(execPrompt.utf8).write(to: artifactsDir.appendingPathComponent("execution_prompt_\(worker.id)_\(index).md"))

        let dirOK = isWritableDirectory(brief.workingDirectory)
        let canInvoke = !revealOnly && healthy && manifest?.kind == .headlessCLI && dirOK

        let started = now()
        if !canInvoke {
            let reason = revealOnly ? "reveal-only" : (!dirOK ? "working directory missing or not writable" : (!healthy ? "worker not healthy" : "manual worker"))
            let ret = ExecutionReturn(
                id: idFactory(), executionWorkerId: worker.id, workingDirectory: brief.workingDirectory,
                dispatchIndex: dispatchIndex, status: .reveal, transcriptExcerpt: reason, startedAt: started, finishedAt: now()
            )
            return dispatchStage(ret, worker: worker)
        }

        let outcome = await workerRunner.invoke(
            worker: worker, manifest: manifest!, prompt: execPrompt,
            workingDirectoryOverride: brief.workingDirectory, timeoutOverride: dispatchTimeout
        )
        let finished = now()
        let transcript = outcome.output ?? outcome.errorReason ?? ""
        let dispatchDir = artifactsDir.appendingPathComponent("dispatch_\(index)", isDirectory: true)
        try? FileManager.default.createDirectory(at: dispatchDir, withIntermediateDirectories: true)
        try? Data(transcript.utf8).write(to: dispatchDir.appendingPathComponent("transcript.txt"))

        let status: ExecutionStatus = {
            switch outcome.status {
            case .done: return .done
            case .timedOut: return .timedOut
            default: return .failed
            }
        }()
        let ret = ExecutionReturn(
            id: idFactory(), executionWorkerId: worker.id, workingDirectory: brief.workingDirectory,
            dispatchIndex: dispatchIndex, status: status, exitCode: outcome.exitCode,
            transcriptPath: dispatchDir.appendingPathComponent("transcript.txt").path,
            transcriptExcerpt: cap(transcript), startedAt: started, finishedAt: finished
        )
        return dispatchStage(ret, worker: worker)
    }

    private func dispatchStage(_ ret: ExecutionReturn, worker: Worker) -> StageOutput {
        StageOutput(
            id: idFactory(), purpose: .dispatch, producedByWorkerId: worker.id,
            status: ret.status == .reveal ? .skipped : (ret.status == .done ? .done : (ret.status == .timedOut ? .timedOut : .failed)),
            payload: .dispatch(ret), startedAt: ret.startedAt, finishedAt: ret.finishedAt
        )
    }

    private func isWritableDirectory(_ path: String) -> Bool {
        var isDir: ObjCBool = false
        let exists = FileManager.default.fileExists(atPath: path, isDirectory: &isDir)
        return exists && isDir.boolValue && FileManager.default.isWritableFile(atPath: path)
    }

    /// Head + tail cap with a marker, so a long coding session doesn't bloat the
    /// run or RB5's return-review input.
    private func cap(_ text: String) -> String {
        let bytes = Array(text.utf8)
        guard bytes.count > transcriptCapBytes else { return text }
        let half = transcriptCapBytes / 2
        let head = String(decoding: bytes.prefix(half), as: UTF8.self)
        let tail = String(decoding: bytes.suffix(half), as: UTF8.self)
        return head + "\n\n[… truncated \(bytes.count - transcriptCapBytes) bytes …]\n\n" + tail
    }
}
