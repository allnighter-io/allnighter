import Foundation
import AllnighterCore

/// Observable ownership surface for `alln ps` / `alln kill` (PO-S05).
///
/// Reads durable state — run dirs, relay dirs, lane `holder.json` files —
/// via existing ProcessOwnership / RunStore / LoopStateStore / ExecutionLaneFlock
/// readers. No new process machinery.
///
/// Law:
/// - `list` **reconciles on read** (CLP-S02): identity-dead owners are settled
///   before rows are returned. Default view shows the floor only (`--all` for history).
/// - `kill` is the big red button: identity-checked total group kill
///   (`ProcessOwnership.terminateOwnerIdentityIfSafe`) + one atomic terminal
///   write `endReason: killed`. Refuses on identity mismatch (recycled pid).
public struct ProcessOwnershipSurface: Sendable {
    public var runStore: RunStore
    public var loopStore: LoopStateStore
    public var lanesRoot: URL
    public var threadProjector: LoopThreadProjector?
    public var now: @Sendable () -> Date

    public init(
        runStore: RunStore = RunStore(),
        loopStore: LoopStateStore = LoopStateStore(),
        lanesRoot: URL? = nil,
        threadProjector: LoopThreadProjector? = LoopThreadProjector(),
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.runStore = runStore
        self.loopStore = loopStore
        self.lanesRoot = lanesRoot ?? AllnighterPaths.lanes
        self.threadProjector = threadProjector
        self.now = now
    }

    // MARK: - ps

    /// Enumerate the process trees Allnighter owns. Stable order: kind, then id.
    ///
    /// `scopeRoot` (Concurrent Invocation Isolation F1/F3): when non-nil, only
    /// rows whose project root canonicalizes to the caller's root are listed.
    /// Fail closed — rows with an unresolvable root (nil, e.g. proof holders)
    /// are excluded from a scoped listing. `nil` is the explicit machine-wide
    /// fleet view (`alln ps --all-projects`).
    ///
    /// `includeHistory`: when false (default), only alive + needs-action rows
    /// (CLP-S03). Pass true via `alln ps --all` for the full museum.
    public func list(scopeRoot: String? = nil, includeHistory: Bool = false) -> OwnershipPsJSON {
        reconcileOnRead(scopeRoot: scopeRoot)
        let countedAt = now()
        var rows: [OwnershipProcessJSON] = []
        rows.append(contentsOf: listRuns(now: countedAt))
        rows.append(contentsOf: listRelays(now: countedAt))
        rows.append(contentsOf: listProofHolders(now: countedAt, existingIds: Set(rows.map(\.id))))
        if let scopeRoot {
            rows = rows.filter { ProjectScope.matches(scopeRoot: scopeRoot, recordRoot: $0.projectRoot) }
        }
        if !includeHistory {
            rows = rows.filter { Self.isFloorVisible($0) }
        }
        rows.sort { lhs, rhs in
            if lhs.kind != rhs.kind { return lhs.kind < rhs.kind }
            return lhs.id < rhs.id
        }
        return OwnershipPsJSON(countedAt: countedAt, processes: rows)
    }

    /// Alive + needs-action rows for default `alln ps` (CLP-S03).
    ///
    /// Agent receipts (RLR-S04a) follow the same alive/history rule as every
    /// other kind — a historical (identity-dead) receipt is museum, hidden by
    /// default; a still identity-alive survivor (e.g. after a `partial` kill)
    /// must remain visible so the operator can see what is still running.
    public static func isFloorVisible(_ row: OwnershipProcessJSON) -> Bool {
        if row.identityAlive { return true }
        if row.kind == "worker" { return false }
        switch row.status {
        case LoopState.Status.awaitingPM.rawValue, LoopState.Status.escalated.rawValue:
            return true
        default:
            break
        }
        if row.phase == RunPhase.waitingForVendor.rawValue { return true }
        return false
    }

    /// Eager reconcile before status inventory (CLP-S02).
    private func reconcileOnRead(scopeRoot: String?) {
        for relay in loopStore.list() {
            if let scopeRoot,
               !ProjectScope.matches(scopeRoot: scopeRoot, recordRoot: relay.projectRoot) {
                continue
            }
            _ = LoopCoordinator.reconcileOrphan(
                relay, stateStore: loopStore, threadProjector: threadProjector, now: now
            )
        }
        _ = runStore.reconcileAll(scopeRoot: scopeRoot)
    }

