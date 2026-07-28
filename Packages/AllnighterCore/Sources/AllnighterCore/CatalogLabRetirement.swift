import Foundation

/// Team Lab is retired (founder 2026-07-24). Lab teams and lab-tagged skills must
/// never appear in the product catalog — delete on read and reject new writes.
public enum CatalogLabRetirement {
    /// Historical Team Lab custom skills used ids like `custom_code_lab_bug_reproducer`.
    public static func isLabSkillId(_ id: SkillID) -> Bool {
        id.contains("_lab_")
    }

    /// Delete all `Catalogs/lab-teams/*.json` and lab-marked skills under
    /// `Catalogs/skills/`. Idempotent.
    @discardableResult
    public static func purgeRetiredLabArtifacts() -> (teams: [TeamID], skills: [SkillID]) {
        var deletedTeams: [TeamID] = []
        for team in CatalogFileIO.loadAll(kind: .team, root: CatalogRoots.labTeams, as: TeamPreset.self) {
            try? CatalogFileIO.delete(id: team.id, root: CatalogRoots.labTeams)
            deletedTeams.append(team.id)
        }
        var deletedSkills: [SkillID] = []
        for skill in CatalogFileIO.loadAll(kind: .skill, root: CatalogRoots.skills, as: Skill.self) {
            guard isLabSkillId(skill.id) else { continue }
            try? CatalogFileIO.delete(id: skill.id, root: CatalogRoots.skills)
            deletedSkills.append(skill.id)
        }
        return (deletedTeams.sorted(), deletedSkills.sorted())
    }
}
