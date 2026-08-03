import AppKit
import Foundation
import AllnighterCore
import AllnighterEngine
import AgentOSTeam

@MainActor
extension ThreadsViewModel {
    // MARK: - Routing composer (Run execution & caching)

    func makeRunService() -> RunService {
        RunService(
            models: readyModels,
            registry: registry,
            runStore: runStore,
            commandRunner: commandRunner,
            writeLock: writeLock,
            invocations: AppSetupModel.invocations(from: toolStatuses)
        )
    }

    /// Unified run primitive — answer teams and mutating execution share one path.
    func runViaRunService(
        _ routing: ComposeRouting,
        toThreadId threadId: String,
        projectId: String?,
        repoRoot: String,
        context: String? = nil,
        deliveries: [IncludedAttachmentDelivery] = [],
        timing seedTiming: RunTimingReport = RunTimingReport()
    ) {
        var timing = seedTiming
        let preset = routing.team.flatMap { TeamCatalog.get($0) } ?? TeamCatalog.defaultRunTeam()
        guard let preset else {
            appendFailedRun("No team configured.", kind: .teamRun, toThreadId: threadId)
            return
        }

        let effort = EffortLevel(rawValue: routing.effort.rawValue) ?? preset.defaultEffort
        let turnKind: ThreadTurnKind = preset.mutating ? .mutatingRun : (routing.lane == .design ? .designBoard : .teamRun)
        let runId = UUID().uuidString
        let startedAt = Date()
        let resolvedModelId = effectiveModelId(for: routing, preset: preset)
        let turn = ThreadTurn(
            id: UUID().uuidString, threadId: threadId, kind: turnKind, status: .running,
            createdAt: startedAt, author: .worker,
            modelId: preset.mutating ? resolvedModelId : (routing.to.isEmpty ? nil : routing.to),
            runId: runId
        )
        guard (try? store.appendTurn(turn, toThreadId: threadId, now: startedAt)) != nil else { return }
        timing.stamp(RunTimingKey.threadWorkerTurnPersisted, at: startedAt)
        // Single-thread refresh so live deltas can land before the off-main full list returns.
        refreshPublishedThread(threadId)
        reload()

        let request = RunRequest(
            message: routing.text.trimmingCharacters(in: .whitespacesAndNewlines),
            repoRoot: repoRoot,
            // Worker_Session_Continuity: carry the visible thread so the run resumes this
            // thread's vendor CLI session per (source, model) instead of a fresh process.
            threadId: threadId,
            projectId: projectId,
            presetId: routing.team,
            pinnedModelId: routing.to.isEmpty ? nil : routing.to,
            effort: effort,
            lane: routing.lane.workLane,
            context: context,
            deliveries: deliveries,
            timing: timing
        )
        let service = makeRunService()
        let threadStore = store
        let turnId = turn.id
        let artifactContext = ArtifactProjector.Context(models: models)
        let teamQuestion = request.message
        let teamLabel = preset.displayName

        Task { @MainActor in
            let uiTiming = RunTimingAccumulator()
            // Consume live answer-delta events so the running turn shows streamed text
            // before the worker exits (mirrors the worker_chat streaming path).
            let (events, continuation) = AsyncStream<RunEvent>.makeStream()
            let consumer = Task { @MainActor in
                for await event in events {
                    if turnKind == .teamRun {
                        self.applyLiveArtifactEvent(
                            event, runId: runId, question: teamQuestion, teamLabel: teamLabel,
                            context: artifactContext)
                    }
                    let isAnswer = event.kind == RunEventKind.workerAnswerDelta
                    let isReasoning = event.kind == RunEventKind.workerReasoningDelta
                    guard isAnswer || isReasoning,
                          let text = event.payload["text"]?.stringValue else { continue }
                    // Stream live text into the in-memory turn (no per-delta list decode or
                    // full thread.json rewrite); a durable checkpoint is throttled inside.
                    let published = self.applyLiveDelta(
                        threadId: threadId, turnId: turnId, isAnswer: isAnswer, text: text,
                        truncated: isAnswer ? (event.payload["truncated"]?.boolValue ?? false) : nil)
                    if published {
                        await uiTiming.count(RunTimingKey.uiPublishCount)
                        await uiTiming.stampOnce(RunTimingKey.firstUIPublish)
                    }
                }
            }
            let result = await service.run(request, origin: .gui, runId: runId, events: continuation)
            await consumer.value
            liveCheckpointAt[turnId] = nil
            liveArtifactByRunId.removeValue(forKey: runId)

            // Seed settlement from the in-memory turn (freshest live text — the last delta
            // may post-date the last durable checkpoint), else the store, else the seed.
            var settled = threads.first(where: { $0.id == threadId })?.turn(id: turnId)
                ?? threadStore.get(threadId)?.turn(id: turnId) ?? turn
            settled.completedAt = Date()
            var settledRun: TeamRun?
            switch result {
            case .success(var run):
                // RLS-S01: a terminal run MUST settle to a terminal turn — never .running.
                settled.status = Self.settledStatus(forSuccessfulRun: run.status)
                if settled.modelId == nil, let modelId = run.answers.first?.modelId {
                    settled.modelId = modelId
                }
                if preset.mutating, let stage = run.stages.last(where: { $0.purpose == .plan }) {
                    settled.stageId = stage.id
                }
                // Capture any real image the worker produced (a path in its output) into the
                // thread's canonical attachment store, so the timeline shows a preview, and
                // strip the now-redundant path from the caption. Run-time copy of canonical
                // bytes — never the vendor path, never a faked thumb. Design boards are
                // skipped: their tile strip already owns the fan-out images.
                if turnKind != .designBoard {
                    let harvested = self.harvestWorkerImages(
                        run: run, settledText: settled.text,
                        reasoningText: settled.reasoningText, threadId: threadId)
                    if !harvested.refs.isEmpty {
                        settled.attachmentRefs += harvested.refs
                        if let caption = harvested.cleanedCaption { settled.text = caption }
                    }
                }
                settledRun = run
            case .failure(let error):
                settled.status = .failed
                settled.text = error.description
                settled.runId = nil
            }
            await uiTiming.stamp(RunTimingKey.threadTurnSettlementStart)
            await uiTiming.count(RunTimingKey.threadStoreUpdateTurnCount)
            // RLS-S01: terminal settlement is not best-effort. A swallowed write left the
            // turn stuck on the last `.running` checkpoint (the "it's still answering"
            // bug). Reflect the terminal state in memory FIRST so the UI can never show an
            // indefinite spinner, then persist — and surface (don't swallow) a write failure.
            applyTerminalSettlement(settled, threadId: threadId)
            do {
                try threadStore.updateTurn(settled, inThreadId: threadId, now: Date())
                await uiTiming.stamp(RunTimingKey.threadTurnSettlementEnd)
            } catch {
                await uiTiming.stamp(RunTimingKey.threadTurnSettlementError, detail: String(describing: error))
                PerfCounters.bump(.settlementError)
                FileHandle.standardError.write(Data(
                    "[settlement] FAILED to persist terminal turn \(turnId) in thread \(threadId): \(error)\n".utf8))
            }
            if var run = settledRun {
                var finalTiming = run.timing ?? timing
                finalTiming.merge(await uiTiming.snapshot())
                finalTiming.count(RunTimingKey.runStoreSaveCount, by: 1)
                run.timing = finalTiming
                try? runStore.save(run, models: models)
                if turnKind == .teamRun, run.status.isTerminal {
                    ArtifactFloorOpener.regenerateArtifact(for: run, models: models)
                }
                // CWB-S03: in-process post-run capacity refresh for the worker's source.
                // The boolean gate lives in CapacityResidentService; this caller satisfies
                // `settlementObservedInDockAppProcess` by being the Dock app's run observer.
                if let modelId = run.answers.first?.modelId,
                   let source = models.first(where: { $0.id == modelId })?.driverId
                       ?? ModelCatalog.get(modelId)?.driverId,
                   CapacityAcquisition.validRefreshSourceIds.contains(source) {
                    await CapacityResidentService.shared.postRunSettled(source: source)
                }
            }
            reload()
        }
    }

