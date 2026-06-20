# Grok Build CLI Support (Headless + Streaming JSON)

Status: streaming-json schema verified; final visible-text extraction wired
(2026-06-19). Live partial UI updates still require the shared streaming runner
from `docs/phases/threads/03_Mac_Streaming.md`.

## Recommended Non-Interactive Streaming Invocation

```bash
grok -p "<PROMPT>" \
  -m <MODEL> \                    # e.g. grok-build or grok-composer-2.5-fast
  --output-format streaming-json \
  --cwd <WORKING_DIR> \
  --always-approve \              # (alias --yolo) auto-approve tools
  --no-wait-for-background \
  --no-subagents \
  --disable-web-search
```

- Primary form: `grok -p` / `grok --single <PROMPT>` (top-level). Not `grok agent ...` for this output format.
- `--cwd` sets project discovery root (used by Allnighter manifests).
- For Allnighter answer/chat runs the driver manifest now emits the above (plus
  `{{workingDir}}` expansion; no-root chat runs use Allnighter's neutral scratch
  path rather than `--cwd ""`).
- Smoke probes continue to use plain output for simple token checks.

## Event Schema (streaming-json)

Newline-delimited JSON. Each line: `{ "type": "...", ... }`

Relevant events:

| type                  | Visible as answer? | Notes / fields                              |
|-----------------------|--------------------|---------------------------------------------|
| `text`                | YES (only this)    | `{"type":"text","data":"<delta>"}`          |
| `thought`             | NO                 | Internal reasoning chunks (`data`)          |
| `end`                 | NO (terminal)      | `{"type":"end","stopReason":"EndTurn","sessionId":"...","requestId":"..."}` |
| `error`               | NO                 | `{"type":"error","message":"..."}`          |
| `max_turns_reached`, `auto_compact_*` | NO | Non-exhaustive; ignore for answer text     |

- **Text deltas are incremental**, not snapshots. Concatenate every `text.data` in arrival order.
- No repeated "final assistant message" in the stream. `end` carries only metadata. Accumulate until `end` (or process exit) → that is the full visible answer.
- Tool calls / tool results / ACP-style `tool_call` etc. are **not surfaced** in this `--output-format streaming-json` envelope. The agent performs tools internally; synthesized text appears in `text` events. For live tool visibility use `grok agent stdio` (ACP).

## What to Show / Not Show

- Chat answer text ← only `type == "text"` → `data`
- Never render: `thought`, `end`, `error`, `max_turns_reached`, `auto_compact_*`, or unknown types.

## Terminal, Errors, Exit Codes

- Success terminal: receive `end` event. Process should exit 0.
- Failure: `error` event (and/or nonzero exit).
- Exit codes (headless):
  - 0 — normal completion
  - 1 — error (auth, network, runtime, etc.)
  - 130 — SIGINT
  - 143 — SIGTERM

## Example JSONL (tiny prompt)

```
{"type":"thought","data":"The"}
{"type":"thought","data":" user asked for one word.\n"}
{"type":"text","data":"P"}
{"type":"text","data":"ONG"}
{"type":"end","stopReason":"EndTurn","sessionId":"019ee2bf-...","requestId":"1e6a7982-..."}
```

## Implementation Notes (Allnighter)

- Manifests updated in `DefaultConfig.swift` + `Apps/.../Drivers/grok.json`.
- `TextUtil.extractGrokStreamingVisibleText` concatenates visible deltas
  (fallback for plain output is identity).
- Wired in `WorkerRunner` after ANSI strip for the Grok driver only.
- Works Test added (`testGrokStreamingJsonExtractsOnlyVisibleTextDeltas`).
- This is not the full live-streaming feature yet: `WorkerRunner` still receives
  the complete stdout after process exit. The V1 live path must stream chunks
  through `StreamingCommandRunner` and persist running-turn partial text.

Sources: `~/.grok/docs/user-guide/14-headless-mode.md`, live `grok -p ... --output-format streaming-json` captures (2026-06), `DriverManifest`, `WorkerRunner`.
