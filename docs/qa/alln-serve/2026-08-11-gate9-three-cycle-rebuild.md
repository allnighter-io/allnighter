# ASR-S06 gate 9 — founder dev loop, three consecutive cycles

Date: 2026-08-11 (UTC)
Gate: §8 ASR-S06 **gate 9** — `rebuild_cli.sh` → `install-cli` → healthy serve,
three times in one session with a changing ad-hoc cdhash under the same
registration.
Signing track: **ad-hoc** (`codesign --sign -`, the dogfood and shipping
reality per §4.6).
Build at start: `0612b8ec`; at finish: `0ca15b7e`.
macOS: 15.6.1 (24G90), arm64.

## Signature status — read this before citing the result

**Executed by the PM agent at the founder's direction, with the founder
confirming the machine lane was clear. It is NOT founder-signed.** §8 states
gates 7–10 require a human at the machine and that "the founder is the signer."
This record is therefore **measured evidence, not a signed gate**. To count as
signed, the founder runs it or explicitly countersigns this file.

## Result: 3/3 clean

| Cycle | canonical cdhash | agent pid | daemon pid | daemons | agents loaded | health | last exit |
| --- | --- | --- | --- | --- | --- | --- | --- |
| baseline | `ee30896c9029…` | 12567 | 12567 | 1 | 1 | `available`, listening | never exited |
| 1 | `ff08c215ba81…` | 26513 | 26513 | 1 | 1 | `available`, listening | never exited |
| 2 | `6d57bcec8665…` | 28390 | 28390 | 1 | 1 | `available`, listening | never exited |
| 3 | `b58f09841 26f…` | 37609 | 37609 | 1 | 1 | `available`, listening | never exited |

- **Four distinct cdhashes** under one unchanged label — the code identity
  genuinely changed on every cycle, which is the §4.5 variable.
- Agent `program` stayed `~/.local/share/allnighter/bin/alln` throughout.
- Agent pid == daemon pid on every cycle: no orphan, no rival daemon.
- `listening: true` is the **active handshake** (ASR-S03d), not a pid inference.
- `log show --last 12m --predicate 'process == "launchd"'` matched
  **zero** occurrences of `LWCR` / `lightweight code requirement` / `exit 78` /
  `Code Signature`.
- No TCC / protected-folder prompt appeared.

## What this proves

The exact motion that wedged on 2026-08-09 — replacing an ad-hoc-signed binary
under a live per-user LaunchAgent — completed cleanly three times in a row with
the ASR-S01/S02 install transaction in place (bootout bracketing the byte
change, canonical path, `KeepAlive` dictionary, verify before staged-byte
removal).

## What this does NOT prove — §10.1 R1 stays open

This is **absence evidence for a fault whose cause is still unidentified**.
ASR-S00 refuted the packet's assumed mechanism (a changing cdhash under a loaded
agent did not reproduce the wedge on any signing track), so a clean run here does
not confirm a fix — it confirms the failure did not occur under these
conditions.

Specifically not covered:

- The 2026-08-09 failure occurred on a host with longer uptime and a different
  install lineage; three cycles in one fresh session do not model that.
- A **second** unexplained launchd event happened earlier today: the job was
  found unloaded with an orphaned daemon at PPID 1 running a Library/Developer
  debug build (see `2026-08-11-live-host-migration.md`). Cause also unidentified.
  Two unexplained events, not one.
- Gates 7, 8, and 10 (logout/login, disable-survives-login, sleep) are unrun.

R1 remains open. Do not archive the packet claiming the incident is fixed.

## Reproduce

```bash
bash scripts/rebuild_cli.sh          # ×3, capturing between each:
launchctl print gui/$(id -u)/com.allnighter.resident-coordinator
codesign -dvvv ~/.local/share/allnighter/bin/alln    # CDHash must differ per cycle
alln serve --health --json
log show --last 12m --predicate 'process == "launchd"' | grep -iE "LWCR|exit 78"
```