    /// Human-readable table for `alln ps` without `--json`.
    public static func humanTable(_ envelope: OwnershipPsJSON) -> String {
        if envelope.processes.isEmpty {
            return "no owned process trees"
        }
        var lines: [String] = []
        // AVQ-S02: STREAM_AGE is stream progress age (not process heartbeat).
        let header = pad("ID", 28) + pad("KIND", 8) + pad("ALIVE", 7)
            + pad("WOULD_REAP", 11) + pad("END", 18) + pad("STREAM_AGE", 12) + "ROOT"
        lines.append(header)
        lines.append(String(repeating: "-", count: min(header.count, 100)))
        for p in envelope.processes {
            let alive = p.identityAlive ? "yes" : "no"
            let reap = p.wouldReconcile ? "yes" : "no"
            let end = p.endReason ?? "-"
            let age: String
            if let s = p.heartbeatAgeSeconds {
                let base = String(format: "%.0fs", s)
                // Mark stale stream on the primary row (not only a secondary line).
                age = p.progressStale == true ? "\(base)*STALE" : base
            } else {
                age = p.progressStale == true ? "*STALE" : "-"
            }
            let root = p.projectRoot ?? "-"
            lines.append(
                pad(p.id, 28) + pad(p.kind, 8) + pad(alive, 7)
                    + pad(reap, 11) + pad(end, 18) + pad(age, 12) + root
            )
            if let silence = p.silenceStatus {
                lines.append("  \(silence)")
            }
            if p.phase == RunPhase.waitingForVendor.rawValue,
               let vendor = p.vendorDisplayName {
                lines.append("  " + VendorContinuityPresentation.waitStatus(
                    vendorDisplayName: vendor
                ))
            }
        }
        lines.append("(\(envelope.processCount) process trees)")
        return lines.joined(separator: "\n")
    }

    // MARK: - kill

    /// Identity-checked total kill of one owned tree + stamp `endReason: killed`.
    public func kill(id: String) -> Result<OwnershipKillRowJSON, OwnershipKillError> {
        if let run = runStore.loadRaw(runId: id) ?? runStore.load(runId: id) {
            return killRun(run)
        }
        if let relay = loopStore.load(id: id) {
            return killRelay(relay)
        }
        if let holder = findProofHolder(id: id) {
            return killProofHolder(holder)
        }
        return .failure(.notFound(id: id))
    }

    /// Kill every identity-alive owned tree **in `scopeRoot`'s project scope**.
    /// Skips identity-mismatched, terminal, and identity-dead (those are
    /// reconcile's job). Never signals recycled pids. Rows whose root can't be
    /// resolved are never in a scoped snapshot (fail closed). `nil` scope is
    /// the explicit machine-wide fleet kill (`alln kill --all --all-projects`).
    public func killAll(scopeRoot: String? = nil) -> OwnershipKillJSON {
        let snapshot = list(scopeRoot: scopeRoot)
        var killed: [OwnershipKillRowJSON] = []
        var skipped: [OwnershipKillSkipJSON] = []
        for row in snapshot.processes {
            // RLR-S04a: recorded worker receipts are read-only `ps` substrate, not
            // independently kill-targetable rows (their group is settled through
            // the owning run — the settlement routine lands in S04b). Skip silently
            // so `kill --all` semantics are unchanged by the new receipts.
            guard row.kind != "worker" else { continue }
            guard row.identityAlive else {
                skipped.append(.init(id: row.id, reason: row.endReason != nil ? "alreadyTerminal" : "identityNotAlive"))
                continue
            }
            if let identity = row.identity.flatMap(ProcessOwnership.OwnerIdentity.fromRecord),
               isIdentityMismatch(identity) {
                skipped.append(.init(id: row.id, reason: "identityMismatch"))
                continue
            }
            switch kill(id: row.id) {
            case .success(let r):
                // RLR-S04b: only a verified stop counts as killed. A non-terminal
                // verdict (partial/refused/verificationUnavailable) is surfaced as a
                // skip with its outcome, never counted as a kill.
                if let outcome = r.killOutcome, outcome != KillOutcome.stopped.rawValue {
                    skipped.append(.init(id: row.id, reason: "killOutcome:\(outcome)"))
                } else {
                    killed.append(r)
                }
            case .failure(.alreadyTerminal(_, let end)):
                skipped.append(.init(id: row.id, reason: "alreadyTerminal:\(end ?? "unknown")"))
            case .failure(.identityMismatch):
                skipped.append(.init(id: row.id, reason: "identityMismatch"))
            case .failure(.notFound):
                skipped.append(.init(id: row.id, reason: "notFound"))
            }
        }
        return OwnershipKillJSON(killed: killed, skipped: skipped)
    }

