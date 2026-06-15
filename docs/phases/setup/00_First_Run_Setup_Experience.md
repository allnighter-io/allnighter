# First-Run Setup — The Experience ("Assemble your team")

**Status:** Spec for design + build. Designers mock from this doc.
**Surface:** A full-window, first-launch flow on macOS (the same window the
team runs in). Re-runnable later from Settings.
**Owner:** Founder / GUI
**Created:** 2026-06-15
**Visual SSOT:** `docs/design-system/` · **Build governance:** `docs/gui/GUI_Workflow.md`

---

## 1. Why this exists (the moment to win)

A solo builder already pays for Claude Code, Codex, Grok, Gemini/Antigravity,
Cursor, Aider… The product's whole thesis is **"you already pay for the team —
Allnighter makes it show up to work."** First-run Setup is where the team
literally shows up. It is the first 60 seconds and the first proof of the
promise. If it feels like a config form, we've lost. If it feels like Allnighter
*reached into the machine and assembled a team that's ready to work tonight*, we
win the user.

### The anti-spec (what we have today — never ship this again)
- Cold open straight into an empty run surface with a 1-worker team.
- A **0/1 healthy** badge with no explanation and no path forward.
- The user has 4 CLIs installed; the app shows one, broken. Zero guidance.
- Setup, auth, and discovery simply don't exist.

> Note: today's single-worker / "no manifest" state is amplified by a **packaging
> bug** — the bundled default team and all driver manifests fail to load, so the
> app falls back to one hardcoded worker. See `01_…` §Cause 0. That bug is a
> prerequisite fix; this experience is what replaces the whole cold open.

The bar: a new user should go from launch → "my whole team is ready" with **one
click and zero typing** in the common case.

---

## 2. The feeling

Cinematic, calm, confident. The brand is "amber phosphor on midnight," and the
**live mark is the hero** — the lamp that's on all night. Setup is a **roll
call**: Allnighter sweeps the machine and the team reports for duty one by one,
each lighting up as it's found and verified. Restraint, not confetti. The wow is
*recognition* ("it found everything I have, and it's ready"), not animation for
its own sake.

Voice: sentence case, verbs first, no hype, no emoji. Numbers concrete and mono.
"Found Claude Code 1.2.4." "Grok needs a login." Never "AI-powered."

---

## 3. The flow (scene by scene)

Six scenes, one continuous window (implementation may merge the scan + reveal —
Scenes 2–3 — into one). The user can always proceed with whoever is ready —
nothing here is a hard gate except "at least one tool ready."

> **Source vs model vs worker (critical):** the roster is **one card per CLI/tool
> source** (Claude Code, Codex, Grok, Antigravity), not one per model. Detection
> is per source; ready sources populate the Bench with models (Opus, Sonnet…),
> and Scene 5 builds workers from those models. Tallies and the health badge are
> source-level. See `01_…` §2.

### Scene 1 — Cold open / hero (≈2s, auto-advances)
- Full midnight canvas (`--bg-base`). The **live mark breathes** (idle → the
  block blinks) center-stage at a large size (~64pt).
- One promise line, display type: **"Let's assemble your team."**
- Subline, muted: "Allnighter runs the AI coding tools you already pay for —
  in parallel, overnight. First, let's find them."
