import Foundation

/// Worker Done catalog writes — separate from roster-only `TeamDraft.commit()`.
public enum WorkerSkillCommit {
    public struct Request: Sendable, Equatable {
        public var skillId: String
        public var template: String
        public var modelId: String?
        public var lane: WorkLane
        public var defaultPurpose: SkillPurpose
        public var isNewSkill: Bool
        public var newSkillName: String?

        public init(
            skillId: String,
            template: String,
            modelId: String?,
            lane: WorkLane,
            defaultPurpose: SkillPurpose,
            isNewSkill: Bool,
            newSkillName: String? = nil
        ) {
            self.skillId = skillId
            self.template = template
            self.modelId = modelId
            self.lane = lane
            self.defaultPurpose = defaultPurpose
            self.isNewSkill = isNewSkill
            self.newSkillName = newSkillName
        }
    }

    public struct Result: Sendable, Equatable {
        public var skillId: SkillID
        public var modelId: String?

        public init(skillId: SkillID, modelId: String?) {
            self.skillId = skillId
            self.modelId = modelId
        }
    }

    /// Commit Worker Done: create a new skill or save an existing body at the same id.
    public static func apply(_ request: Request) throws -> Result {
        let trimmed = request.template.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw CatalogError.skillInvalid("template must not be empty")
        }

        if request.isNewSkill {
            let name = (request.newSkillName ?? "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty else {
                throw CatalogError.skillInvalid("name is required for a new skill")
            }
            let skill = try SkillCatalog.createCustom(
                lane: request.lane, name: name, purpose: request.defaultPurpose, template: trimmed
            )
            return Result(skillId: skill.id, modelId: request.modelId)
        }

        guard !request.skillId.isEmpty else {
            throw CatalogError.skillInvalid("skill id is required")
        }
        guard var existing = SkillCatalog.get(request.skillId) else {
            throw CatalogError.skillNotFound
        }

        let templateChanged = trimmed != existing.template.trimmingCharacters(in: .whitespacesAndNewlines)
        if templateChanged {
            existing.template = trimmed
            try SkillCatalog.saveEffective(existing)
        }

        return Result(skillId: request.skillId, modelId: request.modelId)
    }
}