    // MARK: - Runs

    private func listRuns(now: Date) -> [OwnershipProcessJSON] {
        guard let entries = try? FileManager.default.contentsOfDirectory(
            at: runStore.rootDirectory,
            includingPropertiesForKeys: nil
        ) else {
            return []
        }
        var rows: [OwnershipProcessJSON] = []
        for dir in entries where dir.lastPathComponent.hasPrefix("run_") {
            guard let data = try? Data(contentsOf: dir.appendingPathComponent("run.json")),
                  let run = try? CoreJSON.decode(TeamRun.self, from: data) else {
                continue
            }
            let identity = ProcessOwnership.readOwnerIdentity(in: dir)
            let alive = identity.map { ProcessOwnership.isIdentityAlive($0) } ?? false
            let terminal = run.status.isTerminal
            let quietVendorPark = run.phase == .waitingForVendor
            // RLR-S03a / RLR-L6: activity truth is `run.json.lastActivityAt`, not
            // `heartbeat.json` (retired). `progressStale` is derived at read time —
            // absent before first activity, only meaningful while non-terminal.
            let last = run.lastActivityAt
            let age = RunActivity.heartbeatAgeSeconds(lastActivityAt: last, now: now)
            let stale = (terminal || quietVendorPark)
                ? nil
                : RunActivity.progressStale(lastActivityAt: last, now: now)
            let vendorBlocker = quietVendorPark ? run.blocker : nil
            let vendorSource = vendorBlocker?.capacityObservation?.source
                ?? vendorBlocker?.quotaScope
            let workerOwners = ProcessOwnership.readWorkerOwners(inRunDirectory: dir)
            let anyWorkerAlive = workerOwners.contains { ProcessOwnership.isIdentityAlive($0.identity) }
            let coordPGKillable = identity.map { $0.kind.isProcessGroupKillable } ?? false
            let contradiction = RunContradictionSurface.contradiction(
                isTerminal: terminal,
                anyWorkerIdentityAlive: anyWorkerAlive,
                coordinatorIdentityAlive: alive,
                coordinatorIsProcessGroupKillable: coordPGKillable
            )?.rawValue
            // Cancel lie recovery: terminal + live ownership must be would-reap.
            // Identity-dead non-terminal still uses the F2 lease gate.
            let would: Bool
            if contradiction == RunContradiction.terminalWithLiveOwnership.rawValue {
                would = true
            } else {
                would = !terminal && !quietVendorPark
                    && ProcessOwnership.isReclaimable(in: dir, runCreatedAt: run.createdAt)
            }
            let waitingWriteLock = !terminal
                && (run.phase == .waitingForWriteLock
                    || run.blocker?.resource == .repoWriteLock)
            rows.append(OwnershipProcessJSON(
                id: run.id,
                kind: "run",
                projectRoot: run.repoRoot,
                identity: identity?.asRecord(),
                identityAlive: alive,
                wouldReconcile: would,
                lane: laneState(
                    forRoot: run.repoRoot, workId: run.id, now: now,
                    isWriteLockWaiter: waitingWriteLock),
                lastProgressAt: last,
                heartbeatAgeSeconds: age,
                lastActivityKind: run.lastActivityKind?.rawValue,
                progressStale: stale,
                endReason: run.endReason?.rawValue,
                status: run.status.rawValue,
                phase: run.phase?.rawValue,
                blockerResource: run.blocker?.resource.rawValue,
                vendorDisplayName: vendorSource.map {
                    VendorContinuityPresentation.vendorDisplayName(sourceId: $0)
                },
                wakeAfter: vendorBlocker?.wakeAfter,
                capacityObservation: vendorBlocker?.capacityObservation,
                killOutcome: run.killOutcome?.rawValue,
                contradiction: contradiction,
                silenceStatus: OwnershipSilencePresentation.silenceStatusLine(
                    identityAlive: alive || anyWorkerAlive,
                    lastProgressAt: last,
                    now: now,
                    stallSummary: stallSummaryForRun(directory: dir, identity: identity, workerOwners: workerOwners)
                )
            ))
            // RLR-S04a: surface each recorded worker `runtimeOwnership` receipt
            // (zombie-aware identity-alive) so the recorded worker tree is visible
            // in `ps`. Read-only substrate — `killAll` skips these (worker groups
            // are settled through their run, not killed independently in S04a).
            for (workerId, wIdentity) in workerOwners {
                rows.append(OwnershipProcessJSON(
                    id: workerId,
                    kind: "worker",
                    projectRoot: run.repoRoot,
                    identity: wIdentity.asRecord(),
                    identityAlive: ProcessOwnership.isIdentityAlive(wIdentity),
                    wouldReconcile: false
                ))
            }
        }
        return rows
    }

