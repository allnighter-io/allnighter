# Agent Onboarding — from findable to suggested

Status: **APPROVED, BLOCKED on IR-S02.** RLR-S06 cleared 2026-07-19
(archived `Run_Lifecycle_Reliability.md` Complete) — lifecycle trust is green.
Build only after `Agent_Intent_Router.md` IR-S02. IR-S01 landed as `3d515ff0`;
the router intentionally stopped there.
Specced v2 — hardened by five-seat panel panel_753613c7 (2026-07-16:
21 findings across consent/simplify/adoption/failure-modes/strategy lenses;
accepted set folded below). v3 sharpening (2026-07-18): trigger line points at
the intent router; recipes retitled by intent; works test made adversarial.
v3.1 (2026-07-19): works-test battery gains the named-worker/read-only
utterance class surfaced by a live cold-agent probe (see
`Agent_Intent_Router.md` field evidence); Sol read-only review hardening —
one-source-per-artifact-class SSOT fix, discovery-vs-execution split in the
trigger line, snippet blocks on IR-S01+S02, marker version+hash doctor
states, host support matrix + filesystem contract in S03, reproducible
battery harness. v3.2 (2026-07-19): first-contact **single-worker review**
recipe — run-vs-team, `--project` required, Codex Sol vs Cursor Sol, silent
`--json`, paste-ready snippet (field footguns from the Isolation/Perf Sol
audit via `alln run --worker model_chatgpt`). v3.3 (2026-07-19): Kimi lifecycle
failure makes observable/stoppable/recoverable runs a blocking prerequisite;
the single-worker recipe no longer teaches indefinite silence as healthy.
v3.4 (2026-07-19): RLR gate cleared; Onboarding V1 still waits on IR-S02.
V1 = three slices after IR-S02; the rest parked.
Owner: Mac app (first-run/Settings) + AllnighterCore content SSOT + bootstrap
Updated: 2026-07-19

Related: `Agent_Front_Door.md` (gate 1 — findable, SHIPPED) · this doc (gate 2 —
suggested) · `Agent_Intent_Router.md` (gate 3 — routes intent to the right team;
the trigger line below depends on it) · archived `Run_Lifecycle_Reliability.md` (P0 trust
gate — the recommended work remains observable, stoppable, and recoverable).

## The gap (named precisely)

`Agent_Front_Door.md` made Allnighter FINDABLE for agents that go looking (`alln
bootstrap`, install-cli, no empty silence). Nothing yet makes it SUGGESTED. The
real failure: a user installs the app, opens Claude Code, says "route this to
Grok" — the session reads its context files (CLAUDE.md, AGENTS.md,
`.cursor/rules`), finds nothing about Allnighter, and improvises. `alln
bootstrap` is a great snippet nobody runs, because running it requires already
knowing alln exists. The install-cli chicken-and-egg, reborn for knowledge.

**The app is the only actor present at install time** — the one surface that
exists before any agent session does. It must be the missionary.

## Decisions (proposed — harden via panel)

1. **Three touchpoints, ONE source per artifact class.** (Precision fix — the
   earlier "one content source" phrasing contradicted Decision 2's file-based
   recipes.) Each artifact class has exactly one named source: the trigger
   snippet's SSOT is the Core bootstrap content; the recipe cards' v1 SSOT is
   the shipped `.md` files themselves; ContractRegistry `example-recipes` is a
   separate machine artifact. Where one artifact embeds another (the bootstrap
   snippet inlined in each recipe card), the embed is covered by the drift
   test — never hand-authored twice (the board-staleness lesson).