- Single primary button **"Scan my machine"** — OR auto-start the scan after a
  beat (designer to choose; recommend auto-start with a barely-visible "scanning…"
  so there's no dead click). A faint "What gets scanned?" ghost link opens a
  popover explaining we only look for known CLI tools, locally, read-only.

### Scene 2 — The scan (the magic moment)
This is the scene that has to sing.
- The live mark moves up into a slim header ("Assembling your team ·
  scanning…", live mark blinking).
- A **roster** materializes as a column of **tool cards — one per known CLI**,
  each a dim, ghosted slot that **resolves in real time** as detection completes,
  in roll-call order:
  - ghost → **"found"** (glyph ignites to full color, name + version snap in,
    mono version line) → **"checking…"** (a quiet pulse) → terminal state:
    - **Ready** — green `StatusPill`, version shown, a soft amber/green settle.
    - **Needs login** — amber, "found, not signed in" + an inline fix (Scene 4).
    - **Not installed** — muted/ghosted, an "Add" affordance (Scene 4).
- Cards animate in **staggered** (~120–160ms apart) so it reads as a team
  arriving, not a table rendering. Reduce-motion: no stagger, states just set.
- A live tally updates at the **tool** level: **"4 of 4 tools ready."**
  Progressive reveal rewards each true step — **found → `claude 1.2.4` → signed
  in → 2 models** — so cards ignite long before smoke finishes (probe order is
  fastest-first; see `01_…` §4.1).
- Honesty: a card never flips to Ready unless its probe passed. A failed probe
  shows the real reason in mono ("not signed in", "command not found").

### Scene 3 — Roster reveal
When the sweep settles:
- Header: **"Your team is taking shape — 4 of 4 tools ready."** Live mark
  steady. Ready **tools** sort to the top; their models are used in Scene 5.
- The roster, now sorted: **Ready** on top, **Needs a step** next, **Available
  to add** last. Each card:
  - brand glyph (Anthropic / Gemini / X / Cursor logos; ChatGPT/Codex uses a
    neutral terminal chip — Simple Icons removed OpenAI; see `01_…` §6), name, the
    route (`via claude-code`), a mono version, and a status chip.
  - Ready cards have a subtle plan-writer marker when a model from that source
    can write the plan (e.g., Opus).
- Primary CTA appears once ≥1 is ready: **"Continue"** (to Scene 5) — but the
  user is invited to fix the amber ones first.

### Scene 4 — Fix-its (inline, never a dead end)
Each non-ready card carries the *exact* next step, resolved live without leaving
Setup. Three cases:
- **Found but not signed in.** Calm card: "Claude Code is installed but not
  signed in." Show the tool's real **sign-in flow** (e.g. *run `claude`, then
  `/login`*; Codex prompts on first `codex`; Gemini OAuth) — copyable mono — **and**
  a primary **"Open Terminal & sign in"** that launches Terminal to it. Copy is
  honest: **"Sign in in Terminal — we'll detect when you're done."** The card
  shows "waiting for sign-in…" and **polls** (a cheap re-check, then one smoke),
  flipping to **Ready** the moment it passes — no app restart, no manual refresh.
  (Stretch: an embedded sign-in console so it never leaves the window.)
- **Not installed.** "You don't have Grok yet." Show the one-line install
  (`brew install …` / `npm i -g …`) with copy + "Open install page" link. After
  install, a "Re-scan" chip picks it up. (Installing is the user's choice; we
  never auto-install.)
- **Found as an alias / shim / non-PATH binary.** "We found `agy` as a shell
  function, not a plain command." Offer "Use it anyway" (run through the login
  shell wrapper) or "Locate the binary…" (file picker). See detection doc §4.

Every fix re-probes in place and updates the tally. The user watches amber turn
green — that *is* the reward loop.