    private func killRun(_ run: TeamRun) -> Result<OwnershipKillRowJSON, OwnershipKillError> {
        let directory: URL
        do {
            directory = try runStore.runDirectory(forRunId: run.id)
        } catch {
            return .failure(.notFound(id: run.id))
        }
        return ProcessOwnership.withRunLock(in: directory) {
            guard let data = try? Data(contentsOf: directory.appendingPathComponent("run.json")),
                  var current = try? CoreJSON.decode(TeamRun.self, from: data) else {
                return .failure(.notFound(id: run.id))
            }
            if current.status.isTerminal {
                return .failure(.alreadyTerminal(id: current.id, endReason: current.endReason?.rawValue))
            }
            // The coordinator-owner recycled-pid guard is an early refusal (never
            // signal the wrong process); worker survivors are settled below.
            if let identity = ProcessOwnership.readOwnerIdentity(in: directory),
               isIdentityMismatch(identity) {
                return .failure(.identityMismatch(id: current.id))
            }

            // RLR-S04b: the ONE identity-checked settlement replaces the
            // unconditional `.cancelled`/`.killed` stamp. `kill` stamps terminal
            // ONLY on a verified `.stopped`; the other verdicts record `killOutcome`
            // and leave the lifecycle non-terminal (RLR-L5).
            let settlement = KillSettlement.settle(runDirectory: directory, mode: .kill, run: current)
            current.killOutcome = settlement.outcome

            guard settlement.outcome == .stopped else {
                // Non-terminal verdict: persist the honest `killOutcome`, leave
                // status/endReason/blocker untouched (survivors keep their ticket).
                _ = try? runStore.save(current, models: [])
                return .success(OwnershipKillRowJSON(
                    id: current.id, kind: "run",
                    endReason: nil, killOutcome: settlement.outcome.rawValue,
                    signalled: settlement.signalled))
            }

            // Verified stop → the atomic terminal revision.
            current.status = .cancelled
            current.endReason = .killed
            for i in current.answers.indices where !current.answers[i].result.status.isTerminal {
                current.answers[i].result.status = .cancelled
            }
            // RLR-S02c / RLR-L3: cancel/kill of a BLOCKED run clears its blocker AND
            // withdraws its FIFO ticket in this same terminal revision. The parked run
            // lives in its OWN process (we can't reach its continuation), so remove its
            // on-disk waiter file here — the remaining waiters' positions collapse
            // immediately even though the killer is a different process — and its own
            // process self-abandons the parked wait via this terminal journal. No
            // interleaved state where the run is terminal but still queued in the lane.
            // Gated on the `.stopped` verdict (RLR-L5 step 7): a `partial` kill of a
            // still-live run must NOT withdraw the ticket.
            let wasBlocked = current.blocker != nil
            current.blocker = nil
            if wasBlocked {
                ExecutionLaneFlock.withdrawWaiter(
                    laneKey: ExecutionLane.key(repoRoot: current.repoRoot), claimId: current.id)
            }
            _ = try? runStore.save(current, models: [])
            // WL-PWR-S02: if this process owns the live run, free its lane now.
            let runId = current.id
            let finished = DispatchSemaphore(value: 0)
            Task {
                await RunExecutionRegistry.shared.requestStop(runId: runId)
                finished.signal()
            }
            _ = finished.wait(timeout: .now() + 2.0)
            return .success(OwnershipKillRowJSON(
                id: current.id, kind: "run",
                endReason: "killed", killOutcome: KillOutcome.stopped.rawValue,
                signalled: settlement.signalled))
        }
    }

