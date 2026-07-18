# Relay Read-Only Removal — kill the toggle, keep the knowledge

Status: **Approved — founder call 2026-07-16**
Owner: AllnighterCore + CLI + Mac GUI
Updated: 2026-07-16

## Why (first principles, from the founder review)

`--pm-read-only` was built from an inference, not a user story. Re-derived from
actual users:

1. **The real concern was cost, not writes.** "The PM is often the more expensive
   model" is solved by seat choice, never by write policy.
2. **"Reviewer, don't write" is process — and process lives in the PM's prose.**
   The relay's own division-of-labor law says Allnighter never mechanizes the PM's
   process. HandoverGate mechanizes *danger*; this toggle mechanized *doubt*.
3. **The concurrency rationale doesn't apply.** "Read-only by mechanism" was coined
   for answer teams (N parallel workers, concurrent mutation = catastrophe). The
   relay is sequential by construction; a PM write is one commit with git undo —
   a recoverable non-event under the house safety doctrine.
4. **The fail-closed UX contradicts the product.** Flipping the toggle on a
   Cursor/Grok PM produced "your seat can't do this" — dictating how users use the
   CLIs they pay for, for a guarantee nobody asked for.

## Kill list (outright, no shims)

- `RelayReadOnlyEnforcer.swift` + `RelayReadOnlyEnforcerTests.swift`
- `RunRequest.requireReadOnly` + the `RunService` read-only branch +
  `RunServiceError.readOnlyUnsupported`
- `RELAY_PM_READONLY_UNSUPPORTED` error code (catalog + regenerated artifacts)
- `RelayCoordinator`: `Config.pmMayMutate`, the PM-turn read-only dispatch,
  the HEAD-moved belt-and-braces guard (it only ran in read-only mode)
- `RelayState.pmMayMutate` (+ its resume persistence and legacy-decode default)
- CLI `--pm-read-only` flag; MCP `pmReadOnly` param + start-time capability check
- Mac GUI: the "PM read-only" toggle, per-seat disable/annotation states, the
  view-model validation branch (re-seal the launch-form fixture after removal)
- All tests that exist only to cover the above
- `PM_Relay.md` §4.2: drop the read-only sentences; PM-may-mutate is simply how
  the relay works (turn-based = one mutating worker at a time, unchanged)

## Salvage (before deleting)

The per-driver capability table is hard-won knowledge for the day **answer-team**
mechanical read-only gets built (its real home). Record in
`Unified_Run_Model.md`'s safety section:

> Confirmed headless read-only mechanisms (2026-07-16): `claude_code`
> `--permission-mode plan`; `codex` `--sandbox read-only --ask-for-approval never`.
> `cursor_agent` headless documents full write+shell access (no plan enforcement);
> `grok`/`antigravity`/`opencode` expose no read-only/plan flag.

## Works test

- `alln pair relay` and the Mac launch sheet no longer mention read-only anywhere.
- Full Relay test filter green; launch-form GUI fixture re-sealed; contracts
  regenerated with the error code gone.
