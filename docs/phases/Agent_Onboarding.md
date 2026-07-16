# Agent Onboarding — from findable to suggested

Status: Specced v2 — hardened by five-seat panel panel_753613c7 (2026-07-16:
21 findings across consent/simplify/adoption/failure-modes/strategy lenses;
accepted set folded below). Awaiting founder go. V1 = three slices; the rest parked.
Owner: Mac app (first-run/Settings) + AllnighterCore content SSOT + bootstrap
Updated: 2026-07-16

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

1. **Three touchpoints, ONE content source.** All onboarding content renders
   from the same registry/help SSOT that powers `alln help` and `alln
   bootstrap` — never hand-authored twice (the board-staleness lesson).
2. **Recipes are literal files — and the files ARE the v1 SSOT.** (Core
   registry/`--recipe` export deferred until drift is measured pain — panel
   simplify consensus.) NAMED DECISION: these prompt cards COEXIST with
   ContractRegistry's `example-recipes` (machine command snippets); they are
   different artifacts for different readers — revisit merge only if they
   drift toward each other. A "Use from your CLI" surface in the app that
   is actually a shipped folder of `.md` recipe cards (Pilot a spec · Panel this
   doc · Hand a relay the unattended shift · Route a build to another model),
   each one copy-paste-ready: bootstrap snippet inlined + the specific recipe.
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
4. **The trigger line (part of bootstrap content, not its own machinery).** ONE
   sentence mapping intent to tool: "Use `alln` whenever the user wants work
   routed to another model/CLI, delegated and reviewed, run unattended, or
   judged by multiple models." This is the load-bearing mechanism and a BLOCKING
   prerequisite for the installer slice — installing a mechanics-only snippet
   teaches a dictionary entry, not a reflex. Size budget holds. Success
   criterion (later gate, golden-transcript style): a fresh session given the
   snippet suggests alln for "route this to another model" — named, not v1.
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
works test is green.

| Slice | Deliverable |
| --- | --- |
| ONB-S01 | Bootstrap trigger line + size-budget test (BLOCKING for S03) + a `teaching.installed` doctor check per global target (installed/absent — the mechanical stand-in for the untestable "cold user never clicks" path) |
| ONB-S02 | Shipped recipe `.md` folder (v1 SSOT) + app "Use from your CLI" surface with copy buttons (GUI proof gate applies) |
| ONB-S03 | App one-click GLOBAL snippet install: per-host target enumeration (global paths only), preview, marker append/repair-with-diff/remove, write-failure surfacing |
| PARKED | Per-project AGENTS.md offer (uncommitted-write discipline specced above) · done-card graduation nudge + CLI nextActions echo · Core recipe registry/`--recipe` |

## Works test

A fresh machine-state simulation: install app → click "Teach your CLIs" →
open a new agent session → say "route this build to another model" → the
session suggests alln unprompted (the trigger line fired). Recipe copy-paste
runs end-to-end for pilot + panel. Removal click leaves vendor files byte-clean
outside the markers. Snippet size budget green; recipes render from SSOT
(drift test).
