import Foundation
import Observation
import AllnighterCore
import AllnighterEngine

/// R-S08 — resume-from-GUI (`docs/phases/PM_Relay.md` §4.1: "escalate is a first-class
/// outcome"). When a relay's PM turn escalated (a real founder question), the thread shows
/// an open `relay_escalated` system event (`LoopThreadProjector.syncEscalation`); this
/// controller routes the founder's typed answer through `LoopCoordinator.resume` — same
/// construction as launch (`RelayGUIRuntime.makeCoordinator`), never a normal chat turn.
///
/// There is no existing "answer this open thing inline" seam in the thread composer today
/// (`ThreadTurnRow` has no case for `.systemEvent` at all — it falls through to the generic
/// `stubTurn` pill; manual-paste system events have never grown one either). Routing
/// through the general composer/`sendRouting` would mean teaching it to recognize "the
/// selected thread's open turn is a relay escalation" and branch its entire send path
/// around that — invasive surgery on a house-critical, well-tested file for one narrow
/// case. Per the brief's explicit fallback, this ships as a dedicated affordance on the
/// escalation row instead (`RelayEscalationRow` in `ThreadView.swift`): its own text field
/// + "Answer & resume" button, wired directly to this controller.
@MainActor
@Observable
final class RelayResumeController {
    private(set) var resumingRelayIds: Set<String> = []
    private(set) var lastError: [String: String] = [:]

    private let makeCoordinator: (@escaping @Sendable () -> String) -> LoopCoordinator
    private let stateStore: LoopStateStore
    private let projectStore: ProjectStore
    /// Injected clock for `canResume`'s idFactory placeholder — resume never mints a NEW
    /// relay id, but `RelayGUIRuntime.makeCoordinator` always wants one (unused on the
    /// resume path; `LoopCoordinator.resume` looks the relay up by the id it's given).
    private let idFactory: @Sendable () -> String

    init(
        makeCoordinator: @escaping (@escaping @Sendable () -> String) -> LoopCoordinator = RelayGUIRuntime.makeCoordinator,
        stateStore: LoopStateStore = LoopStateStore(),
        projectStore: ProjectStore = ProjectStore(),
        idFactory: @escaping @Sendable () -> String = { RelayGUIRuntime.newRelayId() }
    ) {
        self.makeCoordinator = makeCoordinator
        self.stateStore = stateStore
        self.projectStore = projectStore
        self.idFactory = idFactory
    }

    /// Whether `loopId` is currently eligible to resume — an escalated relay (a real
    /// founder question) or one reconciled-`.stopped` after its owner process died
    /// mid-round (`LoopState.isResumable` covers the first; the owner-liveness check here
    /// covers the second, mirroring `LoopEngineCLI.parseResumeRequest`'s pre-check — the actual
    /// reconciliation happens inside `LoopCoordinator.resume` itself).
    func canResume(loopId: String) -> Bool {
        guard let state = stateStore.load(id: loopId) else { return false }
        if state.isResumable { return true }
        return state.status == .running && stateStore.isOwnerDead(id: loopId)
    }

    func isResuming(_ loopId: String) -> Bool { resumingRelayIds.contains(loopId) }

    /// Sends the founder's answer through `LoopCoordinator.resume` — the SAME construction
    /// path (`RelayGUIRuntime.makeCoordinator`) `RelayLaunchViewModel.start` uses, so a
    /// resumed relay is dispatched identically whether it was launched from the CLI
    /// or this app. Returns `false` for an empty answer or an ineligible relay (no dispatch
    /// attempted); `true` once the resume `Task` has been kicked off.
    @discardableResult
    func resume(
        loopId: String, answer: String, maxRounds: Int = 20,
        onEvent: (@Sendable (LoopCoordinator.RelayEvent) -> Void)? = nil
    ) -> Bool {
        let trimmed = answer.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !isResuming(loopId), let prior = stateStore.load(id: loopId),
              canResume(loopId: loopId) else { return false }

        let projectId = RelayGUIRuntime.resolveProjectId(forRoot: prior.projectRoot, store: projectStore)
        // Every OTHER config field (`projectRoot`/`docPath`/worker ids)
        // re-derives from the persisted `LoopState` inside `LoopCoordinator.resume`
        // itself — only the ceilings are per-invocation (PM_Relay.md, `resume`'s own doc
        // comment). This mirrors `LoopEngineCLI.parseResumeRequest`.
        let config = LoopCoordinator.Config(
            projectRoot: prior.projectRoot,
            projectId: projectId,
            docPath: prior.docPath,
            pmModelId: prior.pmModelId,
            devModelId: prior.devModelId,
            maxRounds: maxRounds
        )

        resumingRelayIds.insert(loopId)
        lastError[loopId] = nil
        let coordinator = makeCoordinator(idFactory)
        Task { @MainActor [weak self] in
            let result = await coordinator.resume(
                loopId: loopId, founderAnswer: trimmed, config: config
            ) { event in
                Task { @MainActor in onEvent?(event) }
            }
            guard let self else { return }
            self.resumingRelayIds.remove(loopId)
            if case .failure(let refusal) = result {
                self.lastError[loopId] = Self.resumeFailureMessage(refusal)
            }
        }
        return true
    }

    /// RSC-S01: cause-specific copy for each `DispatchRefusal` — a lock-contention
    /// refusal (another process is actively dispatching right now) is a different,
    /// true statement from "not resumable" (the durable status itself is wrong), and
    /// asserting the wrong one names an unobserved cause.
    private static func resumeFailureMessage(_ refusal: LoopCoordinator.DispatchRefusal) -> String {
        switch refusal {
        case .relayNotFound:
            return "This relay no longer exists."
        case .notResumable:
            return "This relay is no longer resumable."
        case .roundInFlight:
            return "Another process is already dispatching a round for this relay — try again in a moment."
        case .alreadyActive:
            // Unreachable from `resume` — `.alreadyActive` is only ever produced by
            // `LoopCoordinator.run`'s start-time duplicate guard (RSC-S02). Kept for
            // `DispatchRefusal`'s exhaustive switch, not a real resume outcome.
            return "This relay is no longer resumable."
        case .journalUnavailable:
            return "The relay claim could not be written durably — check disk space and permissions, then try again."
        }
    }
}