    // MARK: - Relays / pilots

    private func listRelays(now: Date) -> [OwnershipProcessJSON] {
        loopStore.list().map { relay in
            let kind = "loop"
            let dir = (try? loopStore.directory(for: relay.id))
                ?? loopStore.rootDirectory.appendingPathComponent(relay.id, isDirectory: true)
            let turnOwner = ProcessOwnership.readTurnOwner(in: dir)
            let lastRoundOwner = relay.rounds.last?.devTurnOwner
                .flatMap(ProcessOwnership.OwnerIdentity.fromRecord)
            let identity = turnOwner ?? lastRoundOwner
            let alive = identity.map { ProcessOwnership.isIdentityAlive($0) } ?? false
            let terminal = relay.status != .running
            // Would reconcile: .running + owner dead (same guard as reconcileOrphan).
            let would = relay.status == .running && loopStore.isOwnerDead(id: relay.id)
            // CLP-S01: stream-primary liveness — dev journal only, not relay heartbeat.
            let streamLast = StreamLiveness.relayStreamLastActivityAt(state: relay, runStore: runStore)
            let age = streamLast.map { now.timeIntervalSince($0) }
            let stale = terminal
                ? nil
                : streamLast.map { RunActivity.progressStale(lastActivityAt: $0, now: now) } ?? true
            let endReason: String?
            if let stamped = relay.rounds.last?.devTurnEndReason {
                endReason = stamped.rawValue
            } else if terminal, let stopped = relay.stoppedReason {
                endReason = stopped == LoopState.orphanReconciledReason ? "reconciledOrphan" : nil
            } else {
                endReason = nil
            }
            return OwnershipProcessJSON(
                id: relay.id,
                kind: kind,
                projectRoot: relay.projectRoot,
                identity: identity?.asRecord(),
                identityAlive: alive,
                wouldReconcile: would,
                lane: laneState(
                    forRoot: relay.projectRoot, workId: relay.id, now: now,
                    isWriteLockWaiter: relay.laneBlocked != nil)
                    ?? relay.laneBlocked.map { ticket in
                        OwnershipLaneJSON(
                            state: "ticket",
                            holderId: ticket.holder.id,
                            holderKind: ticket.holder.kind,
                            heldSinceSeconds: ticket.heldSinceSeconds,
                            ticketPosition: ticket.position
                        )
                    },
                lastProgressAt: streamLast,
                heartbeatAgeSeconds: age,
                progressStale: stale,
                endReason: endReason,
                status: relay.status.rawValue,
                silenceStatus: OwnershipSilencePresentation.silenceStatusLine(
                    identityAlive: alive,
                    lastProgressAt: streamLast,
                    now: now,
                    stallSummary: {
                        if let persisted = ProcessOwnership.readStallDiagnosis(in: dir)?.summary {
                            return persisted
                        }
                        if alive, let identity,
                           let live = ProcessOwnership.diagnoseOwnedTreeStall(identity: identity) {
                            return live.summary
                        }
                        return nil
                    }()
                )
            )
        }
    }

