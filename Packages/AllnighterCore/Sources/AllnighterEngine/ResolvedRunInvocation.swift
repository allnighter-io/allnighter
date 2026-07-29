import Foundation
import AllnighterCore

/// Flag mode for a resolved run invocation (SH-S01). Internal — not a public JSON field.
public enum RunInvocationFlagMode: String, Sendable, Equatable, CaseIterable {
    case dryRun
    case foreground
    case detach
    case stream
    case tryFix
}

/// One executable seat after resolution (selected seats only).
public struct ResolvedRunSeat: Sendable, Equatable {
    public var workerId: String
    public var modelId: String
    public var skillId: String?
    public var purpose: String
    public var sourceId: String?
    public var seatingReason: String?

    public init(
        workerId: String,
        modelId: String,
        skillId: String? = nil,
        purpose: String,
        sourceId: String? = nil,
        seatingReason: String? = nil
    ) {
        self.workerId = workerId
        self.modelId = modelId
        self.skillId = skillId
        self.purpose = purpose
        self.sourceId = sourceId
        self.seatingReason = seatingReason
    }
}

/// Behavior-affecting flags preserved for teaching templates (Law 4).
public struct RunInvocationNormalizedFlags: Sendable, Equatable {
    public var projectId: String?
    public var teamId: String?
    public var pinnedModelId: String?
    public var effort: EffortLevel?
    public var lane: WorkLane?
    public var type: String?
    public var context: String?
    public var json: Bool
    public var noCommit: Bool
    public var acceptSurvivors: Bool
    public var commitMessage: String?
    public var proofCommand: String?
    public var executorTeamId: String?
    public var idleTimeoutSeconds: Int?
    public var handshakeTimeoutSeconds: Int?
    public var firstActivityTimeoutSeconds: Int?
    public var wallTimeoutSeconds: Int?
    public var idempotencyKey: String?
    public var retryOf: String?
    public var threadId: String?
    public var conversationId: String?
    public var messageId: String?
    public var agent: String?
    /// RSO-S01 — ordered explicit `--seat` model ids accepted at resolve time.
    public var explicitSeatModelIds: [String]? = nil

    public init(
        projectId: String? = nil,
        teamId: String? = nil,
        pinnedModelId: String? = nil,
        effort: EffortLevel? = nil,
        lane: WorkLane? = nil,
        type: String? = nil,
        context: String? = nil,
        json: Bool = false,
        noCommit: Bool = false,
        acceptSurvivors: Bool = false,
        commitMessage: String? = nil,
        proofCommand: String? = nil,
        executorTeamId: String? = nil,
        idleTimeoutSeconds: Int? = nil,
        handshakeTimeoutSeconds: Int? = nil,
        firstActivityTimeoutSeconds: Int? = nil,
        wallTimeoutSeconds: Int? = nil,
        idempotencyKey: String? = nil,
        retryOf: String? = nil,
        threadId: String? = nil,
        conversationId: String? = nil,
        messageId: String? = nil,
        agent: String? = nil,
        explicitSeatModelIds: [String]? = nil
    ) {
        self.projectId = projectId
        self.teamId = teamId
        self.pinnedModelId = pinnedModelId
        self.effort = effort
        self.lane = lane
        self.type = type
        self.context = context
        self.json = json
        self.noCommit = noCommit
        self.acceptSurvivors = acceptSurvivors
        self.commitMessage = commitMessage
        self.proofCommand = proofCommand
        self.executorTeamId = executorTeamId
        self.idleTimeoutSeconds = idleTimeoutSeconds
        self.handshakeTimeoutSeconds = handshakeTimeoutSeconds
        self.firstActivityTimeoutSeconds = firstActivityTimeoutSeconds
        self.wallTimeoutSeconds = wallTimeoutSeconds
        self.idempotencyKey = idempotencyKey
        self.retryOf = retryOf
        self.threadId = threadId
        self.conversationId = conversationId
        self.messageId = messageId
        self.agent = agent
        self.explicitSeatModelIds = explicitSeatModelIds
    }
}

/// Raw input before resolution. Callers pass flags; the resolver owns selection.
public struct RunInvocationInput: Sendable, Equatable {
    public var message: String
    public var projectRoot: String
    public var flagMode: RunInvocationFlagMode
    public var flags: RunInvocationNormalizedFlags
    public var advisoryReview: Bool

