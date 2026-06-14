# 19 — Local Workers

Status: Draft
Milestone: E (Intelligence layer)
Depends on: 04, 13, 15, 16
Owner: Mac + Shared Core + iOS
Created: 2026-06-13

> Absorbs the former `Allnighter-Local-AI-Worker-Opportunity.md` note in full.
> Strategic anchor: Thesis **T6** — intelligence commoditizes, orchestration
> endures. As local models improve, Allnighter becomes *more* valuable, not less.

## Goal

Add local-model runtimes as **private workers in the same bench** — same
scorecard, capability metadata, task categories, lane eligibility, risk tier, and
roster — without Allnighter becoming a model runner. Start **read-only** (judgment,
summarization, QA interpretation, backlog mining, preference synthesis); enable
low-risk implementation only behind explicit, scorecard-gated opt-in.

The wedge: *local models as scheduled workers inside a product-building factory* —
a category the runtime/manager/IDE/notebook tools do not occupy.

## Non-Goals

- Becoming a model runner/server. Local code-writing by default (it starts
  disabled). Multi-machine routing is a later slice (sketched below).

## Approach (per the absorbed note + `00` §9.9, §10, §11)

- **Drivers (API-first, runtime-neutral):**
  1. **OpenAI-compatible local server** driver (build first) — `base_url`, model,
     chat/structured-output/summarization, `privacy: local_only`.
  2. **Ollama** driver — detect `:11434`, list models, smoke prompt, stream,
     token/time stats, optional pull.
  3. **LM Studio** driver — detect server URL, list models, OpenAI-compatible path,
     loaded/unloaded state.
  4. **llama.cpp server** driver — advanced; OpenAI-compatible chat, parallel
     slots, context/model settings.
  - **MLX** is used indirectly through tools that expose servers; no direct MLX
    integration in v1.
- **Capability metadata** (`00` §9.9): a local worker is `{machine, runtime,
  model}` with `privacy`, `default_roles`, `implementation_enabled: false`,
  `power_policy`.
- **Roles first (read-only):** council participant; judge/summarizer (Morning Pull
  + council verdicts — done locally so the transcript need not go to a cloud
  model); QA interpreter (Phase 18); backlog miner (draft work orders only);
  **preference-memory synthesizer** (Phase 15 — ideal local task, uses private
  data). Later: low-risk implementation lanes (tests, copy, refactors, docs,
  fixtures), draft-only until scorecards prove reliability.
- **Local scheduling profile** (`00` §11): optimize machine availability, power
  state, thermal, memory pressure, foreground activity, model load time, privacy,
  task suitability — distinct from cloud quota scheduling. Example: "If Mac Studio
  is idle after 10pm and local workers are enabled, use local for backlog mining
  and preference synthesis before spending frontier quota."
- **Hardware profiles:** Laptop (gentle: summaries, memory, small councils, no
  heavy battery work); Mac mini (always-on night worker, relay/preview host); Mac
  Studio (workhorse: larger models, long context, overnight speculation, local
  indexing). Users name machines ("Mac Studio — Local Bench").
- **UI:** Mac **Local Bench** under Workers (detected runtimes, loaded models,
  context, approx tokens/sec, local/private badge, resource state, recommended
  roles; actions: add server, smoke test, assign roles, limit memory/CPU, charger-
  only, quiet-hours-only, never-for-code). iOS shows local workers in the same
  roster by capability ("local summarizer," "night QA," "backlog miner"), not by
  runtime name.
- **Safety** (`00` §10): local ≠ trusted. Read-only first; code-writing requires
  explicit enablement and starts draft-only; no secret access unless allowed; LAN
  exposure requires pairing/auth; warn against public-internet exposure; local
  outputs scored separately.

## Ordered Slices

- [ ] P19-S01 — Local worker capability metadata in Core.
- [ ] P19-S02 — OpenAI-compatible local server driver (detect, list, smoke, stream).
- [ ] P19-S03 — Ollama driver; P19-S04 — LM Studio driver; P19-S05 — llama.cpp driver.
- [ ] P19-S06 — Local Bench UI (Mac) + local/private badge; iOS roster entry.
- [ ] P19-S07 — Local scheduling profile (power/thermal/memory/quiet-hours/charger).
- [ ] P19-S08 — Wire local worker as council summarizer + preference-memory synthesizer (read-only).
- [ ] P19-S09 — Opt-in, draft-only low-risk local implementation gated by scorecard.

## Works Test

```text
Given Ollama or LM Studio is running on the Mac (or a Mac Studio), opening
Allnighter Workers detects the local server, lists models, runs a smoke prompt,
and marks one model available as a private read-only worker. When a council
finishes, the local worker summarizes the verdict and minority report WITHOUT
sending the transcript to a cloud model.
```

## Exit Gates

- [ ] Works Test passes (detect → list → smoke → read-only worker → local council summary).
- [ ] Local worker carries local/private badge; implementation disabled by default.
- [ ] `00` §10 local-safety rules enforced; local outputs scored separately.
- [ ] Code Audit CLEAN.

## Later Slices (post-v1, tracked here)

1. Local screenshot reviewer (multimodal). 2. Multi-machine local worker routing.
3. Mac Studio overnight mode. 4. Hardware-based model recommendation. 5. Local
embedding/index store per repo. 6. Local-first councils where cloud agents do only
final judgment.

## Closeout

Milestone E complete. Activate Phase 20 (relay & push).