### Scene 5 — Team & plan writer (light confirm)
- "Set your team." Workers from ready models are **pre-selected**; the user can
  toggle. At least one must stay. This is **confirm, not configure** — no model
  editing here (that's Settings).
- **Plan writer** picker, defaulted to the best eligible worker (Opus 4.8
  wearing the Plan Writer skill if present). One line on what the plan writer
  does: "one worker reads every answer and writes the plan."
- A quiet cost/scale reassurance: "N workers · local · $0 marginal."

### Scene 6 — Launch
- "Your team is ready." Live mark gives one confident amber glow-pulse.
- Recap chip: **"6 workers · plan writer: Opus 4.8 · $0 marginal."**
- Primary **"Ask your team"** → dissolves into the Compose screen
  with the team populated and the prompt focused. Show an example prompt **muted
  in the placeholder**, never pre-filled — typing breaks zero-typing for a user
  who already has a task in mind.

---

## 4. States to design (every card, every scene)

For each source card, the designer needs all of:
`ghost/queued` · `detecting` · `ready (version)` · `needs-login` ·
`not-installed` · `alias/needs-path` · `probe-failed (reason)` · `re-probing`.

For the flow: `scanning` · `partial (some ready)` · `all-ready` ·
`none-found (empty state with guidance)` · `offline/edge` (a CLI hung — show
"taking a while…", never spin forever).

The **none-found** state matters: a brand-new machine with zero CLIs should still
feel hopeful — "Let's get your first tool connected. Here are the three fastest to
install," each a one-liner.

---

## 5. Visual direction (for the mock)

- **Tokens/components:** `docs/design-system/` — midnight surfaces, amber as the
  single warm signal, `StatusPill`, model chips, worker chips, `Badge`, `Button`,
  `LiveMark`. Mono (`--font-mono`) for versions, paths, commands.
- **The live mark is the protagonist** — large in the hero, blinking during
  scan, a single glow-pulse on success. Never animate the whole mark, only the
  block (per brand).
- **Roll-call motion:** staggered card resolves; a source "igniting" = its glyph
  going from `--text-faint` monochrome to full brand color. Calm easing
  (`--ease-out`), 140–200ms. Respect reduced-motion.
- **Real brand glyphs** — Simple Icons `anthropic`, `googlegemini`, `x`,
  `cursor`. Simple Icons **removed OpenAI** (trademark), so ChatGPT/Codex uses a
  **neutral terminal chip / SF Symbol** (per `docs/design-system/readme.md`).
  Glyph tint = brand; Opus/plan-writer carries the amber.
- Density and chrome match the team-run window so Setup feels like the same
  product, not a separate installer.

---

## 6. Re-entry & relationship to Doctor

- Setup is **re-runnable** from Settings ("Re-configure team"). Doctor (today's
  health sheet) becomes the *recheck* surface and ultimately folds into this
  language: the title-bar health badge ("4/4 tools ready") opens a compact
  version of the roster with the same fix-its.
- The health badge must always reflect **real** probe state — Setup and Doctor
  share one source of truth (see detection doc).

---

## 7. Success criteria (how we know it WOWs)

- **One-click, zero-typing** in the common case (CLIs installed + already signed
  in) → team assembled.
- **% of installed CLIs auto-detected** approaches 100% — including aliases,
  shims, and version-manager installs (the thing that's broken today).
- A user with an unauthed CLI can fix it **without restarting the app** — sign-in
  completes in Terminal, the card re-probes and flips green in place.
- Time from first launch → first team run is under a minute.
- Emotional read in user testing: "it found my whole team" / "that was magic."

---

## 8. Design decisions (defaults — designer may push back with reason)

Resolved from mentor review so build isn't blocked; each is a default, not a law.

1. **Auto-start the scan** after a ~1s hero beat, with a subtle "scanning…" — no
   dead click in the common case. Keep the "What gets scanned?" link for the
   cautious. (Zero-click is the bar.)
2. **Single-column roll-call** for the scan (reads as a team arriving). A grid is
   fine later for a settled roster once there are >6 tools.
3. **Quiet success:** one live-mark amber glow-pulse + the tally line. No confetti
   — the green cards are the celebration.
4. **"Add a tool you don't have"** lives **inline** on `not-installed` cards only.
   No separate "browse tools" step in v1.
5. **Never skippable to a 0-ready team on first launch.** Require ≥1 ready tool;
   the none-found state (§4) is the empty path.
6. **Roster = shipped drivers only** (Claude Code, Codex, Grok, Antigravity). No
   ghost cards for tools without a manifest (Cursor/Aider/Gemini-CLI are phase-2).