    public init(
        message: String,
        projectRoot: String,
        flagMode: RunInvocationFlagMode,
        flags: RunInvocationNormalizedFlags = .init(),
        advisoryReview: Bool = false
    ) {
        self.message = message
        self.projectRoot = projectRoot
        self.flagMode = flagMode
        self.flags = flags
        self.advisoryReview = advisoryReview
    }

    public init(request: RunRequest, flagMode: RunInvocationFlagMode) {
        self.message = request.message
        self.projectRoot = request.repoRoot
        self.flagMode = flagMode
        self.advisoryReview = request.advisoryReview
        self.flags = RunInvocationNormalizedFlags(
            projectId: request.projectId,
            teamId: request.presetId,
            pinnedModelId: request.pinnedModelId,
            effort: request.effort,
            lane: request.lane,
            type: request.type,
            context: request.context,
            json: false,
            noCommit: request.noCommit,
            acceptSurvivors: request.acceptSurvivors,
            commitMessage: request.commitMessage,
            proofCommand: request.proofCommand,
            executorTeamId: request.executorTeamId,
            idleTimeoutSeconds: request.workerTimeoutSeconds,
            handshakeTimeoutSeconds: request.handshakeTimeoutSeconds,
            firstActivityTimeoutSeconds: request.firstActivityTimeoutSeconds,
            wallTimeoutSeconds: request.wallTimeoutSeconds,
            idempotencyKey: request.idempotencyKey,
            retryOf: request.retryOf,
            threadId: request.threadId,
            agent: nil,
            explicitSeatModelIds: request.explicitSeatModelIds
        )
    }

    public init(request: AsyncTeamStartRequest, flagMode: RunInvocationFlagMode = .detach) {
        self.message = request.question
        self.projectRoot = request.repoRoot ?? ""
        self.flagMode = flagMode
        self.advisoryReview = false
        self.flags = RunInvocationNormalizedFlags(
            projectId: nil,
            teamId: request.teamPresetId,
            pinnedModelId: request.modelId,
            effort: request.effort,
            lane: request.lane,
            type: request.type,
            context: request.context,
            json: true,
            noCommit: false,
            acceptSurvivors: false,
            idempotencyKey: request.idempotencyKey,
            threadId: request.threadId,
            conversationId: request.originConversationId,
            messageId: request.originMessageId,
            agent: request.originAgent
        )
    }
}

/// Bench/runtime facts the resolver needs. Pure selection — no dispatch.
public struct RunInvocationResolveContext: Sendable {
    public var models: [Model]
    public var teams: [TeamPreset]
    public var readyModels: [Model]
    public var readyModelIds: Set<String>
    public var defaultSettings: DefaultModelSettings
    /// When the resolved write policy is mutating, optional live lock probe.
    public var writeLockHeld: Bool?
    public var governorAvailable: Bool
    public var governorBlockedReason: String?

    public init(
        models: [Model],
        teams: [TeamPreset] = TeamCatalog.all,
        readyModels: [Model]? = nil,
        readyModelIds: Set<String>? = nil,
        defaultSettings: DefaultModelSettings = .fresh,
        writeLockHeld: Bool? = nil,
        governorAvailable: Bool = true,
        governorBlockedReason: String? = nil
    ) {
        self.models = models
        self.teams = teams.isEmpty ? TeamCatalog.all : teams
        let ready = readyModels ?? models.filter(\.enabled)
        self.readyModels = ready
        self.readyModelIds = readyModelIds ?? Set(ready.map(\.id))
        self.defaultSettings = defaultSettings
        self.writeLockHeld = writeLockHeld
        self.governorAvailable = governorAvailable
        self.governorBlockedReason = governorBlockedReason
    }
}

/// One resolved invocation shared by dry-run and foreground/detach execution (SH-S01).
/// Internal truth owner — public `RunDryRunJSON` is projected from this value.
public struct ResolvedRunInvocation: Sendable, Equatable {
    public var projectId: String?
    public var projectRoot: String
    public var teamPresetId: String
    public var teamDisplayName: String
    public var explicitTeamChosen: Bool
    public var explicitModelChosen: Bool
    public var workerId: String?
    public var autoResolved: Bool
    public var lane: WorkLane
    public var effort: EffortLevel
    public var type: String?
    public var seats: [ResolvedRunSeat]
    public var writePolicy: RunWritePolicy
    public var takesWriteLock: Bool
    public var canStart: Bool
    public var blockedReason: String?
    public var warnings: [String]
    public var lockKey: String
    public var writeLockHeld: Bool?
    public var flagMode: RunInvocationFlagMode
    public var normalizedFlags: RunInvocationNormalizedFlags
    public var resolvedSourceIds: [String]
    public var blockedSeatCount: Int
    /// Declared sensitive placeholders for teaching templates (Law 4).
    public var templateVariables: [String: String]
    /// Tokenized replay argv; callers substitute `templateVariables` (no shell inference).
    public var argvTemplate: [String]
    /// Preset used by execution (Default Team when no `--team`).
    public var preset: TeamPreset