    /// TRR-S01c — map board `RunEvent`s into the live artifact preview (Mac-only).
    func applyLiveArtifactEvent(
        _ event: RunEvent,
        runId: String,
        question: String,
        teamLabel: String,
        context: ArtifactProjector.Context
    ) {
        guard event.kind == RunEventKind.workerStatusChanged
            || event.kind == RunEventKind.workerAnswerDelta else { return }
        ensureLiveArtifactSeed(
            runId: runId, question: question, teamLabel: teamLabel, context: context)
        guard var state = liveArtifactByRunId[runId] else { return }
        if LiveArtifactProjector.apply(event, to: &state) {
            liveArtifactByRunId[runId] = state
            _ = bumpPublishGeneration()
        }
    }

    func ensureLiveArtifactSeed(
        runId: String,
        question: String,
        teamLabel: String,
        context: ArtifactProjector.Context
    ) {
        if let state = liveArtifactByRunId[runId], !state.seatList.isEmpty { return }
        if let run = runStore.load(runId: runId) {
            liveArtifactByRunId[runId] = LiveArtifactProjector.seed(run: run, context: context)
        } else if liveArtifactByRunId[runId] == nil {
            liveArtifactByRunId[runId] = LiveArtifactProjector.bootstrap(
                runId: runId, question: question, teamLabel: teamLabel)
        }
    }

