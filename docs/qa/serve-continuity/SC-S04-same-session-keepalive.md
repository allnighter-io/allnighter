# SC-S04 same-session KeepAlive proof (logout deferred)

Date: 2026-08-09  
Host: founder Mac  
Result: **PASS (same-session only)** — logout/login still owed

## Why not full SC-S04

Founder cannot logout/restart while work is in flight. This log covers the
stand-in proof: product `serve enable` on staged binary + KeepAlive restart
after kill, without manual `alln serve`.

## Steps run

1. `bash scripts/rebuild_cli.sh`  
   - Symlink install OK.  
   - `refreshAfterInstall` bootstrap briefly failed (`Bootstrap failed: 5: Input/output error`) while old agent was still loaded — non-fatal to install-cli.
2. Staged binary present:  
   `~/Library/Application Support/Allnighter/CLI/alln`
3. `alln serve enable --json` → `outcome: enabled`, staged path in detail.
4. `launchctl print` / plist `ProgramArguments` = staged `…/CLI/alln serve`  
   (**not** `~/.local/bin/alln`).
5. Health settled to `available` pid **68570**, contract **9.16.0**, gitSha `91461a13…`.
6. `kill 68570` → after ~6s health `available` pid **68943**, same staged program, `lastExitCode: 0`.

## Verdicts

| Check | Result |
| --- | --- |
| Enable aims at Application Support staged binary | PASS |
| Never supervises `~/.local/bin` | PASS |
| KeepAlive restarts after kill (same session) | PASS `68570 → 68943` |
| Logout/login BTM re-adoption | **NOT RUN** (deferred) |

## Follow-up

- Full SC-S04: see `docs/phases/sprint/serve-continuity/SC-S04-logout-login.md` when a clean logout is possible.
- Optional: harden install-cli refresh when bootstrap races a live agent (I/O error 5) — enable already recovers; not blocking.
