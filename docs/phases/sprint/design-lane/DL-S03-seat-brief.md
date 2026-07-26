# DL-S03 — Design seat brief: leave one captureable file

Status: **done** (DL-S03)
SSOT: `docs/phases/Design_Lane.md` §§Path selection, Path declaration, Self-determination

## Goal

Teach design seats to leave one host-captureable HTML/SVG and declare
`native | html | concept` so WebKit capture (DL-S02) has an honest input.

## Copy-paste prompt

```text
You are implementing DL-S03 ONLY (Design seat brief + path declaration).

Read:
- docs/phases/sprint/design-lane/DL-S03-seat-brief.md
- docs/phases/Design_Lane.md
- docs/operations/Execution-Playbook.md §Commits

Implement:
1. Design-lane seat prompt profile / skill brief: one screen or one HTML file;
   write runDir/option_<id>.html (or declare path); emit path declaration line;
   no Midjourney default; Allnighter-native SwiftUI only when the target is this app.
2. Wire brief into the design team answer seats (BuiltInTeams / skill catalog /
   prompt profile — whichever is the real owner today). Keep tiny.
3. Tests: brief contains capture convention + ban on silent diffusion; path
   declaration parse if you add a parser.
4. Commit. Grok 4.5 / Composer only.

Out of scope: native capture camera, pick UI, redesign of Lead.

Proof:
swift test --package-path Packages/AllnighterCore --filter 'Design|PromptProfile|Skill'

Done when: design seats get the brief; tests green; committed.
```

## Touch allowlist

- Skill / prompt profile files for design seats (discover from BuiltInTeams)
- Small parser helper only if needed for path declaration
- Matching tests
- This sprint doc status → `done`

## Works Test

```bash
swift test --package-path Packages/AllnighterCore --filter 'Design|SkillCatalog'
```

## Done when

- [x] Design answer seats receive captureable-file brief
- [x] Path declaration required in brief
- [x] Committed