    /// Force the in-memory `threads` turn to its terminal settled state immediately, so a
    /// completed run can never leave a live spinner even if the durable write then fails
    /// or a `reload()` races. The store write remains the source of durable truth.
    func applyTerminalSettlement(_ settled: ThreadTurn, threadId: String) {
        guard let ti = threads.firstIndex(where: { $0.id == threadId }),
              let tj = threads[ti].turns.firstIndex(where: { $0.id == settled.id }) else { return }
        threads[ti].turns[tj] = settled
    }

    /// Models whose driver is confirmed ready (cached health) — the only bench the
    /// team resolver may draw from. Never probes.
    var readyModels: [Model] {
        let parked = SetupStore().load().parkedSet
        let readyDriverIds = Set(
            toolStatuses
                .filter { $0.status.isSmokeReady && !parked.contains($0.driverId) }
                .map(\.driverId)
        )
        return models.filter { $0.enabled && readyDriverIds.contains($0.driverId) }
    }

    /// Resolve the model a routing send will actually run — explicit pin, else Auto tier
    /// default for the default team, else the team's first resolved worker.
    func effectiveModelId(for routing: ComposeRouting, preset: TeamPreset) -> String? {
        if !routing.to.isEmpty { return routing.to }
        if preset.id == TeamCatalog.defaultRunTeam()?.id {
            let settings = DefaultModelSettingsPersistence().load()
            let ready = Set(readyModels.map(\.id))
            return SubstitutionResolver.resolveAuto(settings: settings, readyModelIds: ready).resolvedModelId
        }
        let effort = EffortLevel(rawValue: routing.effort.rawValue) ?? preset.defaultEffort
        let resolved = TeamResolver.resolve(
            team: preset, requestLane: routing.lane.workLane, requestEffort: effort,
            readyModels: readyModels)
        return resolved.answerWorkers.first?.modelId
    }

    func liveArtifact(forRunId runId: String) -> LiveArtifactProjector.State? {
        liveArtifactByRunId[runId]
    }

    /// The durable TeamRun behind a board turn (by `runId`), for the board view.
    func teamRun(forRunId runId: String) -> TeamRun? {
        if let cached = runCache.get(runId) { return cached }
        guard let run = runStore.load(runId: runId) else { return nil }
        PerfCounters.bump(.runJSONDecode)
        // Only cache terminal (immutable) runs; a running run still changes.
        if run.status.isTerminal { runCache.set(runId, run) }
        return run
    }

    /// Manual "Resume now" for a vendor park — same run id, in-process.
    func resumeParkedVendorRun(runId: String) async {
        let coordinatorId = "mac:\(ProcessInfo.processInfo.processIdentifier)"
        guard runStore.claimVendorWake(
            runId: runId,
            coordinatorId: coordinatorId,
            now: Date(),
            force: true
        ) != nil else { return }
        let service = RunService(
            models: models,
            registry: registry,
            runStore: runStore,
            commandRunner: commandRunner,
            writeLock: writeLock
        )
        _ = await service.resumeParkedRun(
            runId: runId,
            coordinatorId: coordinatorId,
            selectionOrigin: MorningReceipt.manualResumeOrigin
        )
        runCache.clear(runId)
        requestReload()
    }

