# Pair Programming — Improvements Backlog

Fast-follow ideas from dogfooding the supervisor + hammer queue on real slices. Items marked **Done** shipped in the observability + OpenCode SSE slice.

## Shipped (this slice)

| Item | Surface |
| --- | --- |
| **Heartbeat while queue runs** | `pair run` prints `B1a running…`, `B1a passed (6m47s)`; `--json` emits NDJSON `pairQueueProgressJSON` before final `pairQueueJSON` |
| **`pair status`** | `alln pair status --queue <dir>` + MCP `pair_status` — queue entry, child run id, elapsed seconds, stall guidance |
| **PM visibility** | Running + elapsed &lt; stall timeout → guidance says *slice in progress — check queue.json*, not implied failure |
| **`--verbose`** | `pair run --verbose` appends progress + `events.jsonl` tail to `pair-verbose.log` in the queue dir |
| **Stale `running` on kill** | `pair run` start reconciles dead child runs back to `pending` |
| **OpenCode SSE** | `prompt_async` + `GET /event` → `WorkerStreamEvent`; `RunService` streams opencode when `canStream` |

## Next (worth doing)

### Observability

- **Live MCP/CLI stream during `pair_run`** — today MCP returns one blob at end; optional NDJSON tool response or side-channel progress events for agents watching unattended runs.
- **Periodic heartbeat while a single slice runs** — slice-level lines exist; add intra-slice ticks (e.g. every 60s with child run age) so multi-minute GLM turns don’t look frozen.
- **`pair status --watch`** — poll queue.json + run store every N seconds for terminal dashboards.
- **Mac app queue panel** — render `pair status` truth in the shell instead of a blank timeline during overnight runs.

### Queue / packets

- **Doc → packet compiler** — turn markdown slice specs (handover sections) into `WorkSlicePacket` JSON + queue entries without hand-authoring.
- **Queue-level `stoppedReason` persistence** — write last outcome into `queue.json` metadata for operators who only open the file.
- **Per-slice verbose** — `--verbose` is queue-wide; optional per-slice OpenCode session log path in the packet.

### Execution

- **OpenCode `/session/:id/wait`** — if idle SSE is flaky on older serve builds, poll wait endpoint as completion backstop (see `OpenCode_Smoke_Probe_Blocker.md` follow-ups).
- **Streaming in run artifacts** — ensure `events.jsonl` on pair child runs includes `workerAnswerDelta` when OpenCode streams (GUI can show live text on replay).
- **Planner takeover progress** — heartbeat when Composer seat runs after three GLM failures (distinct from executor lines).

### PM / process

- **Stall playbook in help** — one help topic section: “queue says running, terminal is quiet” → run `pair status`, check child run, don’t assume failure before `stallTimeoutSeconds`.
- **Slice sizing linter** — warn when packet touch allowlist or check command looks too large for one GLM context window.

## Non-goals (for now)

- Resume/interrupt tokens mid-slice (vendor session continuity is run-level, not queue-level).
- Multi-repo queues (one queue dir = one project root).
- Migration from legacy sprint JSON — greenfield only.

---

*Source: Agent Editing bug-fix dogfood + pair programming lesson (observability gap = black hole during unattended runs).*
