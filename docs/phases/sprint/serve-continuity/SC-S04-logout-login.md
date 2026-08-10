# SC-S04 — Logout/login host proof (product `serve enable`)

Status: ready  
Slice: SC-S04 (host proof only — no product code)  
SSOT: [`docs/phases/Serve_Continuity.md`](../../Serve_Continuity.md) §4 SC-S04 + §5 + §6

## Goal

Prove start-at-login continuity: after `alln serve enable`, logout/login brings
serve back on the **staged** binary without a manual `alln serve`, with Dock app
quit, and doctor/health stay honest.

## Host procedure (founder or PM)

```text
1. Rebuild + install so PATH and staged binary match current tree:
     bash scripts/rebuild_cli.sh
2. Quit Dock app. Confirm no stray serve if you want a clean baseline
     (optional: alln serve --health --json).
3. Enable product agent (opt-in):
     alln serve enable --json
   Expect ProgramArguments under Application Support/.../CLI/alln (never ~/.local/bin).
4. Confirm live:
     alln serve --health --json          # available
     launchctl print gui/$(id -u)/com.allnighter.resident-coordinator
5. Quit Dock app again if open. Note capacity stamp:
     alln capacity --json   # or Capacity/_newest_success.json mtime
6. Log out of macOS user session (full logout, not only lock).
7. Log back in. Do NOT open the Dock app. Do NOT run `alln serve` manually.
8. Within ~30s:
     alln serve --health --json          # must be available
     alln doctor --json                  # serve.launchAgent must not be wedged/critical
9. Confirm capacity history can advance with app closed (wait one refresh window
   or trigger a benign capacity read after serve is up).
10. Log under docs/qa/serve-continuity/SC-S04-logout-login.md (PASS/FAIL + commands).
11. Optional cleanup: alln serve disable
```

## Done when

- [ ] Log exists with PASS (or FAIL with LWCR/BTM evidence)
- [ ] Packet `Serve_Continuity.md` SC-S04 marked DONE or FAIL-open with next fix
- [ ] No silent “looks supervised” wedge

## Not this slice

- SC-S05 admission recycled-PID
- SMAppService migration (current dogfood = product LaunchAgent on staged binary)
- Unrelated capacity/Ollama packets