2. **Recipes are literal files — and the files ARE the v1 SSOT.** (Core
   registry/`--recipe` export deferred until drift is measured pain — panel
   simplify consensus.) NAMED DECISION: these prompt cards COEXIST with
   ContractRegistry's `example-recipes` (machine command snippets); they are
   different artifacts for different readers — revisit merge only if they
   drift toward each other. A "Use from your CLI" surface in the app that
   is actually a shipped folder of `.md` recipe cards, **titled by user intent,
   not product noun** (panel v3): "Get another model to implement this" ·
   "Challenge this decision before I commit" · "Keep working while I'm away" ·
   "Ask several models and compare" · "Recover a run that lost its terminal" ·
   "Use a specific model without silent substitution". ("Get Grok to build this
   while Claude supervises" sells the outcome; "Pilot a spec" only lands after
   someone already knows Pilot.) Each card carries **3 example user utterances**
   (agents pattern-match utterances better than prose) + the bootstrap snippet
   inlined + the specific recipe, all copy-paste-ready.
   Copy button in the app; open-format files on disk so agents (and screenshots)
   can read them. Every recipe must be one we have actually run — zero unearned
   prompts. Vocabulary check: current product words only ("Delegate work to
   another model", never retired craft names).
3. **One-click snippet install — GLOBAL scope only, consent drawn precisely.**
   First-run (after the bench-ready banner) + Settings: "Teach your CLIs" →
   detect GLOBAL-scope targets ONLY (`~/.claude/CLAUDE.md`, the global cursor
   rules path — per-host enumeration is part of the slice; project-scope files
   are NEVER touched by the global installer) → PREVIEW exactly what will be
   appended → write on the user's explicit click. Idempotent repair shows a
   DIFF first when content inside the markers was hand-edited; removal strips
   the marked section byte-cleanly; write failures surface, never silent. This
   is a deliberate, documented carve-out from the CLI's print-never-edit
   posture (the CLI still never edits; the app on a human click is the user's
   hands — state this in the Bootstrap.swift comment when built).
4. **The trigger line teaches ONE reflex: ask the router.** (v3 sharpening —
   teach the reflex, not the catalog.) The snippet stays tiny and intent-shaped:

   > Allnighter coordinates the AI CLIs installed on this Mac. When another model
   > could improve the answer, build the work, or continue without the user, run
   > `alln team hello --for "<the user's intent>" --json` — it is read-only and
   > free, so ask it whenever unsure. Run its recommended command only when the
   > user's request already authorizes that work (it may spend model quota or
   > change files). Never manually substitute a requested worker.

   Two laws inside that wording (panel/Sol hardening, 2026-07-19): **asking the
   router is always safe; executing its answer needs the same authorization any
   mutating/spending action needs** — the snippet must never teach "auto-run
   whatever comes back." And the snippet's field reference must quote the
   FROZEN router contract's exact field names (`recommended.command` etc. —
   the earlier draft said singular "nextAction" against a plural `nextActions`
   schema; a cold agent can't guess which field to execute).

   This is deliberately smaller than v2's four-mechanic list ("routed/delegated/
   unattended/judged"): the agent no longer has to translate a taxonomy or
   memorize team ids — it asks the router (`Agent_Intent_Router.md`) and gets an
   exact command back. Three intuitive branches fall out for humans: improve the
   answer · build the work · continue unattended.

   **BLOCKING dependencies:** this trigger line points at `team hello --for`, so
   the intent router's command contract must be frozen before this snippet
   ships — otherwise it teaches a command that doesn't route. That means
   **IR-S01 AND IR-S02**: the works-test battery below exercises named-worker
   resolution, Chat/Pilot/Relay targets, and requested-worker honesty, which
   are IR-S02 behavior — blocking on IR-S01 alone would ship a snippet whose
   own battery can't pass. It remains
   a BLOCKING prerequisite for the installer slice for the same reason as v2
   (a mechanics-only snippet teaches a dictionary entry, not a reflex). The
   frozen contract must include the router's named-worker resolution and
   read-only-ask routes (`Agent_Intent_Router.md` Decisions 8–9) — a live probe
   showed "ask <named model> for feedback, change nothing" is exactly where a
   cold agent stalls today, so a snippet that sends agents to a router that
   can't answer it teaches the reflex and then punishes it. Size
   budget holds — smaller than before. **IR-S02 is unblocked** (RLR-S06 Complete
   2026-07-19). Onboarding remains blocked on IR-S02 only — it must not teach
   more agents to launch work until named-worker / long-run control bundles
   exist. Success criterion (golden-transcript
   gate): a fresh session given the snippet reaches for `alln team hello --for`
   on "route this to another model" — named, not v1.
5. **Per-project offer (PARKED until v1 proves).** A repo's AGENTS.md is a
   SHARED file — one person's click changes teammates' agents. When built: the
   offer writes the marked section UNCOMMITTED and stops — the user's own git
   review/commit makes it team-visible through the normal flow (Allnighter
   never commits; panel consensus). Lifecycle questions (multi-project,
   downstream cloners, snippet evolution) recorded, unresolved.
6. **(PARKED until v1 proves) Teach at the moment of demonstrated intent.** When a first pilot/panel/
   relay completes in the app's inbox, the done card offers: "next time, run
   this from your CLI — copy this prompt." Graduation nudge exactly when the
   value was just felt.

## Anti-goals

- No always-loaded context walls — the snippet stays within its size budget;
  the trigger line is one sentence. (We retired MCP over this exact tax.)
- No auto-editing vendor/agent files without the explicit click — preview
  first, marker-delimited, removable. CLI never edits, ever.
- No interactive "tutorial mode" in the CLI — agents learn via help/bootstrap/
  MEMORY.md, humans via the app.
- The CLI NEVER writes vendor/agent files — refuted the panel's `--write-rules`
  flag suggestion: one posture per surface, no exceptions; the app owns clicks.
- No hand-authored duplicate content — SSOT or it rots.

## Slices (proposed)

V1 = three slices (panel simplify consensus); everything else parked until the
works test is green. No ONB slice starts before IR-S02 (RLR-S06 already Complete).