    /// Compatible substitutes for a parked vendor wait (manual "Use another model").
    func vendorSubstitutionCandidates(for run: TeamRun) -> [Model] {
        guard run.status == .queued,
              run.phase == .waitingForVendor,
              run.blocker?.resource == .vendorBackoff,
              let failedModelId = run.workers.first?.modelId,
              let presetId = run.presetId,
              let preset = TeamCatalog.get(presetId) else { return [] }
        let settings = DefaultModelSettingsPersistence().load()
        let observations = runStore.list().flatMap { stored in
            stored.failedWorkerAnswers.compactMap(\.result.capacityObservation)
                + stored.attempts.compactMap(\.capacityObservation)
        }
        let cooling = SourceCapacityLedger.coolingSources(observations: observations, now: Date())
        return VendorSubstitutionPolicy.manualCandidates(
            run: run,
            failedModelId: failedModelId,
            preset: preset,
            settings: settings,
            models: models,
            readyModels: readyModels,
            coolingSourceIds: cooling,
            lane: run.lane ?? preset.lane
        )
    }

    /// Manual substitute while parked — same run id, user-selected model.
    func substituteParkedVendorRun(runId: String, modelId: String) async {
        let coordinatorId = "mac:\(ProcessInfo.processInfo.processIdentifier)"
        guard runStore.claimVendorWake(
            runId: runId,
            coordinatorId: coordinatorId,
            now: Date(),
            force: true
        ) != nil else { return }
        let service = RunService(
            models: models,
            registry: registry,
            runStore: runStore,
            commandRunner: commandRunner,
            writeLock: writeLock
        )
        _ = await service.substituteParkedRun(
            runId: runId,
            modelId: modelId,
            coordinatorId: coordinatorId
        )
        runCache.clear(runId)
        requestReload()
    }

    /// Cancel a parked vendor wait via ownership kill settlement.
    func cancelParkedVendorRun(runId: String) async {
        _ = ProcessOwnershipSurface(runStore: runStore).kill(id: runId)
        runCache.clear(runId)
        requestReload()
    }

    /// Warm the terminal-run decode cache off the MainActor after selection (PERF-S04b).
    /// Body evaluation still falls back to a sync load on cache miss.
    func prefetchTerminalRuns(for thread: WorkThread) {
        let missing = thread.turns.compactMap(\.runId).filter { runCache.get($0) == nil }
        guard !missing.isEmpty else { return }
        let runStore = self.runStore
        Task.detached(priority: .userInitiated) {
            var loaded: [(String, TeamRun)] = []
            for runId in missing {
                guard let run = runStore.load(runId: runId), run.status.isTerminal else { continue }
                loaded.append((runId, run))
            }
            guard !loaded.isEmpty else { return }
            await MainActor.run { [weak self] in
                guard let self else { return }
                for (runId, run) in loaded {
                    if self.runCache.get(runId) == nil {
                        self.runCache.set(runId, run)
                        PerfCounters.bump(.runJSONDecode)
                    }
                }
            }
        }
    }

    /// Drop a run from the decode cache (e.g. after it's updated/persisted).
    func invalidateRunCache(_ runId: String) { runCache.clear(runId) }

    func appendFailedRun(_ reason: String, kind: ThreadTurnKind, toThreadId threadId: String) {
        let turn = ThreadTurn(
            id: UUID().uuidString, threadId: threadId, kind: kind, status: .failed,
            createdAt: Date(), completedAt: Date(), author: .system, text: reason
        )
        try? store.appendTurn(turn, toThreadId: threadId, now: Date())
        refreshPublishedThread(threadId)
        reload()
    }

    /// A board turn is `.done` whenever the run produced something to show (complete
    /// OR partial — the board itself shows which workers failed); only a fully
    /// failed/interrupted run with no board is a failed turn.
    nonisolated static func turnStatus(for status: RunStatus) -> ThreadTurnStatus {
        switch status {
        case .complete, .partial, .done: return .done
        case .timedOut: return .timedOut
        case .cancelled: return .cancelled
        case .failed, .interrupted: return .failed
        // All non-terminal states show the in-flight spinner (RLR-L3 `queued`/
        // `running` included); a SUCCESS coerces these to `.done` via settledStatus.
        case .draft, .queued, .running, .fanningOut, .answersIn, .planning, .reviewing, .finalizing: return .running
        }
    }

    /// RLS-S01 terminal-settlement guarantee: a SUCCESSFUL terminal `RunService`
    /// result must settle the thread turn to a terminal state — never `.running`.
    /// `run()` returning `.success` means the run is over, so a `run.status` that
    /// still maps to `.running` (a stale `.finalizing`/`.answersIn`/etc.) is coerced
    /// to `.done`. No spinner may survive a terminal run.
    nonisolated static func settledStatus(forSuccessfulRun status: RunStatus) -> ThreadTurnStatus {
        let mapped = turnStatus(for: status)
        return mapped == .running ? .done : mapped
    }
}
