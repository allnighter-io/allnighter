# Antigravity CLI Support (Headless Final Output)

Status: headless final-output contract recorded (2026-06-19). Current `agy`
does not expose streaming, JSONL, or structured events for `--print` / `-p`.

## Recommended Non-Interactive Invocation

```bash
agy --print "<PROMPT>" \
  --model "<MODEL>" \
  --dangerously-skip-permissions \
  --print-timeout 5m
```

- Primary form: `agy --print`, `agy -p`, or `agy --prompt`.
- `--model` selects the target Gemini/Antigravity model label.
- `--dangerously-skip-permissions` is the current headless auto-approval flag.
- `--print-timeout <duration>` bounds long runs; current CLI default is `5m0s`.
  Allnighter's image-generation manifest uses `10m`.
- `--add-dir <path>` may add context outside the workspace root when needed.

Allnighter's current answer manifest uses:

```text
agy --print {{prompt}} --model {{model}} --dangerously-skip-permissions
```

## Streaming Capability

Current answer from the Antigravity CLI: no token streaming, JSONL, or
machine-readable event mode exists for headless `agy --print` / `agy -p`.

V1 posture:

- Not stream-capable.
- No parser is needed until Antigravity exposes a stream or structured mode.
- Product capability should say "final answer only", not "streams live".

## Output Contract

- stdout contains the clean final assistant answer text in `--print` mode.
- stderr carries diagnostics, warnings, and errors.
- Persistent logs default under `~/.gemini/antigravity-cli/logs`, unless
  `--log-file` overrides the destination.
- Keep `stripAnsi: true` in the manifest.

## Terminal, Errors, Exit Codes

- Terminal signal is process exit.
- Exit `0` means success and stdout is the final answer.
- Non-zero exit means failure; error context is in stderr and/or the Antigravity
  log file.

## Implementation Notes (Allnighter)

- `antigravity.json` captures stdout and strips ANSI.
- `DefaultConfig.swift` embeds the same final-output invocation.
- `docs/phases/threads/03_Mac_Streaming.md` records Antigravity as a V1
  final-output fallback beside the streaming-capable drivers.
- If a future `agy` release adds structured streaming, add `streaming` manifest
  metadata and a dedicated parser before claiming live output.

Sources: Antigravity CLI answer supplied for Allnighter streaming research
(2026-06-19), `Apps/AllnighterMac/Resources/Drivers/antigravity.json`,
`DefaultConfig.swift`.
