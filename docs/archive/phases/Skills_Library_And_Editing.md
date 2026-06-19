# Skills Library And Editing

Status: Archived 2026-06-19; superseded by `docs/phases/Team_And_Skill_Catalogs.md`
Owner: AllnighterCore + AllnighterCLI + Mac GUI
Updated: 2026-06-17

This packet is intentionally retired.

The old shape split skills away from teams, introduced `SkillStore`/`TeamStore`
language, and treated `team edit` as deferred from custom skill editing. That is
no longer the model.

Read the replacement spec:

```text
docs/phases/Team_And_Skill_Catalogs.md
```

Current law:

```text
TeamCatalog   = every team definition Allnighter knows about
SkillCatalog  = every skill definition Allnighter knows about
TeamID        = stable machine id for one team definition
SkillID       = stable machine id for one skill definition
```

No Store vocabulary. No migration burden. No skill versioning in the MLP. Runs
may snapshot the resolved skill content they used.
