# Runtime Seat Overrides

Status: **Ready** — Option C locked; no interim; authorized for implementation  
Owner: AllnighterCore (`RunService` / CLI / agent surface)  
Created: 2026-07-28 (brainstorm)  
Updated: 2026-07-28 (finalized)  
Process: `docs/workflows/SSOT_Founder_Input_Workflow.md` →
`docs/workflows/SSOT_Feature_Workflow.md`  
Depends on: code SSOT `RunService.swift`, `TeamPreset` / `TeamCatalog`,
`TeamRequestResolver.swift`, `ExactIdResolver.swift`, `--worker` honor-or-fail
precedent (PO-F10 / MR-S04); agent surface `MenuCatalog` / `MenuSelectionCopy` /
`HelpTopicRegistry` / `Bootstrap`

---

## Founder intent

Raw request (dogfood):

```text
Run a Spec Review team on this doc using alln and staff only sol from codex,
grok 4.5 from grok, and composer 2.5 from cursor.
```

That is a **run gesture** (built-in job + one-off seats), not a **bench gesture**
(save a named team to the library). Today every such ask becomes another durable
`custom_*` team and pollutes the picker.

## Problem

`alln run` accepts `--team <id>` and can pin **one** seat via `--worker` on
answer/mutating teams. It has **no** flag to reseat a multi-seat judgment team
inline.

Agents correctly fall back to the only multi-seat customize path the product
teaches:

1. `alln teams duplicate <built-in> …`
2. Edit seats (`teams edit` / JSON under
   `~/Library/Application Support/Allnighter/Catalogs/teams/`)
3. `alln run --team custom_…`

Step 1 writes the durable catalog. Relay/pilot do not invent teams themselves;
PM agents fulfilling “staff these models” use that authoring path, so every
one-off seating experiment becomes a permanent library card.

Founder report (2026-07-28): 50+ picker entries, mostly
`Spec Review Min (Cursor …)` throwaways. Team list became unusable.

**Related (shipped separately):** picker performance under a large roster —
catalog caching in `TeamCatalog.swift` / `RoutingComposer.swift`.

## Goal

One atomic run command reseats a built-in (or saved) team **for that run only**.
Zero catalog writes. Catalog `teams duplicate` reserved for teams the user
explicitly wants on the bench.

## Locked decision

**Option C — runtime seat overrides on `alln run`.** Clean cut.

| Keep | Drop |
| --- | --- |
| Built-in team = job/method SSOT (skills, lead, synthesis, lane, envelopes) | `typeTags: ["ephemeral"]` / lab-style hide |
| Ordered `--seat` overrides for this run only | Two-tier `duplicate --ephemeral` vs `--durable` |
| Resolved roster on run receipt / journal (already) | Relay/run sidecar team entities |
| `teams duplicate` = intentional library save only | TTL auto-delete of customs |
| Founder purge of existing throwaways (recovery) | Guidance-only “don’t duplicate” without a primitive |
| | Skill forks for one-off seating |

No users to migrate. No compatibility aliases. No interim hide-the-mess path.

## Why C (and only C)

| Criterion | Verdict |
| --- | --- |
| Stops sprawl at source | Yes — no entity created |
| Agent-simple | One command; no duplicate → edit → run |
| Preserves team posture SSOT | Skills / lead / judgment rules stay on `--team` |
| Replay / audit | Receipt + journal already record resolved workers |
| Matches founder speech | “staff only X, Y, Z” on a named team |

Rejected alternatives (consult record only — do not implement):

- **A / F (ephemeral tag + two-tier save)** — still teaches “make a team,” then
  hide/promote/TTL. Wrong object for one-off seating.
- **B (relay sidecar)** — too narrow; the same ask happens on plain `alln run`.
- **D (guidance only)** — already failed; help teaches `teams duplicate`.
- **E (TTL prune)** — deletes after damage; surprising for anything meant to keep.

## Agent-facing contract

### Teaching story (three lines)

| Intent | Gesture |
| --- | --- |
| Run a job with default seats | `alln run --team code_spec_review_min …` |
| Run a job with these models once | `alln run --team … --seat <model_id> …` |
| Keep a lineup on my bench | `teams duplicate` → name it → save |

### Canonical shape

```bash
alln run --team code_spec_review_min \
  --seat model_codex_sol \
  --seat model_grok_45 \
  --seat model_cursor_composer_25 \
  --prompt "Review docs/phases/Ephemeral_Teams.md"
```

Repeated `--seat <model_id>` flags, **in crew order**, replace the crew model
identities of the resolved `--team`. Skills, lead, synthesis policy, lane, and
judgment envelopes stay on the team.

### Semantics (locked)

1. **Base team** resolves exactly as today (`TeamRequestResolver` +
   `ExactIdResolver` on `--team`).
2. **`--seat` count must equal** the base team’s crew size
   (`workerSpecs` seat count). Wrong count → fail loud (`CLI_USAGE_ERROR` /
   dedicated seat-override code). No silent truncate/pad.
3. Each `--seat` value is an exact model id (same honor-or-fail posture as
   `--worker`). Unknown / not-ready → fail loud; never invent a substitute for
   an explicit seat.
4. **Lead is unchanged** by `--seat` (follow-up `--lead` is out of scope for v1
   unless a slice proves it is needed).
