import Foundation
import AllnighterCore

/// S01c (RLR-L8): the legacy-journal policy is **MAP** — every on-disk
/// `RunStatus` value present maps unambiguously to `RunLifecycle`, so a
/// readable journal is never quarantined. The one invention risk this guards
/// against is an unknown/legacy `status` raw string, which must surface as
/// `JOURNAL_CORRUPT` rather than being silently treated as "no run" or
/// coerced into a made-up status.
public enum RunJournalReadError: Error, Sendable, Equatable {
    case corrupt(runId: String, detail: String)
}

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
    ///
    /// `endReason` is never inferred here (PO-S01 v2). The actor that ends the run
    /// stamps it, or leaves it nil/`unknown`.
    @discardableResult
    public func save(_ run: TeamRun, models: [Model], forceArtifacts: Bool = false) throws -> URL {
        let directory = rootDirectory.appendingPathComponent("run_\(run.id)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let run = run
        let runURL = directory.appendingPathComponent("run.json")
        if run.status.isTerminal {
            // Terminal: publish the terminal state, then drop ownership markers.
            // Never clobber an existing terminal status from a concurrent reconcile —
            // callers that need atomic terminal write use `reconcileRun` / cancel.
            try CoreJSON.encode(run).write(to: runURL, options: .atomic)
            try? FileManager.default.removeItem(at: ProcessOwnership.ownerURL(in: directory))
            try? FileManager.default.removeItem(at: ProcessOwnership.legacyOwnerURL(in: directory))
            try? FileManager.default.removeItem(at: ProcessOwnership.heartbeatURL(in: directory))
            try? FileManager.default.removeItem(at: ProcessOwnership.legacyHeartbeatURL(in: directory))
            try? FileManager.default.removeItem(at: ProcessOwnership.stageLeaseURL(in: directory))
        } else {
            // Non-terminal owner stamp (PO-S01 v2):
            // - Preserve an identity-alive detached runner (self-owning async path).
            //   Progress saves from the runner process must NOT demote it to
            //   inProcess/no-pgid or cancel/reconcile lose group-kill.
            // - Otherwise stamp current process as inProcess (Mac app, sync,
            //   unit tests). kind=inProcess, no pgid — never PG-killed.
            let existing = ProcessOwnership.readOwnerIdentity(in: directory)
            let preserveDetached =
                existing?.kind == .detachedRunner
                && existing.map { ProcessOwnership.isIdentityAlive($0) } == true
            if !preserveDetached {
                if let identity = ProcessOwnership.OwnerIdentity.current(kind: .inProcess) {
                    try ProcessOwnership.writeOwnerIdentity(identity, in: directory)
                }
            }
            // RLR-S03a: no per-save heartbeat floor touch. `heartbeat.json` is
            // retired as truth — durable activity lives on `run.json`
            // (`lastActivityAt`), advanced only by L6 events (RLR-L6). A per-save
            // floor touch is exactly the banned per-tick write that let
            // `touchedAt` advance while `sequence` stayed frozen at 0.
            try CoreJSON.encode(run).write(to: runURL, options: .atomic)
        }

        // Progress fast path: a running team's intermediate save writes only the truth
        // (run.json + owner identity above), not every derived artifact. The full
        // inspectable artifact set is (re)built on the terminal save.
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
            let durationMs, queueMs, ttftMs, gateWaitMs, exitCode: Int?
            let errorKind, errorReason: String?
            let spawnDiagnostics: WorkerSpawnDiagnostics?
        }

        for worker in run.workers {
            let stem = RunArtifactRef.safeStem(worker.id)
            let answer = run.workerAnswer(workerId: worker.id)

            let meta = WorkerMetadata(
                workerId: worker.id, modelId: worker.modelId,
                skillId: worker.skillId, skillName: worker.skillName,
                purpose: worker.purpose?.rawValue,
                status: (answer?.result.status ?? .queued).rawValue,
                startedAt: answer?.result.timing.startedAt, finishedAt: answer?.result.timing.finishedAt,
                durationMs: answer?.result.timing.durationMs, queueMs: answer?.queueMs, ttftMs: answer?.result.timing.ttftMs,
                gateWaitMs: answer?.result.timing.gateWaitMs,
                exitCode: answer?.result.exitCode,
                errorKind: answer?.result.errorKind?.rawValue, errorReason: answer?.result.errorReason,
                spawnDiagnostics: answer?.result.spawnDiagnostics)
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

    /// Loads one run by id. **Reads never kill** (PO-S01 v2): may project what
    /// reconcile WOULD decide (identity-dead → interrupted) but never signals,
    /// never writes. Explicit reconcile paths own kill + terminal write-back.
    ///
    /// Swallows both "no run.json" and "run.json failed to decode" to `nil` —
    /// unchanged behavior for the many callers that only care whether a usable
    /// run exists. Callers that must distinguish "never existed" from "existed
    /// but is corrupt" (RLR-L8 `JOURNAL_CORRUPT`) use `loadRawResult` instead.
    public func load(runId: String) -> TeamRun? {
        let directory = rootDirectory.appendingPathComponent("run_\(runId)", isDirectory: true)
        guard let run = loadRaw(runId: runId) else { return nil }
        return projectIfOrphaned(run, directory: directory)
    }

    /// Raw journal without orphan projection (runner claim path). See `load`'s
    /// doc: swallows missing-vs-corrupt to `nil`; use `loadRawResult` to tell
    /// them apart.
    public func loadRaw(runId: String) -> TeamRun? {
        switch loadRawResult(runId: runId) {
        case .success(let run): return run
        case .failure: return nil
        }
    }

    /// Distinguishes "no run.json on disk for this id" (`.success(nil)`, the
    /// `RUN_NOT_FOUND` case) from "an EXISTING run.json failed to decode"
    /// (`.failure(.corrupt)`, the `JOURNAL_CORRUPT` case — RLR-L8, S01c). The
    /// only decode-time invention risk is an unknown/legacy `status` raw
    /// string; every on-disk value present today maps unambiguously via
    /// `RunStatus.lifecycle`, so this guard only ever fires for genuinely
    /// unmappable journals — never a silent coercion, never a bare "no run".
    public func loadRawResult(runId: String) -> Result<TeamRun?, RunJournalReadError> {
        let directory = rootDirectory.appendingPathComponent("run_\(runId)", isDirectory: true)
        guard let data = try? Data(contentsOf: directory.appendingPathComponent("run.json")) else {
            return .success(nil)
        }
        do {
            return .success(try CoreJSON.decode(TeamRun.self, from: data))
        } catch {
            return .failure(.corrupt(runId: runId, detail: String(describing: error)))
        }
    }

    /// Lists saved runs, newest first. Read-only projection (never kills).
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
                return projectIfOrphaned(run, directory: dir)
            }
            .sorted { $0.createdAt > $1.createdAt }
    }

    // MARK: - Orphan projection + explicit reconcile (PO-S01 v2)

    /// Read-only: if the run is reclaimable under the F2 liveness lease
    /// (written-then-dead owner, or unowned past the stage lease), project
    /// `interrupted` + `reconciledOrphan` without writing or signalling.
    public func projectIfOrphaned(_ run: TeamRun, directory: URL) -> TeamRun {
        guard !run.status.isTerminal else { return run }
        guard ProcessOwnership.isReclaimable(in: directory, runCreatedAt: run.createdAt) else { return run }
        var projected = run
        projected.status = .interrupted
        projected.endReason = .reconciledOrphan
        return projected
    }

    /// True when a non-terminal run is reclaimable under the F2 liveness lease.
    public func wouldReconcile(runId: String) -> Bool {
        let directory = rootDirectory.appendingPathComponent("run_\(runId)", isDirectory: true)
        guard let raw = loadRaw(runId: runId), !raw.status.isTerminal else { return false }
        return ProcessOwnership.isReclaimable(in: directory, runCreatedAt: raw.createdAt)
    }

    /// Explicit reconcile: under per-run flock, identity-dead → PG-kill recorded
    /// pgid (if any), one atomic terminal write, never clobber existing terminal.
    /// Returns the run and whether this call performed a new reap.
    @discardableResult
    public func reconcileRun(runId: String, models: [Model] = []) -> TeamRun? {
        reconcileRunDetailed(runId: runId, models: models)?.run
    }

    public struct ReconcileResult: Sendable {
        public var run: TeamRun
        public var reaped: Bool
    }

    @discardableResult
    public func reconcileRunDetailed(runId: String, models: [Model] = []) -> ReconcileResult? {
        let directory = rootDirectory.appendingPathComponent("run_\(runId)", isDirectory: true)
        return ProcessOwnership.withRunLock(in: directory) {
            guard let data = try? Data(contentsOf: directory.appendingPathComponent("run.json")),
                  var run = try? CoreJSON.decode(TeamRun.self, from: data) else { return nil }
            // Never clobber an existing terminal status.
            if run.status.isTerminal {
                return ReconcileResult(run: run, reaped: false)
            }
            // F2: reap only on positive dead-proof under the liveness lease —
            // never a staged run, never a live owner.
            guard ProcessOwnership.isReclaimable(in: directory, runCreatedAt: run.createdAt) else {
                return ReconcileResult(run: run, reaped: false)
            }

            // PG-kill recorded pgid only when identity rules allow (never in-process).
            _ = ProcessOwnership.terminateRecordedOwnerIfSafe(in: directory)

            run.status = .interrupted
            run.endReason = .reconciledOrphan
            // Single atomic terminal write via save (clears markers).
            _ = try? save(run, models: models)
            return ReconcileResult(run: run, reaped: true)
        }
    }

    /// Sweep non-terminal runs under this store (doctor / `team reconcile`).
    /// Returns only runs this call newly reaped.
    ///
    /// `scopeRoot` (Concurrent Invocation Isolation F1/F3): when non-nil, only
    /// runs whose `repoRoot` canonicalizes to the caller's project root are
    /// eligible. Fail closed — a run whose root can't be resolved is skipped,
    /// never swept. `nil` is the explicit machine-wide fleet sweep.
    @discardableResult
    public func reconcileAll(models: [Model] = [], scopeRoot: String? = nil) -> [TeamRun] {
        guard let entries = try? FileManager.default.contentsOfDirectory(
            at: rootDirectory,
            includingPropertiesForKeys: nil
        ) else {
            return []
        }
        var results: [TeamRun] = []
        for dir in entries where dir.lastPathComponent.hasPrefix("run_") {
            let id = String(dir.lastPathComponent.dropFirst("run_".count))
            if let scopeRoot,
               !ProjectScope.matches(scopeRoot: scopeRoot, recordRoot: loadRaw(runId: id)?.repoRoot) {
                continue
            }
            if let detail = reconcileRunDetailed(runId: id, models: models), detail.reaped {
                results.append(detail.run)
            }
        }
        return results
    }

    /// True when `pid` names a live process. Shared with `ProcessOwnership`.
    public static func processAlive(_ pid: Int32) -> Bool {
        ProcessOwnership.processAlive(pid)
    }

    /// RLR-S03a: minimal activity-only journal write. Re-reads the freshest
    /// `run.json`, stamps `lastActivityAt`/`lastActivityKind`, and atomic-writes
    /// `run.json` ONLY — no derived artifacts, no owner/heartbeat markers. Used
    /// for the coalesced mid-stream flush of streaming activity (message /
    /// stdout / stderr); transition activity rides the coordinator's persist
    /// stamp instead. Guards on terminal state so a late flush can never
    /// resurrect or clobber a settled run.
    public func stampActivity(runId: String, at: Date, kind: RunActivityKind) {
        let directory = rootDirectory.appendingPathComponent("run_\(runId)", isDirectory: true)
        let runURL = directory.appendingPathComponent("run.json")
        guard let data = try? Data(contentsOf: runURL),
              var run = try? CoreJSON.decode(TeamRun.self, from: data),
              !run.status.isTerminal else { return }
        run.lastActivityAt = at
        run.lastActivityKind = kind
        try? CoreJSON.encode(run).write(to: runURL, options: .atomic)
    }
}

/// RLR-S03a: the one durable-activity projection wiring. Classifies a `RunEvent`
/// (`RunActivity.activityKind`), advances the in-memory recorder, and — only for
/// streaming kinds (message/stdout/stderr/tool) — performs the coalesced
/// `run.json` flush. Transition kinds (child/exit) ride the coordinator's
/// persist stamp (`RunActivityRecorder.stamp`), so the two write paths never
/// target `run.json` concurrently and an `.exit` can never resurrect a terminal
/// run. Shared by the async runner and the sync `alln run` emit seam.
public enum RunActivityJournalProjection {
    public static func observe(
        _ event: RunEvent, runId: String, store: RunStore, recorder: RunActivityRecorder
    ) {
        guard let kind = RunActivity.activityKind(for: event) else { return }
        let shouldFlush = recorder.note(runId: runId, kind: kind, at: event.ts)
        guard shouldFlush else { return }
        switch kind {
        case .message, .stdout, .stderr, .tool:
            store.stampActivity(runId: runId, at: event.ts, kind: kind)
        case .child, .exit:
            break // rides the persist stamp — see doc above
        }
    }
}
