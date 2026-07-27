# Team command center — Allnighter UI kit (macOS)

This kit is the destination for the title-bar ready pill (`5/5 healthy`) in the
Judgment shell. It owns source/CLI readiness, repair actions, and the lane
benches where models become workers through `Skill | Model` assignments.

## Flow

1. **Ready** — source-level health for the CLIs/app bridges Allnighter can run.
   This is where a broken source is re-checked, signed in, or pointed at a
   binary. The tally is source-level, not worker-level.
2. **Build bench** — ready Build-capable models plus the default Build team.
   Type and effort are visible; `Customize team` opens the row editor.
3. **Design bench** — image/design-capable models plus the default Design team.
   Design workers are still `Skill | Model`, including image engines and
   critique workers.
4. **Copy bench** — placeholder parity with the same model while the copy phase
   owns its detailed playbooks.
5. **Skills** — lane-tagged skill library used by presets.

## Files

- `index.html` — mounts the Team command center. Query helpers:
  `?view=ready`, `?view=build`, `?view=design`, `?view=design&drawer=1`.
- `data.jsx` — sample sources, Bench models, lane skills, and presets.
- `chrome.jsx` — macOS window frame, ready pill, left nav.
- `screens.jsx` — Ready, Bench, Skills, and Customize drawer views.

## Product language

Follows `docs/workflows/Product_Vocabulary.md`:

- **Source** = how Allnighter reaches a model.
- **Bench** = available models.
- **Skill** = reusable hat/instruction.
- **Worker** = one model wearing one skill for a run.
- **Team** = the worker lineup for a work order.
