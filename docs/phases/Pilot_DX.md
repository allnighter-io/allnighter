# Pilot DX — from good to great for a cold piloting agent

Status: **SHIPPED** (2026-07-16, rounds 1–3 on `feat/design-chain`)
Owner: AllnighterCore + CLI
Updated: 2026-07-16

Source: third fresh-agent field report (a Grok CLI session correctly chose Pilot
from docs alone — the product story lands; the friction is first-run ergonomics).
PM verification reproduced the load-bearing claims before this spec was written.

## Pushbacks (decided, not building)

- Gate does NOT rewrite bad clauses — it quotes them; the PM rephrases (verbatim law).
- No `project next-work` README parsing — picking the slice is the PM's judgment.
- No profiles noun yet — remember last-used seat per project instead; revisit later.

## DX1 — one help truth path (top footgun) — SHIPPED

Verified: `alln docs pm_relay` → "no docs for topic" while `alln help get pm_relay`
works (two topic namespaces); `alln pair pilot start --help` returns a usage ERROR
envelope instead of help.

**Acceptance:** `docs <topic>` and `help get <topic>` resolve the same registry (one
namespace or a hard redirect); `--help`/`help` on EVERY subcommand prints usage +
exit 0 (never an error envelope, never requires other flags); a drift test walks all
registry commands asserting `--help` behaves; a second test asserts every top-level
help topic name resolves via both `docs` and `help get`.

## DX2 — bootstrap: fix the argv[0] identity bug + teach Pilot — SHIPPED

Verified root-cause hypothesis: invoked as bare `alln` from PATH, argv[0] has no
slash; realpath against cwd fabricates `<cwd>/alln` (the field report's
`websitemd.studio/alln`, `onPath:false`). Absolute invocations resolve correctly.

**Acceptance:** binary self-resolution handles the three argv[0] shapes (absolute,
relative-with-slash, bare-name → PATH search) with tests; `install-cli`,
`binary.onPath` doctor check, and bootstrap all use the one resolver. Bootstrap
snippet gains a compact Pilot recipe (~6 lines: start / write handover / handoff
--verdict --handover-file / review repoDelta / done-by-declaration) for all hosts —
Pilot is the agent front door (Pilot_Relay.md §1.8); snippet stays ≤ 15 lines total.

## DX3 — worker-readiness honesty (the brick wall) — SHIPPED

Field report: `project workers` → 7× `unsafeToProbe` with a generic "open CLI once"
hint; agent couldn't tell whether pilot start would fail. Truth: pilot does NOT
gate on project-worker probes; global seat readiness is what matters.

**Acceptance:** `unsafeToProbe` detail says exactly that: "global seat ready;
project-level trust unprobed (driver declares no safe probe); pilot/relay may
start — this is not a blocker." `project workers --json` gains
`pilotReady: true|false` per seat derived from GLOBAL readiness; no new probe
machinery.

## DX4 — pilot start ergonomics — SHIPPED

**Acceptance:** `--dev-worker` accepts an unambiguous alias (case-insensitive
substring/suffix of id or displayName; ambiguous → error LISTING the candidates,
e.g. `sonnet` → model_sonnet vs model_agy_sonnet); start output (human + JSON)
includes the exact next command with the relay id filled in AND the path of a
scaffolded `round1.md` it wrote into the relay state dir; new
`alln pair pilot scaffold-handover --relay <id> [--round N]` prints/re-emits the
template (suggested sections: goal / out of scope / pointers / proof required /
stop conditions — suggestions in comments, NOT required schema). Last-used dev
seat per project is remembered; `pilot start` without `--dev-worker` uses it (and
says so) or errors with candidates if none.

## DX5 — watch is the recovery story; freshness; tombstone — SHIPPED

**Acceptance:** `pilot watch --relay X --json` blocks until the in-flight round
settles and returns the SAME envelope as a blocking handoff (dev report included);
`pilot status` on a running round whose owner pid is DEAD but whose dispatch
survived says "handoff process alive/detached — run pilot watch" (productize the
works-test recovery); git observation (branch/dirty/head) freshened on pilot
start/status/handoff — never served stale from the project cache; `alln pair run`
/ `pair slice` print a one-line tombstone ("the slice queue was retired — see
`alln help get pm_relay`") + exit 2 instead of the bare usage line.

## DX6 — doctor: fast by contract, pilot-aware — SHIPPED

Field reports twice describe doctor hanging in agent environments (measured 4s
here — still slow for a first-contact call).

**Acceptance:** default `doctor --json` completes in ≤2s on this machine (find and
fix/skip whatever blocks — expensive probes move behind `--full`; name the cause
in the delivery report); a `doctor.pilot` summary check (or `--pilot` view)
answers: "can a pilot start now with <seat> on <project>? yes/no + the exact
blocking check + fixCommand." Timing asserted by a test with injected slow probes
(bounded, not wall-clock flaky).

## Works test (cold-agent replay)

From a fresh shell on PATH: `alln bootstrap` (correct identity, Pilot recipe) →
`alln --help` → every advertised topic resolves via BOTH `docs` and `help get` →
`pair pilot start --doc <spec> --project . --dev-worker sonnet` (alias resolves,
scaffold written, next command printed) → `pilot handoff --verdict continue
--handover-file <scaffold>` → kill the shell mid-round → `pilot status` names the
recovery → `pilot watch` returns the dev report → doctor default ≤2s. Filters
`Relay|Pilot|Help|Doctor|Bootstrap|FrontDoor` green; contracts regenerated.

### Evidence (2026-07-16, round 3 closeout)

What a cold agent now experiences on a rebuilt binary:

1. **Help/docs:** one namespace — `alln help get pm_relay` and `alln docs pm_relay` both resolve; `--help` on pilot subcommands exits 0.
2. **Bootstrap:** `alln bootstrap` prints correct binary identity + 6-line Pilot recipe.
3. **Start:** `alln pair pilot start --doc docs/phases/Pilot_DX.md --project . --dev-worker composer` resolves alias, writes scaffold, prints filled `next` command; second start recalls remembered seat.
4. **Workers:** `project workers --json` shows `pilotReady` per seat with honest `unsafeToProbe` detail (global seat, not a pilot blocker).
5. **Recovery:** `pilot status --json` on a live `.running` relay emits `PilotStatusJSON` with `recovery` + `nextActions` naming handoff-alive vs orphan-reconciled; `pilot watch --json` returns `PilotWatchJSON` (relay + devReport + note when nothing in flight).
6. **Freshness:** pilot start/status/handoff/watch call `resolveProjectFreshForPilot` — git branch/head/dirty re-observed, not served from stale project cache.
7. **Tombstone:** `alln pair run` / `alln pair slice` → stderr one-liner + exit 2.
8. **Doctor:** default path uses cached `SetupStore` probe records (no live `-lic` shell batch); fallback detect-only probes use 2s hard timeouts. Root cause of prior ~4s default: live `CLIDetector` with `interactive: true` login-shell resolve + per-driver `--version` subprocesses on every default call. `alln doctor --pilot --project . --json` includes `checks[].name == "pilot"` with yes/no + fixCommand.
9. **Tests:** `swift test --package-path Packages/AllnighterCore --filter 'Relay|Pilot|Doctor|Help'` → 294/294 green (1 skipped); `DoctorTimingTests` proves cached default path ignores injected 30s-blocking runner.