| Slice | Deliverable |
| --- | --- |
| ONB-S01 | Bootstrap trigger line + size-budget test (BLOCKING for S03) + a `teaching.installed` doctor check per global target. The marker carries a **schema version + content hash**, so doctor distinguishes installed / absent / **stale** (older snippet version) / **modified** (hash mismatch — user hand-edit, never destructively repaired) / **malformed** — a bare installed/absent bit can't drive safe repair. (The mechanical stand-in for the untestable "cold user never clicks" path.) |
| ONB-S02 | Shipped recipe `.md` folder (v1 SSOT) + app "Use from your CLI" surface with copy buttons (GUI proof gate applies). Names the canonical on-disk install path, update-on-app-update behavior, and how an agent discovers the folder — an unfindable recipe file is a dead recipe. |
| ONB-S03 | App one-click GLOBAL snippet install: per-host target enumeration (global paths only) including the **v1 host support matrix** — which hosts actually load a global instructions file, exact path per host, and what unsupported hosts show in UI/doctor; preview (names every affected host + states the instruction applies across all projects + detects pre-existing/older-format Allnighter blocks and offers repair, never a duplicate append); marker append/repair-with-diff/remove under an explicit filesystem contract (missing-file creation, symlinks, CRLF preservation, malformed/duplicate markers, atomic write, preview→click content drift re-check); write-failure surfacing |
| PARKED | Per-project AGENTS.md offer (uncommitted-write discipline specced above) · done-card graduation nudge + CLI nextActions echo · Core recipe registry/`--recipe` |

## Works test (adversarial — v3)

A fresh machine-state simulation: install app → click "Teach your CLIs" → open a
new agent session → the session reaches for `alln team hello --for` **unprompted,
on a battery of utterances that never name Allnighter**:

- "Ask Grok to implement this."
- "Can you get a second opinion?"
- "Keep going tonight without me."
- "Use whichever of my other subscriptions is free." ("free" = ready per
  source health — authenticated + not down; quota/cost semantics are out of
  scope for v1 and this row routes to Auto)
- "Have Claude review what Codex changed."
- "Get Sol's take on this spec — don't change anything." (named worker +
  read-only: exercises name→id resolution across drivers and the
  no-silent-substitution law, the field-probe stall case)

A cold agent should suggest `alln` for each — that's the reflex firing, not
recall of a specific noun. The battery is a **reproducible harness, not an
anecdote**: pinned host fixtures (host + version + clean global state), the
snippet installed by the real installer, N trials per utterance with a stated
pass threshold, and the expected observable = the agent invoking (or explicitly
proposing) `alln team hello --for`. One lucky session proves nothing. Recipe copy-paste runs end-to-end for at least
delegate + panel. Removal click leaves vendor files byte-clean outside the
markers. Snippet size budget green (smaller than v2); recipes render from SSOT
(drift test).

## First-contact: single-worker review (paste-ready)

When the ask is **"get Sol's take on these docs — change nothing"** (one named
worker, one ask, read-only), use `alln run` — **not** a multi-seat team. Field
footguns from the 2026-07-19 Isolation/Perf Sol audit:

1. **Run vs team.** One worker / one ask → `alln run --worker …`. Multi-seat
   judgment → `alln team --team …`. Never collapse "send to Sol" into Spec
   Review (or any panel) — that burns seats the user did not ask for.
2. **`--project` is required today.** Omit it and you get
   `CLI_USAGE_ERROR: --project required`. Pass `--project <id|path>` every
   time. **Product gap (desirable):** defaulting to cwd when unambiguous would
   remove this cold-agent stall; not shipped yet.
3. **Codex Sol ≠ Cursor Sol.** Same model family, different driver:
   `model_chatgpt` = Codex (`gpt-5.6-sol`); `model_chatgpt_sol` = Cursor.
   Prefer `model_chatgpt` when the user says "Sol" without naming a host.
4. **Transport truth is bounded.** `--json` is final-only and may be silent until
   finish; it is not a monitoring transport. For a long run, use `--stream`,
   capture the canonical run id from its first NDJSON event, and use the exact
   monitor/cancel commands returned by the router. Silence alone proves neither
   health nor failure: lifecycle phase, causal blocker, `lastActivityAt`, and
   `progressStale` own that judgment (archived `Run_Lifecycle_Reliability.md` Complete).
   Recipe shipping still waits on IR-S02 for the router-returned monitor/cancel
   argv.

**Paste-ready (Codex Sol, named docs, read-only):**

```bash
alln run --project <id|path> --worker model_chatgpt --lane code --no-commit --stream \
  "Read-only review of <path/to/Doc_A.md> and <path/to/Doc_B.md>. Do not edit files. Return findings only."
```

Swap `--stream` for `--json` only when the caller wants one terminal
machine-readable blob and does not need live control through that stdout stream.
Router still owns the long term ("ask `team hello --for` first") and, after
IR-S02, returns the matching monitor/result/cancel argv. This recipe is
the honest direct command when the agent already knows it wants one named worker.
