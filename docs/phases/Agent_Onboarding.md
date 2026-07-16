# Agent Onboarding — from findable to suggested

Status: Specced — awaiting panel hardening + founder go
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
2. **Recipes are literal files.** A "Use from your CLI" surface in the app that
   is actually a shipped folder of `.md` recipe cards (Pilot a spec · Panel this
   doc · Hand a relay the unattended shift · Route a build to another model),
   each one copy-paste-ready: bootstrap snippet inlined + the specific recipe.
   Copy button in the app; open-format files on disk so agents (and screenshots)
   can read them. Every recipe must be one we have actually run — zero unearned
   prompts (the no-fake-wisdom law, applied to onboarding).
3. **One-click snippet install (the consent line drawn correctly).** First-run +
   Settings: "Teach your CLIs about Allnighter" → detect `~/.claude/CLAUDE.md`,
   `.cursor/rules`, `AGENTS.md` conventions → PREVIEW exactly what will be
   appended → write on the user's explicit click. The CLI keeps its
   print-never-edit posture; the app acting on a human's click is the user's own
   hands. Idempotent (re-click repairs/updates the section, marker-delimited);
   removable (one click strips the marked section).
4. **The trigger line.** The bootstrap snippet gains ONE sentence mapping intent
   to tool: "Use `alln` whenever the user wants work routed to another model/
   CLI, delegated and reviewed, run unattended, or judged by multiple models."
   Mechanics without triggers is a dictionary entry; this makes it a reflex.
   Size budget holds (the anti-MCP context-tax law).
5. **Per-project offer.** When a project is registered (app or `alln project
   add`), offer once: "Add an Allnighter section to this repo's AGENTS.md?" —
   same preview + click + marker discipline. Repo-level teaching travels to
   every teammate who clones — each shared repo becomes a distribution vector.
6. **Teach at the moment of demonstrated intent.** When a first pilot/panel/
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
- No hand-authored duplicate content — SSOT or it rots.

## Slices (proposed)

| Slice | Deliverable |
| --- | --- |
| ONB-S01 | Recipe SSOT: recipe registry in Core (id, title, prompt text rendered from bootstrap + per-recipe body), exported as shipped `.md` files + `alln bootstrap --recipe <id>` prints one (CLI parity for free) |
| ONB-S02 | Trigger line in the bootstrap snippet (+ size-budget test) |
| ONB-S03 | App: "Use from your CLI" surface rendering the recipe folder + copy buttons (GUI proof gate applies) |
| ONB-S04 | App: one-click snippet install — target detection, preview, marker-delimited append/repair/remove, per-target consent |
| ONB-S05 | Per-project AGENTS.md offer (app + `alln project add` prints the offer text) |
| ONB-S06 | Done-card graduation nudge (inbox) |

## Works test

A fresh machine-state simulation: install app → click "Teach your CLIs" →
open a new agent session → say "route this build to another model" → the
session suggests alln unprompted (the trigger line fired). Recipe copy-paste
runs end-to-end for pilot + panel. Removal click leaves vendor files byte-clean
outside the markers. Snippet size budget green; recipes render from SSOT
(drift test).