5. **Skills stay with the team.** Do not fork skills for one-off seating.
6. **Mutating / execution-source gate still applies** after override (mixed
   sources on a mutating team still fail closed).
7. **`--worker` unchanged** — still the single-seat pin for answer / Default
   Team / mutating one-worker runs. Do not overload `--worker` as multi-seat
   reseat; agents must use `--seat` for multi-crew judgment teams.
8. **No catalog write** when `--seat` is present. Effective roster is whatever
   the run already persists (resolved workers on `TeamRun` / receipt / journal).
9. **Reproduce / dry-run** must echo the same `--seat` flags that were accepted.

### Exact founder scenario

| Flow | Steps | Catalog |
| --- | --- | --- |
| **Broken (today)** | duplicate → edit `custom_*.json` → `run --team custom_*` | Permanent file; picker grows |
| **Fixed (this packet)** | one `alln run --team code_spec_review_min --seat …` ×3 | Zero files written |

## Agent surface cutover

Update in the same implementation pass as the flag (not a soft follow-up):

| Surface | Change |
| --- | --- |
| `MenuSelectionCopy` / `MenuCatalog` | `run`: useWhen covers one-off seating via `--seat`; `teams duplicate` dontUseWhen = one-off seating — use `--seat` on `run` |
| `HelpTopicRegistry` (`teams_and_workers`) | Teach `--seat` as the reseat path; duplicate only for library saves |
| `Bootstrap` / teaching snippets | One line: custom seats for a single run → `--seat` on `alln run`; do not duplicate |
| `ContractRegistry` | Flag + error specs for `--seat` |

## Founder recovery (not the product model)

Existing throwaway `custom_*` files are debt from the broken path. Ship a
**one-shot cleanup** so the bench is usable again:

```text
alln teams purge --unused
```

Suggested meaning: custom teams with no (or zero recent) run history, or an
explicit allowlist of throwaway name patterns — fail closed / dry-run first;
never delete built-ins; never delete a custom the founder named as a keeper
without confirmation. This is recovery hygiene, not ongoing architecture.
TTL auto-prune is still rejected.

## Non-goals

- Ephemeral catalog entities, tags, or TTL
- Replacing built-ins or Team Studio for intentional durable customization
- Resuming Team Lab
- Changing relay/pilot PM/dev seating (`pmWorkerId` / `devWorkerId`) — those
  already pin seats without inventing teams; nested judgment runs use `--seat`
- GUI composer reseat UX in v1 (CLI + agent path first; GUI can mirror later)
- Per-seat `skill:model` surgery or JSON `--seats` blobs in v1
- Forking skills for one-off runs

## Implementation slices

| Slice | Goal | Done when |
| --- | --- | --- |
| **RSO-S00** | Founder purge | `alln teams purge --unused` (or equivalent) removes throwaway customs; dry-run + explicit paths; built-ins untouched |
| **RSO-S01** | Resolver + CLI `--seat` | Repeated `--seat` reseats crew in order; count/id fail loud; no catalog write; mutating source gate still holds |
| **RSO-S02** | Persistence / reproduce | Accepted seats appear on run record; `reproduce` / dry-run argv includes `--seat`; receipt honest |
| **RSO-S03** | Agent teaching | Menu / help / bootstrap / ContractRegistry teach `--seat`; `teams duplicate` no longer the one-off path |

Slice order: S00 can ship first for relief; S01 is the core fix; S02/S03 must
land before calling the packet done (agents will keep duplicating if teaching
lags the flag).

## Code touchpoints

| Area | Files |
| --- | --- |
| Resolve / run | `TeamRequestResolver.swift`, `RunService.swift`, `ResolvedRunInvocation.swift`, seat resolution near `--worker` honor-or-fail |
| CLI | `RunCLI.swift`, `AllnighterCLI.swift`, `ContractRegistry` (+ milestone flag/error specs) |
| Catalog cleanup | `TeamCatalog.swift`, Catalog CLI (`teams purge`) |
| Agent surface | `MenuSelectionCopy.swift`, `MenuCatalog.swift`, `HelpTopicRegistry.swift`, `Bootstrap` / teaching |
| Proof | Engine/CLI tests for override count, unknown id, no `saveCustom` side effect, reproduce argv |

## Works Test / proof

```text
1. alln run --team code_spec_review_min --seat A --seat B --seat C …
   → run accepts; Catalogs/teams/ unchanged (no new custom_*)
2. Wrong --seat count → loud CLI error; no spawn
3. Unknown model id on --seat → loud error; no silent substitute
4. alln reproduce / dry-run echoes the same --seat flags
5. Menu/help: one-off seating points at --seat; duplicate dontUseWhen matches
6. (S00) purge --unused removes founder throwaways without touching built-ins
7. swift test (focused): seat override + catalog CLI + menu copy contracts
```

## Open only if blocked in implementation

These are **not** product reopeners; resolve inside the slice if they appear:

- Exact crew-count definition when a `workerSpec` has `count > 1` (expand to
  N ordered `--seat` values vs reject multi-count specs for override) — pick one
  rule, document in S01, test it.
- Whether GUI composer needs a parallel “staff for this send” control before
  archive — default **no** for v1; file a follow-up packet if dogfood demands it.