    public var mutating: Bool { writePolicy == .mutating }

    public var seatCount: Int { seats.count }

    /// Resolved effects for the spend twin this preview validates (Law 7).
    /// `repoWrite` is permission from `writePolicy`, not an observed repo delta.
    /// Dry-run itself does not start workers or spend; those booleans describe the
    /// real run `nextAction` would dispatch.
    public var effects: RunDryRunJSON.Effects {
        guard let profile = ContractRegistry.milestone1.commands
            .first(where: { $0.name == "run" })?
            .effects
        else {
            preconditionFailure("ContractRegistry.milestone1 missing run command effects")
        }
        return profile.resolve(
            spending: true,
            repoWritePermitted: writePolicy == .mutating
        )
    }

    /// Project public dry-run envelope (schema v2 — writePolicy + effects; no top-level `mutating`).
    public func makeDryRunJSON() -> RunDryRunJSON {
        let readOnlySteer = readOnlyAnswerTeamSteer()
        let dryRunSeats = dryRunSeatProjection()
        return RunDryRunJSON(
            canStart: canStart,
            blockedReason: blockedReason,
            projectId: projectId,
            projectRoot: projectRoot,
            teamPresetId: teamPresetId,
            teamDisplayName: teamDisplayName,
            workerId: workerId,
            writePolicy: writePolicy,
            effects: effects,
            lane: lane.rawValue,
            counts: .init(
                readyWorkers: canStart ? seats.count : max(0, seats.count - blockedSeatCount),
                blockedWorkers: blockedSeatCount,
                resolvedSourceIds: resolvedSourceIds.count,
                seatCount: seats.count
            ),
            writeLockHeld: writeLockHeld,
            warnings: warnings + (readOnlySteer.map { [$0.warning] } ?? []),
            nextAction: canStart
                ? AgentNextAction(
                    kind: "startRun",
                    label: "Run for real (spends quota)",
                    command: teachingCommand)
                : AgentNextAction(
                    kind: "runDoctor",
                    label: "Check setup and sources",
                    command: blockedReason == nil ? "alln doctor --json" : teachingCommand),
            alternatives: readOnlySteer.map { [$0.alternative] },
            seats: dryRunSeats
        )
    }

    /// Project crew seats for answer/research teams (not bare default-chat execution).
    func dryRunSeatProjection() -> [RunDryRunJSON.Seat]? {
        guard !seats.isEmpty else { return nil }
        let projectsCrew = preset.runShape != .execution || explicitTeamChosen
        guard projectsCrew else { return nil }
        return seats.map { seat in
            let driverId = seat.sourceId ?? ""
            return RunDryRunJSON.Seat(
                modelId: seat.modelId,
                family: ModelCatalog.modelFamily(seat.modelId, driverId: driverId.isEmpty ? nil : driverId),
                driverId: driverId,
                skillId: seat.skillId,
                stage: seat.purpose,
                reason: seat.seatingReason ?? "band+rank"
            )
        }
    }

    /// Canonical read-only ask team the docs already reference (the Code lane
    /// default answer team). Teaching this preserves the caller's `--model`/`--effort`
    /// selectors while swapping to a team that is read-only by construction.
    static let readOnlyAnswerTeamId = "code_plan"

