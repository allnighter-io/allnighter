# Run Latency — CLI-to-CLI Benchmark Findings (2026-06-21)

**Trigger:** founder noticed runs sometimes "take a super long time", and that the *interactive*
grok CLI answers instantly while Allnighter's grok turn took ~4s (and sometimes far longer).

**Method:** ran the EXACT command Allnighter issues for a grok worker, measuring spawn→first-byte
(TTFB) and spawn→process-exit, isolating one variable at a time. Prompt: "Just say Hi."

## Headline result

| Working directory | TTFB | total | note |
|---|---|---|---|
| empty `/tmp` | ~2.5s | **~6.6s** | baseline |
| tiny git repo (1 file) | ~3.9s | ~6.2s | git-ness is free |
| tiny repo + Allnighter `.claude` + Agents.md | ~4.3s | ~6.8s | **config is NOT the cost** |
| **full Allnighter repo** | ~21s | **~25–28s** | 4× slower |
| full repo + `GROK_SANDBOX=danger-full-access` | ~18s | ~22s | sandbox is NOT the cost |

**The cost scales with the working directory's CONTENTS, not our flags or config.** The Allnighter
repo has **1,420 tracked files but 17,135 total files** (~15k untracked/ignored build artifacts;
`Packages/` is 658M). grok cold-starts and **walks/indexes the working tree on every invocation**;
on a big repo that's ~20s of dead air before the model emits a single token.

### What is NOT the cause (ruled out by benchmark)
- ❌ The streaming-json output format (json/streaming-json both ~same).
- ❌ Our flags: `--always-approve`, `--no-subagents`, `--disable-web-search`, `--no-wait-for-background`.
- ❌ The agentic loop: `--max-turns 1`, `--no-plan`, disabling all file tools — **none helped** (the
  dead air is BEFORE turn 1 runs).
- ❌ The repo's `.claude` permissions (44), Agents.md, 14 skills, sandbox profile, git-ness.

### What IS the cause
- ✅ grok **cold-starts a fresh agent runtime per `grok -p`** (there is **no warm leader** —
  `grok leader list` → "No leader candidates found").
- ✅ That cold start **indexes the working tree**, which is huge for the Allnighter repo.
- ✅ The interactive CLI the founder uses is fast because it keeps a **warm leader process**
  (`~/.grok/leader.sock`) alive — the walk is paid once, then every turn is instant.

## The architectural problem (general, not grok-specific)

Allnighter **spawns a fresh agentic CLI process for every turn**, pointed at the full repo, with the
CLI's whole agent runtime (skills/agents/tools/tree-index) loaded each time — even for a chat turn
that only needs the model to answer. We pay a cold-start + repo-walk tax on every message. The
vendor CLIs are designed to be **long-lived warm sessions** (grok's leader, claude/codex resume),
and we use them as **one-shot cold invocations**. That inversion is the latency.

This is almost certainly NOT grok-only — codex and cursor are also agentic CLIs that build repo
context on launch. (Follow-up: run the same benchmark for each.)

## Fix directions (in value order)

1. **Warm, persistent worker process per thread** (the real fix). Keep one CLI session alive per
   Allnighter thread and pipe turns to it, the way the interactive CLI / grok leader works — the
   tree-walk and runtime init happen ONCE, then turns are near-instant. This is the architectural
   inversion that matches how these CLIs are meant to run. Pairs with the session-continuity work
   already shipped (that gives conversation memory; this gives a warm runtime). Bigger lift.
2. **Don't point non-mutating turns at the full repo.** Chat/answer turns that don't need repo
   files can run in a lightweight scratch cwd (~4× faster). Risk: a chat turn that DOES reference
   repo files needs the tree — so this is a heuristic, not unconditional. Smaller lift, partial win.
3. **Use the fast model for chat.** `grok-composer-2.5-fast` had ~2s TTFB vs grok-build's ~20s.
4. **Surface the numbers.** TTFT + queue-wait capture shipped (L1+L2) so we can SEE per-turn where
   the time goes; an `alln runs --latency` read surface (L3) is the next slice.

## Captured signals (already shipped this session)
- `WorkerAnswer.ttftMs` — CLI spawn → first visible streamed delta (the dead air).
- `WorkerAnswer.queueMs` — request accepted → CLI spawned (lock/lane wait + resolution + staging).
- Persisted in `run.json` + `workers/<id>.metadata.json`. With these, the 20s dead air shows up
  as a huge `ttftMs`, distinguishing "slow to start" from "slow to stream".
