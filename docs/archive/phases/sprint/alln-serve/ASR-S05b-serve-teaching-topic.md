# ASR-S05b — teach serve: one narrative topic, findable by the words people use

Status: **ready**
Priority: **P2 — §10's teaching item; agents cannot learn serve from the CLI today.**
SSOT: [`docs/phases/Alln_Serve_Hotfixes.md`](../../Alln_Serve_Hotfixes.md) §8
ASR-S05, §5.1 (command contracts), §4.2/§4.4 (restart, login, sleep behaviour).

## 1. Measured gap

`alln help search serve` **works** — it returns `serve`, `serve enable`,
`serve disable`, `serve repair`, `serve status`. Command discovery is fine and
this slice must not disturb it.

What is missing is the narrative. `alln help topics` returns 22 topics:

```text
quickstart, bootstrap, tool_selection, team_run_loop, loop,
teams_agents_and_skills, capacity, opencode_headless_completion,
opencode_mutating_commit_contract, opencode_go_capacity, park_cli,
default_model, pending, projects_and_threads, setup_and_auth, current_setup,
artifact, results_and_history, errors, auto_fix, schemas, recipes
```

**None** is about serve, background scheduling, login continuity, or what to do
when status is degraded. A caller who reads `alln help` learns the commands exist
but not what the thing is, when it matters, or how to recover it.

§8 ASR-S05 names the search terms this must answer: `serve`, `scheduler`,
`background`, `login`, `launchagent`, `capacity stale`, `pending stuck`,
`notification`, `repair`.

## 2. Copy-paste prompt

> Add one narrative help topic for `alln serve` to `HelpTopicRegistry`, findable
> by the words in §8 ASR-S05's search list. It explains what the background
> scheduler is, which obligations depend on it, that it survives logout/login and
> system sleep, what `degraded` means, and the one command that recovers it. Keep
> the claims to behaviour that is proven by the ASR-S06 gate records — do not
> teach aspirations.

## 3. Read only

- `Packages/AllnighterCore/Sources/AllnighterCore/HelpTopicRegistry.swift` — how
  a topic is declared and how search terms attach. Copy the `capacity` topic's
  shape.
- `docs/phases/Alln_Serve_Hotfixes.md` §5.1 (command table), §4.2 (restart
  contract), §4.4 (login and sleep), §6 (scheduler list).
- `docs/qa/alln-serve/` — the gate records. **The topic may only claim what these
  prove.** Gates 3, 4, 7, 8, 10, 11 are the source of truth for behaviour
  statements.

## 4. Touch only

```text
Packages/AllnighterCore/Sources/AllnighterCore/HelpTopicRegistry.swift
Packages/AllnighterCore/Tests/AllnighterCoreTests/HelpTopicRegistryTests.swift
```

## 5. Do not touch

`ContractRegistry`, `MenuCatalog`, `RetiredVocabulary`, any command
implementation, any script, generated contract artifacts. Command search already
works — do not "improve" it.

## 6. Steps

1. **One topic**, id `serve`. Not five.

2. **Content, in this order** — a reader in trouble reads top-down:
   - what it is: one supervised per-user background scheduler, started by
     launchd, no Dock app required;
   - what depends on it: the §6 schedulers — pending wake, PM turn wake, boost
     seed, vendor backoff, notifications, capacity refresh, probe record refresh.
     Say plainly that `alln run` does **not** depend on it; only deferred
     obligations do;
   - what survives: logout/login (gate 7), system sleep with a due deadline
     firing within 2 minutes of wake (gate 10), daemon crash (gates 3, 11);
   - what `degraded` means and that `serve status --json` names a recovery
     command in `recovery.command`;
   - `alln serve repair` as the one command that fixes most states, and
     `alln serve disable` / `enable` for deliberate control;
   - that a disable **persists** across login and reinstall (gate 8) — a user who
     forgot they disabled it will otherwise never look there.

3. **Attach the §8 search terms** so the listed words route here: `serve`,
   `scheduler`, `background`, `login`, `launchagent`, `capacity stale`,
   `pending stuck`, `notification`, `repair`.

4. **Claim only what the gates prove.** No "reliable", no "never fails". Where a
   bound exists, state the bound (2 minutes after wake; restart after
   `ThrottleInterval`). A topic that overstates is worse than no topic, because
   the reader stops checking.

5. **Do not teach retired vocabulary.** `--no-auto-serve` and
   `ALLN_NO_AUTO_SERVE` are deny-listed; detached auto-launch does not exist.

6. **Test it is reachable.** Assert `help get serve` returns the topic and that
   each §8 search term routes to it.

## 7. Works Test

```bash
scripts/swift-test.sh --filter 'HelpTopicRegistryTests'
bash scripts/rebuild_cli.sh
alln help get serve --json
alln help search "pending stuck" --json
alln help search launchagent --json
```

All safe and read-only. Run them and paste real output.

## 8. Done when

- [ ] One `serve` topic exists and `alln help get serve` returns it.
- [ ] Every §8 search term routes to it, proven by test.
- [ ] Behaviour claims trace to gate records; bounds are stated where they exist.
- [ ] The persistence of `disable` is called out.
- [ ] No retired vocabulary taught.
- [ ] Existing command search unchanged.
- [ ] Focused tests and `rebuild_cli.sh` pass. One commit.

## 9. Host-state invariant

Additive text in the help registry. No runtime behaviour changes.