    /// ADP-S02 — when a dry-run resolves mutating-allowed on a bare prompt ask (no
    /// `--team`), teach the mechanical read-only answer-team alternative at the
    /// decision point. Returns `nil` (nothing taught) for answer-team runs, read-only
    /// resolutions, or when the answer team can't be resolved read-only. This changes
    /// no routing, lanes, or write-policy — it only discloses (SH-S05 / Menu-Not-Router).
    func readOnlyAnswerTeamSteer() -> (warning: String, alternative: RunDryRunJSON.Alternative)? {
        guard writePolicy == .mutating, !explicitTeamChosen else { return nil }
        guard let answerTeam = TeamCatalog.get(Self.readOnlyAnswerTeamId),
              answerTeam.writePolicy == .readOnly else { return nil }

        var altFlags = normalizedFlags
        altFlags.teamId = answerTeam.id
        // A read-only answer team never writes, so `--no-commit` is redundant noise.
        altFlags.noCommit = false
        let (altVars, altArgv) = RunInvocationResolver.buildTemplate(
            message: templateVariables["message"] ?? "",
            flagMode: flagMode,
            flags: altFlags,
            resolvedWorkerId: explicitModelChosen ? workerId : nil,
            resolvedTeamId: answerTeam.id
        )
        let command = Self.shellJoin(altArgv)
        let warning = "writePolicy is mutating because a bare prompt ask (Default Team / explicit --model) is mutating-allowed. For a mechanical read-only guarantee, run an answer team instead — e.g. `--team \(answerTeam.id)` — which is read-only by construction and preserves your selectors. See `alternatives`."
        let alternative = RunDryRunJSON.Alternative(
            kind: "readOnlyAnswerTeam",
            label: "Run as a read-only answer team (\(answerTeam.displayName))",
            command: command,
            argvTemplate: altArgv,
            templateVariables: altVars
        )
        return (warning, alternative)
    }

    /// Shell-joined teaching command using `{name}` placeholders from `templateVariables`.
    public var teachingCommand: String { Self.shellJoin(argvTemplate) }

    /// Shell-join a tokenized argv template, quoting `{name}` placeholders and any
    /// token that carries spaces/quotes. Shared by `teachingCommand` and the ADP-S02
    /// answer-team `alternatives` command so both render identically.
    static func shellJoin(_ argv: [String]) -> String {
        argv.map { token in
            if token.hasPrefix("{"), token.hasSuffix("}"), token.count > 2 {
                return "\"\(token)\""
            }
            if token.contains(" ") || token.contains("\"") {
                return "\"\(token.replacingOccurrences(of: "\"", with: "\\\""))\""
            }
            return token
        }.joined(separator: " ")
    }

    /// Foreground `RunRequest` carrying the same selectors (no re-resolution).
    public func makeRunRequest(message: String? = nil) -> RunRequest {
        let flags = normalizedFlags
        return RunRequest(
            message: message ?? templateVariables["message"] ?? "",
            repoRoot: projectRoot,
            threadId: flags.threadId,
            projectId: projectId,
            presetId: explicitTeamChosen ? teamPresetId : flags.teamId,
            pinnedModelId: explicitModelChosen ? workerId : flags.pinnedModelId,
            effort: flags.effort,
            lane: flags.lane,
            type: type,
            context: flags.context,
            executorTeamId: flags.executorTeamId,
            workerTimeoutSeconds: flags.idleTimeoutSeconds,
            handshakeTimeoutSeconds: flags.handshakeTimeoutSeconds,
            firstActivityTimeoutSeconds: flags.firstActivityTimeoutSeconds,
            wallTimeoutSeconds: flags.wallTimeoutSeconds,
            commitMessage: flags.commitMessage,
            noCommit: flags.noCommit,
            proofCommand: flags.proofCommand,
            idempotencyKey: flags.idempotencyKey,
            retryOf: flags.retryOf,
            acceptSurvivors: flags.acceptSurvivors
        )
    }

    /// Detach `AsyncTeamStartRequest` carrying the same selectors.
    public func makeAsyncStartRequest(message: String? = nil) -> AsyncTeamStartRequest {
        let flags = normalizedFlags
        return AsyncTeamStartRequest(
            question: message ?? templateVariables["message"] ?? "",
            lane: flags.lane ?? lane,
            teamPresetId: teamPresetId,
            effort: effort,
            modelId: workerId,
            type: type,
            context: flags.context,
            threadId: flags.threadId,
            originAgent: flags.agent,
            originConversationId: flags.conversationId,
            originMessageId: flags.messageId,
            idempotencyKey: flags.idempotencyKey,
            repoRoot: projectRoot
        )
    }
}

/// Single resolver for dry-run and execution (Law 3). Neither path may select independently.
public enum RunInvocationResolver {

