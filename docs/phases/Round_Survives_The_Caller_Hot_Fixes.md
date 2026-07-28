# Round Survives The Caller — Redesign (RSC-HF)

**Status:** In progress  
**Predecessor:** `Round_Survives_The_Caller.md` (S01–S05 shipped; audit: REFACTOR REQUIRED)  
**Constraint:** zero users → hard cut, no migration, zero dead code.

## Goal

`--no-wait` means: ack only after the child durably accepted the work, return the
real id, and never introduce a second dispatch state machine.

## Design (founder-confirmed)

1. **One detached-acceptance primitive** — parent creates a handoff directory,
   sets `ALLNIGHTER_DETACHED_HANDOFF`, spawns the same registered verb with
   `--no-wait` stripped, waits for `runner_ready.json` (`ProcessOwnership.RunnerReadyHandshake`).
   Child writes accepted/refused after durable claim. Reuse the handshake I/O that
   already exists; do **not** restore deleted `team __runner` / `AsyncTeamRunnerRequest`.
2. **Collapse relay** — delete `relay-continue`, `relay-start-continue`,
   `dispatchToken`, and the guard/continuation split for detachment. Child runs the
   normal `pair relay` / `relay-resume` / `relay adopt` path.
3. **Harden run identity** — remove public `--run-id`. Child mints/claims; handshake
   returns the actual id (including idempotency replay). Defense-in-depth: reject
   unsafe id path components in `RunStore`.
4. **Hard-fail lock persist** — no `try?` on the `.running` claim write.
5. **Hostile proofs** — real subprocess kill-caller + two-process race tests.
6. **P2** — preserve `--no-auto-serve`; GUI waits on guarded start; canonicalize
   doc identity; register detached ack schema.

## Out of scope

- Restoring resident/`--detach` control plane
- Migrating old on-disk `dispatchToken` values (hard delete field)
- Changing pilot handoff product semantics beyond sharing the acceptance wait

## Done when

- All P1/P2 from the mid-flight audit closed
- Hidden verbs and `dispatchToken` gone
- Dead `spawnDetachedRunner` path deleted if unused
- Works Test (real OS processes) green
- Both RSC docs archived per Execution Playbook

## Slices

| Slice | Goal |
| --- | --- |
| HF-S01 | `DetachedHandoff` + `DetachedDispatch.launchAndAwaitAcceptance` |
| HF-S02 | Collapse relay `--no-wait` onto normal verbs; delete hidden verbs/tokens |
| HF-S03 | Run `--no-wait` handshake; remove public `--run-id`; safe `RunStore` ids |
| HF-S04 | Hard-fail relay claim + P2 edge cases |
| HF-S05 | Hostile multi-process proofs |
| HF-S06 | Deslop, Code Audit, archive both RSC docs |
