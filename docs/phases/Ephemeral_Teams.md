# Ephemeral Teams — Brainstorm

Status: **Open / consult** — not authorized for implementation  
Updated: 2026-07-28  
Owner: Founder + product review

## Problem

Custom teams created during relay, pilot, or agent sessions are **durable by default**.
`alln teams duplicate` → edit seats → `alln run --team custom_…` writes
`~/Library/Application Support/Allnighter/Catalogs/teams/<id>.json`. Every duplicate
appears in the composer Team picker, Teams launcher, and `alln menu`.

Founder report (2026-07-28): 50+ teams in the picker, most named like
`Spec Review Min (Cursor …)` — throwaway seating experiments that were never meant
to be a permanent library entry. Relay/pilot does not write teams directly, but PM
agents fulfilling "seat a custom team" correctly use the catalog authoring path,
which persists.

**Related (fixed separately):** Team picker performance when the roster is large —
see team catalog caching in `TeamCatalog.swift` / `RoutingComposer.swift`.

## Goal

Support **one-off / session-scoped team seating** without polluting the user's
durable team library — while keeping an explicit path to **promote** a team the
user actually wants to keep.

## Non-goals (for this brainstorm)

- Replacing built-in teams or Team Studio for intentional customization
- Resuming Team Lab economics / ablation
- Changing relay/pilot worker seating (`pmWorkerId` / `devWorkerId` on `RelayState`)

## Constraints

- Built-in ids are an immutable public contract once used in run history
- `TeamCatalog` merge rules: saved file at built-in id = override in place
- Lab teams already hide via `typeTags: ["lab"]` — a precedent for filtered listings
- CLI, GUI, and menu must agree on what "exists" vs "hidden"

---

## Option A — `typeTags: ["ephemeral"]` (mirror lab teams)

**Idea:** Tag throwaway teams like lab teams. Filter out of `composeAllTeams`,
Teams launcher browse, and `alln menu`. Store under product catalog or a sibling
`Catalogs/ephemeral-teams/` root.

| Pros | Cons |
| --- | --- |
| Reuses lab-team hiding pattern | Still on disk unless TTL cleanup added |
| Small schema change (`typeTags`) | Agents must learn to tag (or CLI auto-tags) |
| Explicit promote = strip tag + save | Orphan files if relay dies mid-round |

**Lifecycle questions:** Delete on relay terminal status? TTL (7d)? Manual purge UI?

---

## Option B — Relay/run sidecar (never touch product catalog)

**Idea:** Store ephemeral team manifest on `RelayState` or `TeamRun` snapshot only.
Run resolver reads inline `TeamPreset` when present; catalog unchanged.

| Pros | Cons |
| --- | --- |
| Zero picker pollution | Harder reproduce (`alln run` replay needs snapshot) |
| Clear ownership (relay-scoped) | New persistence + migration surface |
| Matches mental model for pilot seating | GUI "customize for this round" needs new UX |

**Open:** Does `ArtifactWriter` / run receipt already snapshot enough to replay?

---

## Option C — Runtime seat overrides (no new team entity)

**Idea:** `alln run --team code_spec_review_min --seat model_kimi_k3 --seat model_cursor_grok_45`
(or a single `--seats` JSON flag). `TeamResolver` applies overrides at resolve time;
catalog unchanged.

| Pros | Cons |
| --- | --- |
| No catalog writes for one-offs | New CLI contract + resolver complexity |
| Agents can script without duplicate | GUI composer needs parallel UX |
| Built-in team stays SSOT for skills/lead | Multi-seat override validation is non-trivial |

**Precedent:** `--worker` already pins one seat on answer teams.

---

## Option D — Agent guidance only + bulk cleanup (no product change)

**Idea:** Update bootstrap/menu copy: *"Do not `teams duplicate` for one-off seating;
use built-in team + resolver defaults or `--worker`."* Add `alln teams purge`
for stale `custom_*` files.

| Pros | Cons |
| --- | --- |
| Cheapest | Does not stop agents that ignore guidance |
| Immediate relief via cleanup | Fights current menu teaching (`teams duplicate`) |
| No schema churn | Founder already hit 50+ teams under current guidance |

---

## Option E — TTL auto-prune `custom_*`

**Idea:** Background job deletes custom teams not referenced by any run in N days
(or never favorited).

| Pros | Cons |
| --- | --- |
| Self-healing roster | May delete something user meant to keep |
| No agent behavior change | Surprising data loss without opt-in |
| Works with existing duplicate flow | "Referenced" is fuzzy (menu favorites?) |

---

## Option F — Two-tier save in Team Studio / CLI

**Idea:** Split **"Use for this run"** vs **"Save to library"** in GUI; CLI gets
`teams duplicate --ephemeral` vs default durable duplicate.

| Pros | Cons |
| --- | --- |
| User-visible intent | Agents still need CLI ephemeral flag |
| Promote path is explicit | Two code paths through save |
| Fixes GUI customize flow too | Relay agents won't see GUI affordance |

---

## Comparison matrix

| Option | Stops sprawl at source | Agent-friendly | GUI-friendly | Replay-safe | Effort |
| --- | --- | --- | --- | --- | --- |
| A — ephemeral tag | Medium | Medium | Medium | Yes (if kept on disk) | Medium |
| B — relay sidecar | High | High (relay) | Medium | Needs design | Large |
| C — runtime overrides | High | High | Low (until GUI) | Medium | Large |
| D — guidance only | Low | Low | N/A | N/A | Small |
| E — TTL prune | Medium | High (no change) | N/A | Risky | Medium |
| F — two-tier save | High | Medium | High | Yes | Medium |

---

## Recommended direction (for discussion)

**Short term:** Option D cleanup (done ad hoc for founder) + performance fix (shipped).

**Medium term (lean):** **Option A + F** — `ephemeral` tag filtered like lab teams,
`teams duplicate --ephemeral` auto-tagged when invoked from relay context (or always
unless `--save`), promote via Team Studio "Save to library."

**Long term (if agents keep needing inline seating):** **Option C** as the run primitive;
catalog duplicates reserved for teams the user names and keeps.

---

## Questions for reviewers

1. Should ephemeral teams appear anywhere (run history, receipt, `teams show`) or
   be invisible outside the active relay/run?
2. Is TTL deletion acceptable, or must ephemeral teams survive until explicit delete?
3. Should relay **always** use ephemeral duplicate, or should the PM ask before persisting?
4. Do we need a founder-facing **"Clean up throwaway teams"** action regardless of
   which option ships?
5. Are forked custom **skills** (`"<Skill> for <Team>"`) part of the same problem?

---

## Code touchpoints (when authorized)

| Area | Files |
| --- | --- |
| Catalog model | `TeamCatalog.swift`, `TeamPreset` / `typeTags` |
| Listings | `AppModel.composeAllTeams`, `MenuCatalog`, `TeamsLauncherView` |
| CLI | `AllnighterCLI.swift` (`teams duplicate`, purge) |
| Relay | `RelayCoordinator.swift`, `RelayState.swift` |
| Agent surface | `MenuSelectionCopy.swift`, `Bootstrap.swift`, `HelpTopicRegistry.swift` |
| GUI | `TeamEditorView.swift`, `RoutingComposer.swift` |

## Proof (when implemented)

- Duplicate with `--ephemeral` → run succeeds → team absent from composer picker
- Promote → team appears in picker and survives relaunch
- Relay terminal → ephemeral teams removed (if lifecycle chosen)
- `swift test` filters: `TeamCatalog`, `MenuCatalog`, `CatalogCLI`