    public static func resolve(
        _ input: RunInvocationInput,
        context: RunInvocationResolveContext
    ) -> ResolvedRunInvocation {
        var warnings: [String] = []
        var canStart = true
        var blockedReason: String?
        var blockedSeatCount = 0

        let explicitTeamChosen = !(input.flags.teamId ?? "").isEmpty
        let explicitModelChosen = !(input.flags.pinnedModelId ?? "").isEmpty
        let root = RunWriteLock.normalize(input.projectRoot) ?? input.projectRoot

        // --- Team (Default Team when no --team; matches RunService.run) ---
        let preset: TeamPreset
        let typeEcho: String?
        if explicitTeamChosen, let teamId = input.flags.teamId {
            switch ExactIdResolver.resolveTeam(teamId, flag: "--team", teams: context.teams) {
            case .success(let team):
                if let lane = input.flags.lane, lane != team.lane {
                    return blocked(
                        input: input, root: root, preset: team,
                        reason: "team \(team.id) is a \(team.lane.rawValue) team but --lane is \(lane.rawValue)",
                        explicitTeam: true, explicitWorker: explicitModelChosen
                    )
                }
                if let type = input.flags.type, !type.isEmpty, !team.typeTags.contains(type) {
                    return blocked(
                        input: input, root: root, preset: team,
                        reason: "--type \(type) conflicts with --team \(team.id) (type is not in the team's typeTags).",
                        explicitTeam: true, explicitWorker: explicitModelChosen
                    )
                }
                preset = team
                typeEcho = (input.flags.type.flatMap { team.typeTags.contains($0) ? $0 : nil })
            case .failure(let failure):
                let fallback = TeamCatalog.get(teamId) ?? TeamCatalog.defaultRunTeam()
                    ?? TeamPreset(
                        id: teamId, displayName: teamId, lane: .code, outputKind: .plan,
                        defaultEffort: .med, agentSpecs: [], lead: TeamLeadSpec(skillId: "plan_writer_build"))
                return blocked(
                    input: input, root: root, preset: fallback,
                    reason: failure.message,
                    explicitTeam: true, explicitWorker: explicitModelChosen
                )
            }
        } else {
            // Unified Run Model: no `--team` → Default Team, even when `--lane` /
            // `--model` / `--type` are present (lane is context; type is Copy sugar
            // only with an explicit team). Matches RunService.run.
            guard let team = TeamCatalog.defaultRunTeam()
                    ?? context.teams.first(where: { $0.id == "default_chat" }) else {
                return blocked(
                    input: input, root: root,
                    preset: TeamPreset(
                        id: "default_chat", displayName: "Auto", lane: .code, outputKind: .plan,
                        defaultEffort: .med, agentSpecs: [], lead: TeamLeadSpec(skillId: "plan_writer_build")),
                    reason: "no default team configured",
                    explicitTeam: false, explicitWorker: explicitModelChosen
                )
            }
            preset = team
            typeEcho = nil
        }

        let effort = input.flags.effort ?? preset.defaultEffort
        let lane = input.flags.lane ?? preset.lane
        let explicitSeatModelIds = input.flags.explicitSeatModelIds ?? []
        let explicitSeatsChosen = !explicitSeatModelIds.isEmpty
        if explicitSeatsChosen,
           let seatError = TeamExplicitSeats.validateFlags(
               seatModelIds: explicitSeatModelIds,
               explicitTeamChosen: explicitTeamChosen,
               explicitWorkerChosen: explicitModelChosen,
               preset: preset
           ) {
            return blocked(
                input: input, root: root, preset: preset,
                reason: seatError.description,
                explicitTeam: explicitTeamChosen, explicitWorker: explicitModelChosen
            )
        }
        let writePolicy = preset.writePolicy
        let takesWriteLock = writePolicy == .mutating && !input.advisoryReview
        let lockKey = RunWriteLock.key(repoRoot: root)
        let writeLockHeld = takesWriteLock ? context.writeLockHeld : nil
        if writeLockHeld == true {
            warnings.append("repo write lock is currently held")
        }

        // --- Agent ---
        var workerId: String? = nil
        var autoResolved = false

        if explicitModelChosen, let raw = input.flags.pinnedModelId {
            switch resolveExplicitModel(raw, context: context) {
            case .failure(let error):
                canStart = false
                blockedReason = error.description
                blockedSeatCount = 1
                workerId = raw
            case .success(let model):
                workerId = model.id
            }
        } else if preset.id == TeamCatalog.defaultRunTeam()?.id || preset.id == "default_chat" {
            let auto = SubstitutionResolver.resolveAuto(
                settings: context.defaultSettings, readyModelIds: context.readyModelIds)
            if let modelId = auto.resolvedModelId {
                workerId = modelId
                autoResolved = true
            } else {
                canStart = false
                blockedReason = "Auto waits — no ready model on the \(context.defaultSettings.defaultTier.displayName) tier"
                blockedSeatCount = 1
            }
        }

        // --- Seats (execution shape = one seat; answer = team seats or pin) ---
        var teamResolved: ResolvedTeamRun
        if explicitSeatsChosen {
            switch TeamExplicitSeats.resolve(
                team: preset,
                lane: lane,
                effort: effort,
                seatModelIds: explicitSeatModelIds,
                models: context.models,
                readyModels: context.readyModels
            ) {
            case .failure(let seatError):
                canStart = false
                blockedReason = seatError.description
                blockedSeatCount = explicitSeatModelIds.count
                teamResolved = TeamResolver.resolve(
                    team: preset, requestLane: lane, requestEffort: effort,
                    readyModels: context.readyModels
                )
            case .success(let resolved):
                teamResolved = resolved
            }
        } else {
            teamResolved = TeamResolver.resolve(
                team: preset, requestLane: lane, requestEffort: effort,
                readyModels: context.readyModels
            )
        }
        TeamSourceFacts.enrich(&teamResolved, models: context.models)

        var seats: [ResolvedRunSeat] = []
        if preset.runShape == .execution {
            // One worker — explicit pin, Auto, or team's answer seat.
            // Selected worker owns the seat; team roster readiness is not the canStart gate.
            let modelId = workerId
                ?? teamResolved.answerWorkers.first?.modelId
            if let modelId {
                let skillId = teamResolved.answerWorkers.first?.skillId
                seats = [
                    ResolvedRunSeat(
                        workerId: Agent.makeID(modelId: modelId, instanceIndex: 0),
                        modelId: modelId,
                        skillId: skillId,
                        purpose: AgentStage.answer.rawValue,
                        sourceId: context.models.first { $0.id == modelId }?.driverId
                    )
                ]
                if workerId == nil { workerId = modelId }
                // Selected-seat warnings only — drop multi-seat Default Team roster noise.
                warnings.append(contentsOf: teamResolved.warnings.filter { warning in
                    warning.localizedCaseInsensitiveContains(modelId)
                })
            } else if canStart {
                canStart = false
                blockedReason = teamResolved.blockReason ?? "no worker resolved"
                blockedSeatCount = 1
            }
        } else if explicitModelChosen, let pinnedId = workerId {
            // Answer team + --model → single pinned seat (matches RunService.runAnswer).
            let skillId = teamResolved.answerWorkers.first?.skillId
            seats = [
                ResolvedRunSeat(
                    workerId: Agent.makeID(modelId: pinnedId, instanceIndex: 0),
                    modelId: pinnedId,
                    skillId: skillId,
                    purpose: AgentStage.answer.rawValue,
                    sourceId: context.models.first { $0.id == pinnedId }?.driverId
                )
            ]
            warnings.append(contentsOf: teamResolved.warnings.filter {
                $0.localizedCaseInsensitiveContains(pinnedId)
            })
        } else {
            seats = teamResolved.allWorkers.map { w in
                let driverId = context.models.first { $0.id == w.modelId }?.driverId
                return ResolvedRunSeat(
                    workerId: w.id,
                    modelId: w.modelId,
                    skillId: w.skillId,
                    purpose: (w.purpose ?? .answer).rawValue,
                    sourceId: driverId,
                    seatingReason: w.seatingReason
                )
            }
            warnings.append(contentsOf: teamResolved.warnings)
            blockedSeatCount = teamResolved.disabledRows.count
            if !teamResolved.isRunnable {
                canStart = false
                blockedReason = teamResolved.blockReason ?? blockedReason
            }
            let gate = ExecutionTeamSourceGate.evaluate(resolved: teamResolved, models: context.readyModels)
            if let blocker = gate.sourceGateBlocker {
                canStart = false
                blockedReason = blocker.message
            }
        }

        if canStart, !context.governorAvailable {
            canStart = false
            blockedReason = context.governorBlockedReason ?? "team governor unavailable"
            warnings.append("Team governor is at capacity.")
        }

        let sourceIds = Array(Set(seats.compactMap(\.sourceId))).sorted()
        let displayName = RunIdentity.teamDisplayName(
            presetId: preset.id,
            catalogDisplayName: preset.displayName,
            explicitTeamChosen: explicitTeamChosen
        )

        var flags = input.flags
        // Canonicalize resolved worker id; type echoes only when valid for the team.
        if explicitModelChosen { flags.pinnedModelId = workerId ?? input.flags.pinnedModelId }
        flags.type = typeEcho ?? input.flags.type

        let (templateVariables, argvTemplate) = buildTemplate(
            message: input.message,
            flagMode: input.flagMode,
            flags: flags,
            resolvedWorkerId: explicitModelChosen ? workerId : nil,
            resolvedTeamId: explicitTeamChosen ? preset.id : nil
        )

        return ResolvedRunInvocation(
            projectId: flags.projectId,
            projectRoot: root,
            teamPresetId: preset.id,
            teamDisplayName: displayName,
            explicitTeamChosen: explicitTeamChosen,
            explicitModelChosen: explicitModelChosen,
            workerId: workerId,
            autoResolved: autoResolved,
            lane: lane,
            effort: effort,
            type: typeEcho ?? input.flags.type,
            seats: seats,
            writePolicy: writePolicy,
            takesWriteLock: takesWriteLock,
            canStart: canStart,
            blockedReason: blockedReason,
            warnings: warnings,
            lockKey: lockKey,
            writeLockHeld: writeLockHeld,
            flagMode: input.flagMode,
            normalizedFlags: flags,
            resolvedSourceIds: sourceIds,
            blockedSeatCount: blockedSeatCount,
            templateVariables: templateVariables,
            argvTemplate: argvTemplate,
            preset: preset
        )
    }

