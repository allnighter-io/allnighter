# Allnighter Local AI Worker Opportunity

**Companion note to Allnighter PRD v0.3**  
June 12, 2026

> Purpose: keep the main PRD focused while preserving the local-model thesis.
> This note should become a product contract only if the Allnighter pivot is
> accepted.

---

## 1. Short Answer

Yes, there is an opportunity here.

The market for **running local models** is crowded. Ollama, LM Studio,
llama.cpp, MLX, Open WebUI, and similar tools already cover a lot of runtime,
chat, and developer-server behavior.

The market for **managing local models as part of an agent workforce** is not
captured.

Allnighter should not try to become the best local model runner. It should make
local runners useful inside the same operating system as Claude Code, Codex,
Grok, Gemini, Cursor, Aider, and other agents.

The wedge:

> Your Mac Studio, Mac mini, or spare workstation becomes another worker in the
> bench: private, always available, cheap to run, and perfect for background
> review, QA, summarization, planning, indexing, and low-risk implementation.

The stronger long-term thesis:

> If local models become frontier-class, Allnighter becomes more valuable, not
> less.

When intelligence is expensive, quota is a bottleneck. When intelligence gets
cheap, local, and effectively unlimited, human attention becomes the bottleneck.
Allnighter's core loops -- races, teams, disagreement routing, picker as
prompt, taste memory, and landing queues -- are all ways to spend less human
attention per unit of shipped work.

---

## 2. Why This Belongs in Allnighter

Allnighter's core thesis is:

> keep the AI workforce busy and route work to the right available worker.

Local AI fits that thesis naturally.

Cloud subscriptions provide frontier capability but have limits, windows,
latency, vendor dependency, and privacy concerns. Local models increasingly
provide:

- no per-call marginal cost;
- strong privacy;
- offline or LAN-only operation;
- always-available background labor;
- controllable hardware;
- useful specialization;
- no quota reset anxiety;
- a reason to put a Mac Studio or Mac mini to work all night.

The product story becomes stronger:

```text
Cloud agents handle frontier tasks.
Local agents keep the factory warm.
Allnighter routes between them.
```

If local models reach frontier-class quality, the story evolves:

```text
Local agents become the workforce.
Allnighter becomes the conductor.
The user's picks become the durable asset.
```

The product should therefore avoid a temporary "local models are interns"
positioning. That may be true for some current tasks and models, but it is not
the durable thesis.

---

## 3. What Local Models Should Do First

Do not start by promising local models can replace frontier coding agents in
all cases. Do build the architecture as if they eventually can.

Start with work where they are immediately valuable:

### 3.1 Team Participant

Local model gives an additional independent take in strategy/planning teams.

Good for:

- "What are the risks in this plan?"
- "Find the simplest version."
- "Argue against the consensus."
- "Summarize the tradeoff."

### 3.2 Plan writer and Summarizer

Local model reads outputs from multiple agents and prepares the phone-friendly
verdict.

Good for:

- compressing long outputs;
- extracting disagreement;
- writing minority reports;
- classifying risk;
- producing Morning Pull summaries.

### 3.3 QA and Smoke Tester

Local model works with deterministic tools:

- read Playwright output;
- summarize test failures;
- generate manual QA checklists;
- inspect screenshots when multimodal local models are available.

### 3.4 Backlog Miner

Local model scans safe local sources:

- TODO comments;
- failed tests;
- logs;
- README gaps;
- issue text already synced locally;
- stale branches.

It creates draft work orders, not code changes, until trust is established.

### 3.5 Preference Memory Plan writer

Local model periodically turns picks/rejections/reverts into project memory.

This is a perfect local task because it uses private user preference data.

### 3.6 Low-Risk Implementation Worker

After the basics work, local models can try small implementation lanes:

- tests;
- copy changes;
- refactors in isolated files;
- documentation;
- fixture generation;
- typed model scaffolds.

They should begin in draft-only or green-land-disabled mode until scorecards
prove reliability.