    private func killRelay(_ state: LoopState) -> Result<OwnershipKillRowJSON, OwnershipKillError> {
        let kind = "loop"
        // Terminal parked states (done/escalated/stopped/awaitingPM without a live tree).
        if state.status != .running {
            // Still allow kill when an in-flight turn owner file exists (edge).
            if let dir = try? loopStore.directory(for: state.id),
               ProcessOwnership.readTurnOwner(in: dir) == nil {
                let end = state.rounds.last?.devTurnEndReason?.rawValue
                return .failure(.alreadyTerminal(id: state.id, endReason: end))
            }
        }
        guard var current = loopStore.load(id: state.id) else {
            return .failure(.notFound(id: state.id))
        }
        let dir: URL
        do {
            dir = try loopStore.directory(for: current.id)
        } catch {
            return .failure(.notFound(id: state.id))
        }

        // Prefer live turn-owner file; fall back to last round owner; then owner.pid is not
        // a full identity (never invent one).
        let turnOwner = ProcessOwnership.readTurnOwner(in: dir)
        let lastRecord = current.rounds.last?.devTurnOwner
        let lastIdentity = lastRecord.flatMap(ProcessOwnership.OwnerIdentity.fromRecord)
        let identity = turnOwner ?? lastIdentity

        if let identity, isIdentityMismatch(identity) {
            return .failure(.identityMismatch(id: current.id))
        }

        var signalled = false
        if let turnOwner {
            signalled = ProcessOwnership.terminateOwnerIdentityIfSafe(turnOwner)
            ProcessOwnership.clearTurnOwner(in: dir)
        } else if let lastIdentity {
            signalled = ProcessOwnership.terminateOwnerIdentityIfSafe(lastIdentity)
        }

        if let lastIndex = current.rounds.indices.last {
            if current.rounds[lastIndex].devTurnEndReason == nil {
                current.rounds[lastIndex].devTurnEndReason = .killed
            }
            if let identity {
                current.rounds[lastIndex].devTurnOwner =
                    current.rounds[lastIndex].devTurnOwner ?? identity.asRecord()
            }
            if current.rounds[lastIndex].outcome == nil {
                current.rounds[lastIndex].outcome = .stopped
                current.rounds[lastIndex].finishedAt = now()
            }
        }
        if current.status == .running || current.status == .awaitingPM {
            current.status = .stopped
            current.stoppedReason = current.stoppedReason ?? "killed"
            current.finishedAt = current.finishedAt ?? now()
        }
        current.laneBlocked = nil
        _ = try? loopStore.save(current)
        return .success(OwnershipKillRowJSON(id: current.id, kind: kind, signalled: signalled))
    }

    // MARK: - Proof holders (lane holder.json with harnessProof)

    private struct ProofHolder {
        var laneKey: String
        var metadata: ExecutionLaneFlock.HolderMetadata
    }

    private func listProofHolders(now: Date, existingIds: Set<String>) -> [OwnershipProcessJSON] {
        allHolders().compactMap { holder -> OwnershipProcessJSON? in
            guard holder.metadata.kind == ExecutionLaneSite.harnessProof.rawValue else { return nil }
            // Prefer the run/relay row when the proof claim id already appears there;
            // still emit a distinct proof row when the claim id is unique.
            let id = holder.metadata.id
            if existingIds.contains(id) {
                // Already listed as run/relay — skip duplicate row.
                return nil
            }
            let identity = holder.metadata.identity
            let alive = ProcessOwnership.isIdentityAlive(identity)
            let would = !alive
            return OwnershipProcessJSON(
                id: id,
                kind: "proof",
                projectRoot: nil,
                identity: identity.asRecord(),
                identityAlive: alive,
                wouldReconcile: would,
                lane: OwnershipLaneJSON(
                    state: "held",
                    holderId: holder.metadata.id,
                    holderKind: holder.metadata.kind,
                    heldSinceSeconds: max(0, now.timeIntervalSince(holder.metadata.acquiredAt))
                ),
                lastProgressAt: nil,
                heartbeatAgeSeconds: nil,
                endReason: nil,
                status: alive ? "running" : "orphaned"
            )
        }
    }

    private func findProofHolder(id: String) -> ProofHolder? {
        allHolders().first {
            $0.metadata.id == id && $0.metadata.kind == ExecutionLaneSite.harnessProof.rawValue
        }
    }

    private func killProofHolder(_ holder: ProofHolder) -> Result<OwnershipKillRowJSON, OwnershipKillError> {
        let identity = holder.metadata.identity
        if isIdentityMismatch(identity) {
            return .failure(.identityMismatch(id: holder.metadata.id))
        }
        let signalled = ProcessOwnership.terminateOwnerIdentityIfSafe(identity)
        // Clear holder metadata under the lanes root this surface was configured with
        // (tests inject a temp tree; production uses AllnighterPaths.lanes).
        let holderURL = lanesRoot
            .appendingPathComponent(holder.laneKey, isDirectory: true)
            .appendingPathComponent(ExecutionLaneFlock.holderFileName)
        try? FileManager.default.removeItem(at: holderURL)
        return .success(OwnershipKillRowJSON(id: holder.metadata.id, kind: "proof", signalled: signalled))
    }