    // MARK: - Helpers

    private static func resolveExplicitModel(
        _ id: String,
        context: RunInvocationResolveContext
    ) -> Result<Model, RunServiceError> {
        switch ExactIdResolver.resolveWorker(
            id, flag: "--model", models: context.models, readyModelIds: context.readyModelIds
        ) {
        case .failure(let failure):
            return .failure(.workerNotAvailable(failure.message))
        case .success(let model):
            guard model.enabled else {
                return .failure(.workerNotAvailable(
                    "\(id) is disabled — run `alln models enable \(id)`, or pick a ready worker; see `alln menu --json` / `alln doctor`."
                ))
            }
            guard context.readyModelIds.contains(model.id) else {
                return .failure(.workerNotAvailable(
                    "\(id) is notReady — check `alln doctor` (or run `alln doctor --full`); see `alln menu --json`."
                ))
            }
            return .success(model)
        }
    }

    private static func blocked(
        input: RunInvocationInput,
        root: String,
        preset: TeamPreset,
        reason: String,
        explicitTeam: Bool,
        explicitWorker: Bool
    ) -> ResolvedRunInvocation {
        let flags = input.flags
        let (vars, argv) = buildTemplate(
            message: input.message,
            flagMode: input.flagMode,
            flags: flags,
            resolvedWorkerId: flags.pinnedModelId,
            resolvedTeamId: flags.teamId
        )
        return ResolvedRunInvocation(
            projectId: flags.projectId,
            projectRoot: root,
            teamPresetId: preset.id,
            teamDisplayName: RunIdentity.teamDisplayName(
                presetId: preset.id,
                catalogDisplayName: preset.displayName,
                explicitTeamChosen: explicitTeam),
            explicitTeamChosen: explicitTeam,
            explicitModelChosen: explicitWorker,
            workerId: flags.pinnedModelId,
            autoResolved: false,
            lane: flags.lane ?? preset.lane,
            effort: flags.effort ?? preset.defaultEffort,
            type: flags.type,
            seats: [],
            writePolicy: preset.writePolicy,
            takesWriteLock: preset.writePolicy == .mutating && !input.advisoryReview,
            canStart: false,
            blockedReason: reason,
            warnings: [],
            lockKey: RunWriteLock.key(repoRoot: root),
            writeLockHeld: nil,
            flagMode: input.flagMode,
            normalizedFlags: flags,
            resolvedSourceIds: [],
            blockedSeatCount: 0,
            templateVariables: vars,
            argvTemplate: argv,
            preset: preset
        )
    }