---

## 4. Product Positioning

Do not say:

> Allnighter is a local AI app.

Say:

> Allnighter can use every worker you have: cloud subscriptions, CLI agents,
> IDE agents, and local models running on your own hardware.

User-facing line:

> Put your Mac Studio on the night shift.

Supporting lines:

- "Run private background workers from your own hardware."
- "Use local models for review, summaries, QA, and low-risk tasks."
- "Save frontier quota for the jobs that need frontier models."
- "Your spare Mac mini becomes part of the bench."

---

## 5. Market Read

Existing local AI products mostly occupy four categories:

1. **Runtime/server:** Ollama, llama.cpp, MLX-based servers.
2. **Local chat/model manager:** LM Studio, Open WebUI-style apps.
3. **IDE coding integration:** Continue, Cursor local-model settings, editor
   plugins.
4. **Model experimentation:** notebooks, MLX examples, benchmarks.

Allnighter should occupy a different category:

> local models as scheduled workers inside a product-building factory.

The others answer:

```text
How do I run a local model?
```

Allnighter answers:

```text
What should this local model do while I sleep, and how does its work feed into
the same queue, race, team, landing, and memory system as every other agent?
```

That is the gap.

Ollama, LM Studio, llama.cpp, and MLX-style tools are not the main structural
threat because they are runtime layers. Their job is to run models simply and
neutrally. The more they move into routing, judging, picking winners, modifying
repos, or landing code, the more they complicate the simple runtime promise that
makes users trust them.

The analogy:

```text
Runtime layer: "Run this model."
Operating layer: "Coordinate all workers and ship the right result."
```

Allnighter belongs in the operating layer.

The real long-term threat is another product that understands the same thing:
when intelligence commoditizes, the lasting assets are execution substrate and
per-user taste/review data.

---

## 6. Integration Surfaces

Local model support should be API-first and runtime-neutral.

### 6.1 OpenAI-Compatible Local Server Driver

Many local runtimes expose OpenAI-compatible endpoints. Build this driver first.

Config:

```json
{
  "id": "local_openai_compatible",
  "display_name": "Local Model Server",
  "base_url": "http://localhost:1234/v1",
  "model": "qwen3-coder-local",
  "capabilities": ["chat", "structured_output", "summarization"],
  "cost_model": "local",
  "privacy": "local_only"
}
```

### 6.2 Ollama Driver

Ollama exposes a local API with streaming responses, chat, embeddings, model
listing, running-model listing, and model pull/load behavior.

Driver jobs:

- detect `http://localhost:11434`;
- list local models;
- run smoke prompt;
- stream responses;
- collect token/time stats;
- optionally pull recommended models.

### 6.3 LM Studio Driver

LM Studio can run a local API server and supports OpenAI-compatible endpoints,
including responses/chat/embeddings. It can also serve on the local network.

Driver jobs:

- detect server URL;
- list models;
- use OpenAI-compatible client path;
- optionally support Anthropic-compatible path later;
- report loaded/unloaded model state where available.

### 6.4 llama.cpp Server Driver

Useful for advanced users who want direct control.

Driver jobs:

- connect to server;
- use OpenAI-compatible chat/responses where available;
- track parallel slots;
- respect context size/model settings;
- treat as advanced configuration.

### 6.5 MLX Path

MLX is a framework, not a finished product surface for Allnighter v1.

Use MLX indirectly through tools that expose servers first. Consider direct MLX
integration only when Allnighter needs Apple-Silicon-specific performance or
packaged local workers.

---

## 7. Hardware Profiles

### 7.1 Laptop Mode

Use local models gently:

- summarization;
- preference memory;
- small teams;
- no heavy overnight work on battery.

### 7.2 Mac Mini Worker

The always-on home worker:

- local team participant;
- backlog miner;
- QA summarizer;
- small implementation lanes;
- relay/preview host.

### 7.3 Mac Studio Worker

The local workhorse:

- larger local models;
- longer context;
- multiple local workers;
- overnight speculative tasks;
- private codebase indexing;
- local multimodal inspection where supported.

The product should let users name the machine:

```text
Mac Studio - Local Bench
Mac mini - Night Worker
MacBook - Desk Factory
```

---

## 8. Scheduling Rules

Local models should have a different scheduling profile from cloud agents.

Cloud scheduler optimizes:

- quota window;
- subscription limits;
- model strength;
- cost;
- latency.

Local scheduler optimizes:

- machine availability;
- power state;
- thermal load;
- memory pressure;
- user foreground activity;
- model load time;
- privacy level;
- task suitability.

Example rule:

```text
If Mac Studio is idle after 10pm and local workers are enabled, use local model
for backlog mining and preference-memory synthesis before spending frontier
quota.
```

---

## 9. UI Implications

### Mac App

Add a **Local Bench** section under Workers.

Shows:

- detected runtimes;
- loaded models;
- available context;
- approximate tokens/sec where reported;
- local/private badge;
- machine resource state;
- recommended roles.

Actions:

- Add local server;
- Smoke test;
- Assign roles;
- Limit memory/CPU;
- Use only on charger;
- Use only during quiet hours;
- Never use for code changes.

### iOS App

Show local workers as part of the same bench:

```text
Claude - busy
Codex - idle
Mac Studio Local - summarizing team
Mac mini Local - mining TODOs
```

Do not force the user to think about runtime names. Use capabilities:

- private reviewer;
- local summarizer;
- night QA;
- backlog miner;
- small-task worker.

---

## 10. Safety Rules

Local does not automatically mean safe.

Rules:

- local models begin as read-only workers;
- code-writing roles require explicit enablement;
- local implementation starts draft-only;
- local workers cannot access secrets unless explicitly allowed;
- local server exposed on LAN must require pairing/auth where Allnighter
  brokers access;
- public internet exposure must be warned against;
- local model outputs are scored separately from frontier agents.

Important:

> A local worker is private capacity, not trusted capacity.

---

## 11. MVP Slice

Smallest useful local AI slice:

```text
Detect Ollama or LM Studio
-> list available local models
-> run smoke prompt
-> add local model as read-only worker
-> use it to summarize a three-agent team
-> show "Local/private" badge in Mac and iOS worker roster
```

Do not start with local code-writing. Start with summarization and review.

Works Test:

```text
Given Ollama or LM Studio is running locally
when the user opens Allnighter Mac Workers
then the app detects the local server,
lists models,
runs a smoke prompt,
and marks one local model available as a private read-only worker.

When a team finishes,
then the local worker produces a phone-friendly summary and minority report
without sending the team transcript to a cloud model.
```

---

## 12. Later Slices

1. Local preference-memory synthesis.
2. Local TODO/backlog mining.
3. Local QA summary from test logs.
4. Local screenshot reviewer with multimodal model support.
5. Local small-task implementation lanes.
6. Multi-machine local worker routing.
7. Mac Studio overnight mode.
8. Model recommendation based on installed hardware.
9. Local embedding/index store per repo.
10. Local-first teams where cloud agents are used only for final review.

---

## 13. Product Risk

The risk is not that the local AI market is captured. The risk is that local
models are oversold.

Bad promise:

> Run frontier-quality coding agents locally.

Better promise:

> Add private, always-on local workers to the same factory as your frontier
> agents.

Allnighter wins if it routes local models to jobs where they are actually good
and preserves frontier agents for the work that needs them.

---

## 14. Recommendation

Add local AI support to the Allnighter roadmap, but do not make it the launch
headline.

Launch headline:

> Ask your AI bench for options. Pick one. Implement it.

Local AI headline inside the product:

> Put your Mac Studio on the night shift.

This is a strong expansion path because it deepens the same core idea:

> Allnighter does not care whether the worker is a cloud subscription, a CLI
> agent, an IDE agent, or a local model. It cares what work the worker can
> reliably do next.
