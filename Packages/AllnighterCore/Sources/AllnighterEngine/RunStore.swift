import Foundation
import AllnighterCore

/// Persists runs to disk as a folder per run under Application Support. Flat
/// files now (Core models are `Codable`); GRDB is the documented growth path
/// when history/query needs exceed files.
public struct RunStore: Sendable {
    public let rootDirectory: URL

    public init(rootDirectory: URL? = nil) {
        self.rootDirectory = rootDirectory ?? AllnighterPaths.runs
    }

    /// The run's folder, created if needed.
    @discardableResult
    public func runDirectory(forRunId runId: String) throws -> URL {
        let directory = rootDirectory.appendingPathComponent("run_\(runId)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    /// Persist a run. `forceArtifacts` regenerates the derived markdown/artifact set even
    /// for a non-terminal run (e.g. a stage boundary); by default the artifacts are
    /// regenerated only on TERMINAL saves — a running team's progress save (where only
    /// answer text grew) writes just run.json + the liveness marker, not every artifact
    /// (PERF-S05 progress fast path). The artifacts are the inspectable terminal receipt;
    /// run.json stays the truth throughout.
    @discardableResult
    public func save(_ run: TeamRun, models: [Model], forceArtifacts: Bool = false) throws -> URL {
        let directory = rootDirectory.appendingPathComponent("run_\(run.id)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        // Concurrency: a background coordinator saves progress while another
        // caller (cancel/status) reads. All state files are written ATOMICALLY
        // (temp + rename) so a reader never sees a torn/partial file, and the
        // liveness marker + run.json are ordered so a reader can never see a live
        // run.json without its owner.pid (which would misfire orphan recovery and
        // flip a running run to `.interrupted`).
        let runURL = directory.appendingPathComponent("run.json")
        let ownerURL = directory.appendingPathComponent("owner.pid")
        if run.status.isTerminal {
            // Terminal: publish the terminal state, then drop the marker. Readers
            // see a terminal run and skip the orphan check entirely.
            try CoreJSON.encode(run).write(to: runURL, options: .atomic)
            try? FileManager.default.removeItem(at: ownerURL)
        } else {
            // Non-terminal: write the marker FIRST so that once this run.json is
            // visible, a complete owner.pid is guaranteed already present.
            try Data("\(RunStore.currentPID)".utf8).write(to: ownerURL, options: .atomic)
            try CoreJSON.encode(run).write(to: runURL, options: .atomic)
        }

        // Progress fast path: a running team's intermediate save writes only the truth
        // (run.json + owner.pid above), not every derived artifact. The full inspectable
        // artifact set is (re)built on the terminal save.
        guard run.status.isTerminal || forceArtifacts else { return directory }

        // Derived artifacts (regenerated from run.json truth on each terminal save).
        let bundle = RunMarkdown.bundle(run, models: models)
        try Data(bundle.utf8).write(to: directory.appendingPathComponent("bundle.md"))

        let analysis = RunMarkdown.analysis(run)
        if !analysis.isEmpty {
            try Data(analysis.utf8).write(to: directory.appendingPathComponent("analysis.md"))
        }

        if let plan = run.plan, !plan.isEmpty {
            try Data(plan.utf8).write(to: directory.appendingPathComponent("master_plan.md"))
        }

        // RB artifacts, all derived from run.json stages.
        for review in RunMarkdown.latestReviews(run) where review.status == .done {
            let lensId = review.payload?.review?.lensId ?? review.promptProfileId ?? review.id
            if let md = review.payload?.markdown {
                try Data(md.utf8).write(to: directory.appendingPathComponent("review_\(lensId).md"))
            }
        }
        let finalSpec = RunMarkdown.finalSpec(run)
        if !finalSpec.isEmpty {
            try Data(finalSpec.utf8).write(to: directory.appendingPathComponent("final_spec.md"))
        }

        try writeWorkerArtifacts(run, in: directory)
        try writeStageArtifacts(run, in: directory)
        try writeReturnArtifacts(run, in: directory)
        return directory
    }

    /// F-S03: when a Signal run produced a parseable typed insight, persist it as
    /// `return/insight.json` so agents can read structure without re-parsing the
    /// markdown. Derived from run.json on each save.
    private func writeReturnArtifacts(_ run: TeamRun, in directory: URL) throws {
        guard run.outputKind == .insight,
              let insight = SignalInsightParser.parse(fromWriterOutput: run.plan) else { return }
        let returnDir = directory.appendingPathComponent("return", isDirectory: true)
        try FileManager.default.createDirectory(at: returnDir, withIntermediateDirectories: true)
        try CoreJSON.encode(insight).write(
            to: returnDir.appendingPathComponent("insight.json"), options: .atomic)
    }

    /// F-S02: every stage that produced markdown (analysis/plan/review/final spec/
    /// return review) becomes a durable `stages/<id>.<purpose>.md` +
    /// `<id>.metadata.json`, so the inspectable path is not only `bundle.md`. Board
    /// stages are structured (options/chosen), not markdown, and stay in run.json.
    private func writeStageArtifacts(_ run: TeamRun, in directory: URL) throws {
        let withMarkdown = run.stages.filter { $0.payload?.markdown != nil }
        guard !withMarkdown.isEmpty else { return }
        let stagesDir = directory.appendingPathComponent("stages", isDirectory: true)
        try FileManager.default.createDirectory(at: stagesDir, withIntermediateDirectories: true)

        struct StageMetadata: Encodable {
            let stageId, purpose, status: String
            let producedByWorkerId: String?
            let startedAt, finishedAt: Date?
        }
        for stage in withMarkdown {
            guard let md = stage.payload?.markdown else { continue }
            let stem = RunArtifactRef.safeStem(stage.id)
            try Data(md.utf8).write(
                to: stagesDir.appendingPathComponent("\(stem).\(stage.purpose.rawValue).md"), options: .atomic)
            let meta = StageMetadata(
                stageId: stage.id, purpose: stage.purpose.rawValue, status: stage.status.rawValue,
                producedByWorkerId: stage.producedByWorkerId,
                startedAt: stage.startedAt, finishedAt: stage.finishedAt)
            try CoreJSON.encode(meta).write(
                to: stagesDir.appendingPathComponent("\(stem).metadata.json"), options: .atomic)
        }
    }

    /// F-S01: every worker's durable return is preserved as an inspectable artifact
    /// — `workers/<id>.answer.md` (when output exists), `workers/<id>.prompt.md`
    /// (local-only resolved prompt), and `workers/<id>.metadata.json` for EVERY
    /// worker including failed/skipped/cancelled (a failure is never hidden).
    /// Derived from run.json truth on each save; relative paths match
    /// `RunArtifactRef.safeStem` so the Floor projection resolves them.
    private func writeWorkerArtifacts(_ run: TeamRun, in directory: URL) throws {
        guard !run.workers.isEmpty else { return }
        let workersDir = directory.appendingPathComponent("workers", isDirectory: true)
        try FileManager.default.createDirectory(at: workersDir, withIntermediateDirectories: true)

        struct WorkerMetadata: Encodable {
            let workerId, modelId: String
            let skillId, skillName: String?
            let purpose: String?
            let status: String
            let startedAt, finishedAt: Date?
            let durationMs, queueMs, ttftMs, exitCode: Int?
            let errorKind, errorReason: String?
        }

        for worker in run.workers {
            let stem = RunArtifactRef.safeStem(worker.id)
            let answer = run.workerAnswer(workerId: worker.id)

            let meta = WorkerMetadata(
                workerId: worker.id, modelId: worker.modelId,
                skillId: worker.skillId, skillName: worker.skillName,
                purpose: worker.purpose?.rawValue,
                status: (answer?.status ?? .queued).rawValue,
                startedAt: answer?.startedAt, finishedAt: answer?.finishedAt,
                durationMs: answer?.durationMs, queueMs: answer?.queueMs, ttftMs: answer?.ttftMs,
                exitCode: answer?.exitCode,
                errorKind: answer?.errorKind?.rawValue, errorReason: answer?.errorReason)
            try CoreJSON.encode(meta).write(
                to: workersDir.appendingPathComponent("\(stem).metadata.json"), options: .atomic)

            if let output = answer?.output, answer?.hasAnswer == true {
                try Data(output.utf8).write(
                    to: workersDir.appendingPathComponent("\(stem).answer.md"), options: .atomic)
            }
            if let prompt = worker.resolvedWorkerPromptSnapshot, !prompt.isEmpty {
                try Data(prompt.utf8).write(
                    to: workersDir.appendingPathComponent("\(stem).prompt.md"), options: .atomic)
            }
        }
    }

    /// Loads one run by id, applying orphan recovery (a non-terminal run whose
    /// owning process is gone resolves to `interrupted` — never falsely `running`,
    /// never silently absent). Returns nil only when no `run.json` exists.
    public func load(runId: String) -> TeamRun? {
        let directory = rootDirectory.appendingPathComponent("run_\(runId)", isDirectory: true)
        guard let data = try? Data(contentsOf: directory.appendingPathComponent("run.json")),
              let run = try? CoreJSON.decode(TeamRun.self, from: data) else { return nil }
        return recovered(run, directory: directory)
    }

    /// Lists saved runs, newest first, with orphan recovery applied.
    public func list() -> [TeamRun] {
        guard let entries = try? FileManager.default.contentsOfDirectory(
            at: rootDirectory,
            includingPropertiesForKeys: nil
        ) else {
            return []
        }
        return entries
            .filter { $0.lastPathComponent.hasPrefix("run_") }
            .compactMap { dir -> TeamRun? in
                guard let run = try? CoreJSON.decode(TeamRun.self, from: Data(contentsOf: dir.appendingPathComponent("run.json"))) else { return nil }
                return recovered(run, directory: dir)
            }
            .sorted { $0.createdAt > $1.createdAt }
    }

    // MARK: - Orphan recovery

    /// Projects a non-terminal run to `interrupted` when its owning process is no
    /// longer alive (crash/orphan). A non-terminal run with a live owner pid is
    /// genuinely running and is returned unchanged. Pure: never writes on read.
    private func recovered(_ run: TeamRun, directory: URL) -> TeamRun {
        guard !run.status.isTerminal else { return run }
        if let pid = ownerPID(directory), RunStore.processAlive(pid) { return run }
        var orphan = run
        orphan.status = .interrupted
        return orphan
    }

    private func ownerPID(_ directory: URL) -> Int32? {
        guard let raw = try? String(contentsOf: directory.appendingPathComponent("owner.pid"), encoding: .utf8) else { return nil }
        return Int32(raw.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    private static var currentPID: Int32 { ProcessInfo.processInfo.processIdentifier }

    /// True when `pid` names a live process. `kill(pid, 0)` returns 0 when we can
    /// signal it, or fails with `EPERM` when it exists but we may not — both mean
    /// alive; `ESRCH` means gone.
    public static func processAlive(_ pid: Int32) -> Bool {
        guard pid > 0 else { return false }
        if kill(pid, 0) == 0 { return true }
        return errno == EPERM
    }
}