    /// Tokenized argv + declared sensitive variables. Every behavior-affecting
    /// explicit flag survives (Law 4). Sensitive prose uses `{name}` tokens.
    static func buildTemplate(
        message: String,
        flagMode: RunInvocationFlagMode,
        flags: RunInvocationNormalizedFlags,
        resolvedWorkerId: String?,
        resolvedTeamId: String?
    ) -> (variables: [String: String], argv: [String]) {
        var variables: [String: String] = ["message": message]
        var argv: [String] = ["alln", "run", "{message}"]

        if let project = flags.projectId, !project.isEmpty {
            argv.append(contentsOf: ["--project", project])
        }
        if let team = resolvedTeamId ?? flags.teamId, !team.isEmpty {
            argv.append(contentsOf: ["--team", team])
        }
        for seat in flags.explicitSeatModelIds ?? [] where !seat.isEmpty {
            argv.append(contentsOf: ["--seat", seat])
        }
        if let worker = resolvedWorkerId ?? flags.pinnedModelId, !worker.isEmpty {
            argv.append(contentsOf: ["--model", worker])
        }
        if let effort = flags.effort {
            argv.append(contentsOf: ["--effort", effort.rawValue])
        }
        if let lane = flags.lane {
            argv.append(contentsOf: ["--lane", lane.rawValue])
        }
        if let type = flags.type, !type.isEmpty {
            argv.append(contentsOf: ["--type", type])
        }
        if let context = flags.context, !context.isEmpty {
            variables["context"] = context
            argv.append(contentsOf: ["--context", "{context}"])
        }
        if let seconds = flags.idleTimeoutSeconds {
            argv.append(contentsOf: ["--idle-timeout", String(seconds)])
        }
        if let seconds = flags.handshakeTimeoutSeconds {
            argv.append(contentsOf: ["--handshake-timeout", String(seconds)])
        }
        if let seconds = flags.firstActivityTimeoutSeconds {
            argv.append(contentsOf: ["--first-activity-timeout", String(seconds)])
        }
        if let seconds = flags.wallTimeoutSeconds {
            argv.append(contentsOf: ["--wall-timeout", String(seconds)])
        }
        if let key = flags.idempotencyKey, !key.isEmpty {
            argv.append(contentsOf: ["--idempotency-key", key])
        }
        if let retry = flags.retryOf, !retry.isEmpty {
            argv.append(contentsOf: ["--retry-of", retry])
        }
        if flags.acceptSurvivors {
            argv.append("--accept-survivors")
        }
        if let commit = flags.commitMessage, !commit.isEmpty {
            variables["commitMessage"] = commit
            argv.append(contentsOf: ["--commit-message", "{commitMessage}"])
        }
        if flags.noCommit {
            argv.append("--no-commit")
        }
        if let proof = flags.proofCommand, !proof.isEmpty {
            variables["proof"] = proof
            argv.append(contentsOf: ["--proof", "{proof}"])
        }
        if let executor = flags.executorTeamId, !executor.isEmpty {
            argv.append(contentsOf: ["--executor", executor])
        }
        if let agent = flags.agent, !agent.isEmpty {
            argv.append(contentsOf: ["--agent", agent])
        }
        if let thread = flags.threadId, !thread.isEmpty {
            argv.append(contentsOf: ["--thread-id", thread])
        }
        if let conv = flags.conversationId, !conv.isEmpty {
            argv.append(contentsOf: ["--conversation-id", conv])
        }
        if let msg = flags.messageId, !msg.isEmpty {
            argv.append(contentsOf: ["--message-id", msg])
        }

        switch flagMode {
        case .detach:
            // RSC-S05: the real shipped detached-dispatch flag is `--no-wait`
            // (RSC-S04); the phantom flag this mode used to emit never existed as
            // real CLI grammar. This `.detach` mode has no live production call
            // site today (every real caller passes `.foreground` or `.dryRun`), but
            // it must still emit contract-accurate argv if it is ever wired up.
            argv.append("--no-wait")
        case .stream:
            argv.append("--stream")
        case .tryFix:
            argv.append("--try-fix")
        case .dryRun, .foreground:
            break
        }

        // Teaching action is the spend twin of dry-run — never re-emit --dry-run.
        if flags.json || flagMode == .dryRun || flagMode == .detach {
            argv.append("--json")
        }

        return (variables, argv)
    }
}
