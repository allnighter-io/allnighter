import Foundation

/// Runtime `--seat` overrides for judgment-team crew rows (RSO-S01).
public enum TeamExplicitSeats {
    public static let explicitSeatingReason = "explicit"

    public struct CrewSlot: Sendable, Equatable {
        public var row: TeamAgentSpec
        public var stage: WorkerStage
        public var slotIndex: Int
    }

    public static func crewSlotCount(team: TeamPreset) -> Int {
        team.workerSpecs.reduce(0) { $0 + max(1, $1.count) }
    }

    public static func expandedCrewSlots(team: TeamPreset) -> [CrewSlot] {
        var slots: [CrewSlot] = []
        var index = 0
        for row in team.workerSpecs {
            let stage: WorkerStage = row.purpose == .review ? .review : .answer
            let want = max(1, row.count)
            for _ in 0..<want {
                slots.append(CrewSlot(row: row, stage: stage, slotIndex: index))
                index += 1
            }
        }
        return slots
    }

    public enum ValidationError: Equatable, Error, CustomStringConvertible {
        case requiresTeam
        case conflictsWithWorker
        case executionTeamNotAllowed(String)
        case countMismatch(expected: Int, received: Int)
        case seatUnavailable(index: Int, modelId: String, reason: String)
        case seatIncompatible(index: Int, modelId: String, skillId: String)

        public var description: String {
            switch self {
            case .requiresTeam:
                return "--seat requires an explicit --team"
            case .conflictsWithWorker:
                return "--seat and --model are mutually exclusive"
            case .executionTeamNotAllowed(let id):
                return "--seat is only valid on judgment teams; \(id) is an execution team — use --model"
            case .countMismatch(let expected, let received):
                return "--seat count mismatch: team expects \(expected) crew seat(s), got \(received)"
            case .seatUnavailable(let index, let modelId, let reason):
                return "seat \(index + 1) (\(modelId)): \(reason)"
            case .seatIncompatible(let index, let modelId, let skillId):
                return "seat \(index + 1) (\(modelId)) is incompatible with skill \(skillId)"
            }
        }
    }

    public static func validateFlags(
        seatModelIds: [String],
        explicitTeamChosen: Bool,
        explicitWorkerChosen: Bool,
        preset: TeamPreset
    ) -> ValidationError? {
        guard !seatModelIds.isEmpty else { return nil }
        guard explicitTeamChosen else { return .requiresTeam }
        guard !explicitWorkerChosen else { return .conflictsWithWorker }
        if preset.runShape == .execution { return .executionTeamNotAllowed(preset.id) }
        let expected = crewSlotCount(team: preset)
        guard seatModelIds.count == expected else {
            return .countMismatch(expected: expected, received: seatModelIds.count)
        }
        return nil
    }

    public static func resolve(
        team: TeamPreset,
        lane: WorkLane,
        effort: EffortLevel,
        seatModelIds: [String],
        models: [Model],
        readyModels: [Model],
        capabilities: (String) -> ModelCapabilities = ModelCatalog.capabilities,
        skill: (String) -> Skill? = SkillCatalog.skill
    ) -> Result<ResolvedTeamRun, ValidationError> {
        if let flagError = validateFlags(
            seatModelIds: seatModelIds,
            explicitTeamChosen: true,
            explicitWorkerChosen: false,
            preset: team
        ) { return .failure(flagError) }

        var base = TeamResolver.resolve(
            team: team, requestLane: lane, requestEffort: effort, readyModels: readyModels,
            capabilities: capabilities, skill: skill
        )

        let readyIds = Set(readyModels.filter(\.enabled).map(\.id))
        let slots = expandedCrewSlots(team: team)
        var nextIndex: [String: Int] = [:]
        var answerWorkers: [Worker] = []
        var reviewWorkers: [Worker] = []

        for (offset, slot) in slots.enumerated() {
            let modelId = seatModelIds[offset]
            guard let model = models.first(where: { $0.id == modelId }) else {
                return .failure(.seatUnavailable(
                    index: offset, modelId: modelId,
                    reason: "unknown model — run `alln menu --json`"))
            }
            guard readyIds.contains(modelId) else {
                return .failure(.seatUnavailable(
                    index: offset, modelId: modelId,
                    reason: "not ready — check `alln doctor` / `alln menu --json`"))
            }
            let caps = capabilities(modelId)
            guard caps.laneTags.contains(lane) else {
                return .failure(.seatIncompatible(index: offset, modelId: modelId, skillId: slot.row.skillId))
            }
            if !slot.row.allowedModelIds.isEmpty, !slot.row.allowedModelIds.contains(modelId) {
                return .failure(.seatIncompatible(index: offset, modelId: modelId, skillId: slot.row.skillId))
            }
            if !slot.row.requiredCapabilityTags.allSatisfy({ caps.capabilityTags.contains($0) }) {
                return .failure(.seatIncompatible(index: offset, modelId: modelId, skillId: slot.row.skillId))
            }

            let skillName = skill(slot.row.skillId)?.displayName ?? slot.row.skillId
            let instance = nextIndex[modelId, default: 0]
            nextIndex[modelId] = instance + 1
            let worker = Worker(
                id: Worker.makeID(modelId: modelId, instanceIndex: instance),
                modelId: modelId,
                instanceIndex: instance,
                skillId: slot.row.skillId,
                skillName: skillName,
                purpose: slot.stage,
                seatingReason: explicitSeatingReason
            )
            switch slot.stage {
            case .answer: answerWorkers.append(worker)
            case .review: reviewWorkers.append(worker)
            default: answerWorkers.append(worker)
            }
        }

        base.answerWorkers = answerWorkers
        base.reviewWorkers = reviewWorkers
        TeamSourceFacts.enrich(&base, models: models)
        if !base.isRunnable {
            return .failure(.seatUnavailable(
                index: 0, modelId: seatModelIds.first ?? "",
                reason: base.blockReason ?? "team cannot run with explicit seats"))
        }
        let gate = ExecutionTeamSourceGate.evaluate(resolved: base, models: readyModels)
        if let blocker = gate.sourceGateBlocker {
            return .failure(.seatUnavailable(
                index: 0, modelId: seatModelIds.first ?? "", reason: blocker.message))
        }
        return .success(base)
    }
}
