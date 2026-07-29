# Product Vocabulary

Standing word-list for product, GUI, CLI, and docs. **Not a phase packet.**

**Code SSOT for runs:** `RunService.swift`, `TeamPreset` / `TeamCatalog`,
`RunWriteLockRegistry`.
**Closed cutover records:** `docs/archive/phases/Language_Cutover.md`,
`docs/archive/phases/Work_Order_Team_Model.md`,
`docs/archive/phases/Team_Depth_Naming.md`.

Hard rule: **no aliases** for retired product words. Prefer rename over dual
paths.

---

## Human layer

| Word | Meaning |
| --- | --- |
| **Chat** | The default turn surface inside a Project — a run of the Default Team. |
| **Delegate** | Hand intent to a team. UI label: **Send to team** (retired: Fan out). |
| **Execute** | Authorize a make-real / mutating send. **Not** a composer mode. |
| **Team** | The actor noun — the agent lineup you send to. |
| **Crafts** | **Code · Design · Copy** (+ **Signal** scout). Code was: Build. |
| **Signal** | Repo-aware scout: outside → insights (not “move cards”). |
| **Project** | Local repo/folder floor where work happens. |

`lane` means **craft** (Code/Design/Copy/Signal). It is never “a single run.”

## Machine layer

One primitive: **run a team** (a solo agent is a team of one). A team carries
`craft` + `mutating:bool`. No approval gate on mutating runs — `RunService`
executes once the team resolves to one agent seat.

Retired ceremony (do not revive): propose → approve → dispatch → verify as a
separate Project Manager spine; posture enum `propose|review|execute|scout` as
product gates.

## Team model nouns

| Term | Meaning |
| --- | --- |
| **Source** | How Allnighter reaches a model (CLI/runtime). Setup/internal. |
| **Execution source** | The single source/driver that owns a mutating run. |
| **Bench** | Models the user has available. |
| **Model** | Recognizable AI identity (Opus, Grok, …). CLI pin: `--model <model_id>`. |
| **Agent** | A staffed roster row: one **model** wearing one **skill** on a team. Count plural: **agents** (not models — four Auto seats are four agents, not four models). |
| **Skill** | Hat / instruction profile a model wears. Shared by `skillId` across teams; the editable body is **skill.md** (the `template` field in catalog JSON). Same-ID overrides edit in place; **Restore** drops the override. Mac drill-in: **Edit skill**. |
| **Type** | Optional subtype metadata inside a craft; not a Send-to-team selector. |
| **Reasoning effort** | Per-agent model reasoning (`low|med|high` when supported). Never changes lineup, depth, or flavor. |
| **TeamPreset** | Saved team definition (lane, agents, synthesis policy). UI says Team. |

**Retired (user-facing):** **Worker** — do not use in GUI, CLI flags, help, or
docs. Never teach `worker*` to humans.

**Machine contracts** (TeamRunJSON, floor, NDJSON stream, threads, pending,
handoff mailbox, spec retrieval): staffed seats expose **`agentId`**; catalog
pins expose **`modelId`**. Never overload one field for both meanings.

**Layer E (internal only — not product seats, not agent-facing wire):** journal
`TeamRun.workers`, `workerAnswer(workerId:)`, internal `RunEvent` payload keys,
process ownership (`WarmWorker*`, `kind: "worker"`), on-disk `workers/`
artifact directories. These stay until an explicit process-layer cutover.

Historical cutover record: `docs/archive/phases/Worker_To_Agent_Migration.md`.

Shortcut: *Model at rest. Agent at work (model + skill).*

### CLI pins (no aliases)

| Flag | Meaning |
| --- | --- |
| `--model` | Pin which model runs (`alln run`, `alln thread send`, `alln pending add`, …). |
| `--dev-model` / `--pm-model` | Relay/pilot seat model ids. |
| `--seat` | Ordered model ids for one-off judgment-team staffing (not a synonym for `--model`). |

Retired flags: `--worker`, `--dev-worker`, `--pm-worker`. Retired commands:
`alln project workers` → `alln project models`.

### Execution source gate

Judgment / research teams may mix sources. Mutating teams must resolve to
**exactly one** source/driver before spawn. Do not silently pick the first ready
source, flip mutating off, invent mirrors, or spawn multiple CLIs as “one”
execution team. Shared blocker: `EXECUTION_TEAM_MIXED_SOURCES`. Historical
proof: `docs/archive/phases/Execution_Team_Source_Gate.md`.

### Effort vs depth

- **Effort** = model reasoning only.
- **Depth** = a different **named Team** (Min / bare / Max), never an effort dial.

---

## Team depth naming (Min / Default / Max)

1. **Family name = the job** (Spec Review, Bug Hunt, …). One name in picker,
   docs, and marketing.
2. **Depth vocabulary:** Min / (bare name) / Max. IDs: `<family>_min` /
   `<family>` / `<family>_max`.
3. **Bare name is the default.** Picker may show “Default” as a UI label only —
   it never appears in the team name, ID, or CLI id.
4. **No numbers in names.** Seat count is metadata, not the name.
5. **Not every family ships all three tiers.** Unique names only for different
   jobs (e.g. Polish vs Usability Review), not for depth.
6. **Routing:** auto / default send → bare team. Min is always an explicit
   choice. Escalation may recommend Max; never silent switch.
7. **Min** = smallest curated roster that keeps the family’s core outcome.
   **Max** = every seat that earns its place on the hardest case class.

Roster truth lives in `BuiltInTeams.swift` / `TeamCatalog`.

---

## Substitution tiers (Frontier / Balanced / Economy)

Auto and healthy substitution draw from a **tier** — an ordered roster, not a
model property. Distinct from team depth (Min / bare / Max) and from caliber
(seating strength).

| Tier | Meaning |
| --- | --- |
| **Frontier** | Smartest models you are willing to spend on Auto |
| **Balanced** | Everyday workhorses |
| **Economy** | Lowest acceptable spend for Auto |

- IDs / CLI / JSON: `frontier` | `balanced` | `economy`.
- **Retired tier names:** `flagship`, `fast` — still parse from old settings files
  but must not appear in new Allnighter copy, help, or UI.
- **Never use “Fast”** as a tier label — vendor model names already use it
  (`Composer 2.5 Fast`, etc.).
- Code SSOT: `DefaultModelSettings.swift`, `DefaultSettingsJSON`, `alln defaults`.