    private func allHolders() -> [ProofHolder] {
        guard let entries = try? FileManager.default.contentsOfDirectory(
            at: lanesRoot,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }
        return entries.compactMap { dir -> ProofHolder? in
            let url = dir.appendingPathComponent(ExecutionLaneFlock.holderFileName)
            guard let data = try? Data(contentsOf: url),
                  let meta = try? CoreJSON.decode(ExecutionLaneFlock.HolderMetadata.self, from: data) else {
                return nil
            }
            // Directory name is the sanitized lane key (hex without v1:). Reconstruct
            // a key only for path helpers; holder metadata is enough for kill.
            let key = dir.lastPathComponent
            return ProofHolder(laneKey: key, metadata: meta)
        }
    }

    // MARK: - Lane state helper

    private func laneState(
        forRoot root: String?,
        workId: String,
        now: Date,
        isWriteLockWaiter: Bool
    ) -> OwnershipLaneJSON? {
        guard let root, !root.isEmpty else { return nil }
        let key = ExecutionLane.key(repoRoot: root)
        // Prefer the canonical path under AllnighterPaths (honors SUPPORT_DIR); also
        // probe our injected lanesRoot for tests that redirect the tree.
        let meta = ExecutionLaneFlock.readHolder(laneKey: key)
            ?? readHolderUnderLanesRoot(laneKey: key)
        if let meta {
            if meta.id == workId {
                return OwnershipLaneJSON(
                    state: "held",
                    holderId: meta.id,
                    holderKind: meta.kind,
                    heldSinceSeconds: max(0, now.timeIntervalSince(meta.acquiredAt))
                )
            }
            guard isWriteLockWaiter else {
                return OwnershipLaneJSON(state: "none")
            }
            let position = ExecutionLaneFlock.wouldBePosition(laneKey: key)
            return OwnershipLaneJSON(
                state: "ticket",
                holderId: meta.id,
                holderKind: meta.kind,
                heldSinceSeconds: max(0, now.timeIntervalSince(meta.acquiredAt)),
                ticketPosition: position
            )
        }
        return OwnershipLaneJSON(state: "none")
    }

    private func readHolderUnderLanesRoot(laneKey: String) -> ExecutionLaneFlock.HolderMetadata? {
        let safe = ExecutionLaneFlock.sanitizedDirectoryName(for: laneKey)
        let url = lanesRoot.appendingPathComponent(safe, isDirectory: true)
            .appendingPathComponent(ExecutionLaneFlock.holderFileName)
        guard let data = try? Data(contentsOf: url),
              let meta = try? CoreJSON.decode(ExecutionLaneFlock.HolderMetadata.self, from: data) else {
            return nil
        }
        return meta
    }

    // MARK: - Stall diagnosis (auth-prompt / frozen child)

    private func stallSummaryForRun(
        directory: URL,
        identity: ProcessOwnership.OwnerIdentity?,
        workerOwners: [(workerId: String, identity: ProcessOwnership.OwnerIdentity)]
    ) -> String? {
        if let persisted = ProcessOwnership.readStallDiagnosis(in: directory)?.summary {
            return persisted
        }
        if let identity, ProcessOwnership.isIdentityAlive(identity),
           let live = ProcessOwnership.diagnoseOwnedTreeStall(identity: identity) {
            return live.summary
        }
        for (_, wIdentity) in workerOwners where ProcessOwnership.isIdentityAlive(wIdentity) {
            if let live = ProcessOwnership.diagnoseOwnedTreeStall(identity: wIdentity) {
                return live.summary
            }
        }
        return nil
    }

    // MARK: - Identity

    /// Live pid with a different start time → recycled; must never be signalled.
    private func isIdentityMismatch(_ identity: ProcessOwnership.OwnerIdentity) -> Bool {
        ProcessOwnership.processAlive(identity.pid)
            && !ProcessOwnership.isIdentityAlive(identity)
    }

    private static func pad(_ s: String, _ width: Int) -> String {
        if s.count >= width { return String(s.prefix(width - 1)) + " " }
        return s + String(repeating: " ", count: width - s.count)
    }
}
