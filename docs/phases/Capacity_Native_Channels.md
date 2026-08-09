# Capacity Native Channels — stop scraping a repainting terminal

Status: **v6 — four native channels SHIPPED; kimi RULED OUT; cursor stays a screen; model-read shadow mode SHIPPED.**

| Source | Channel | Commit |
| --- | --- | --- |
| `agy` | `--print "/usage" --output-format json` | `c82520ac` |
| `codex` | `app-server` JSON-RPC `account/rateLimits/read` | `275b737f` + `2a96de2f` |
| `claude_code` | `cachedUsageUtilization.utilization.limits[]` | `335d96a1` + `90bd2690` |
| `grok` | newest `billing: fetched credits config` in `unified.jsonl` | `7fd1d18f` |
| `kimi` | **none — ruled out, see §4c** | — |
| `cursor_agent` | **none — permanent screen** | — |

Cross-cutting correctness fix from the same batch: `220b4f35`.

**Model-read shadow mode SHIPPED 2026-08-09 (`5c191432`)**, founder-approved.
`alln capacity --refresh --source <id> --shadow-pane-reader` runs the model
reader alongside the deterministic parser and logs disagreements to
`Capacity/shadow/disagreements.jsonl`. It never changes a published number and
never introduces a failure. **Explicit CLI flag only** — `CapacityRefreshScheduler`
(serve's background tick) and `CapacityResidentService` structurally cannot reach
it, so it cannot become recurring background spend, and there is no persisted
setting to leave on by accident. Contract 9.11.0 → 9.12.0, binary 0.12.3 → 0.12.4.

It exists for one reason, and it is not doubt about accuracy — that is settled at
10/10. **A wrong argv is indistinguishable from an unavailable vendor**, because
every failure path in the reader returns nil by design. Shadow mode makes that
silence visible. Reproducing the known `-m` vs `--model` landmine produced a
`kind: "modelSilent"` entry while the published value held at 52.

First live result, recorded for the founder's standing bet (*"it will show it is
not needed; insurance will break first"*): on a real refresh, parser and model
**agreed**, and agreement is not logged. One data point, in the direction of the
bet.

Keychain CLOSED permanently (§4); model-read of a captured pane
SHIPPED (§4b, `e2c5cc76` + `f6658005`). Per-source native-channel slices are
next and unstarted.** Five of six sources move with zero credentials; only
`cursor_agent` keeps the PTY scrape, and it now has a model reader behind it.
Owner: AllnighterCore (`CapacityProbe`, `CapacityAcquisition`, `CapacityFetch`)
Created: 2026-08-08
Origin: Founder, 2026-08-08, after a day of capacity outages:
*"Odd that it works only some of the time. I thought software was predictable
but there is something we are missing."* and *"have K3 or DeepSeek V4 Pro think
creatively if there is another more reliable way to capture the screens."*

Companion: [`Probe_Freshness.md`](Probe_Freshness.md) (freshness + the refuted
"capacity is a table" redesign, §0.4).

---

## 1. Why

Capacity is read today by PTY-spawning each vendor's **interactive TUI**, typing
`/usage` or `/status`, and regex-parsing the rendered screen. Every capacity bug
on 2026-08-08 came from that choice, and none was a parser bug:

| Defect | Cause |
| --- | --- |
| codex + grok reported `parserFailed` for hours | readiness/attribution, parsers were fine |
| a readiness guard never fired | misspelled marker (`escrtointerrupt`) |
| codex declared ready while still booting | generic marker `"tip:"` matched its own boot chrome |
| cursor claimed a usage pane had rendered | generic words `"settings"`/`"config"` matched a chat composer |
| codex hung indefinitely | built-in `codex_apps` MCP server never finishes starting |
| full-bench refresh failed 2 of 6 runs | **machine load** — 103 leaked processes; probes are load-sensitive |

That last row is the tell. A correct parser, a correct guard, and a correct
budget still produced wrong answers because *the machine was busy*. Screen
scraping an animated TUI is timing-sensitive by construction; it cannot be made
deterministic by fixing individual matchers.

## 2. Finding — every source has a better channel

Investigated 2026-08-08 by K3 (run `088DFB73`), read-only, **verified by
execution** on the dogfood host unless marked otherwise. Two permitted
archetypes, and one that is forbidden:

1. **CLI-owned local JSON** — a headless command or local server where the vendor
   binary does auth and refresh internally and emits typed JSON. Race-free,
   credential-free.
2. **On-disk cache/log the CLI already writes** — zero cost, zero credentials;
   freshness bounded by last CLI activity, so it must fail closed on staleness.

**Forbidden — do not propose it again:** a vendor HTTP endpoint reached by
reading a credential the vendor stored (Keychain item, token file we did not
cause to exist). Typed JSON and no spawn make it *look* like the best archetype,
which is exactly why it keeps coming back. It is ruled out permanently — see §4.
The two archetypes above are the whole option space.

| Source | Best channel | Archetype | Credentials |
| --- | --- | --- | --- |
| `agy` | `agy --print "/usage" --output-format json --print-timeout 25s` — ~1s, **zero model tokens**, structured `groups[].buckets[]` with `remaining_fraction` + `reset_time` for all four buckets | 1 | none — CLI refreshes in-process |
| `codex` | `codex app-server --listen stdio://` → JSON-RPC `initialize` / `account/rateLimits/read` → typed `rateLimits.{primary.usedPercent, resetsAt, credits, planType}`; also `unix://`, a durable `daemon` mode, and a push `account/rateLimits/updated` | 1 | none — CLI owns auth |
| `kimi` | `kimi web --no-open --port <p>` → `GET /api/v1/oauth/usage` with `~/.kimi-code/server.token` → weekly + 5h windows, absolute `reset_at`, typed error kind | 1 | none — the token belongs to the loopback server **we launched**, in the process we own; it is not a stored vendor credential (see §4) |
| `claude_code` | `cachedUsageUtilization` in `~/.claude.json` — five_hour/seven_day utilization, reset times, spend; `fetchedAtMs` observed ~5 min old under active use | 2 | none |
| `cursor_agent` | **none.** The Connect-RPC `DashboardService/GetCurrentPeriodUsage` endpoint exists and returns exactly what we want, but reaching it means reading the Keychain item `cursor-access-token` — forbidden. PTY scrape stays, with the model reader behind it. | — | forbidden channel; no permitted one exists |
| `grok` | newest `billing: fetched credits config` line in `~/.grok/logs/unified.jsonl` (weekly period, `creditUsagePercent`, prepaid balance, tier) | 2 | none — read-only on a log the CLI already writes |

**`agy` is the headline.** Slash commands run in **print mode** — one second,
no model tokens, structured JSON, no PTY. If that pattern generalizes to other
CLIs it removes the TUI entirely for those seats; nobody had tried it.

**`grok` is the weakest** — no headless quota method exists (`x.ai/billing` over
ACP stdio returns `-32601`, verified), so the log read is all we get. We do not
trigger the `GET cli-chat-proxy.grok.com/v1/billing` refresh ourselves; that
would need grok's stored token. We read what the CLI last wrote and **fail
closed when it is stale**, which is the honest version: a log line is evidence of
what was true when grok last checked, never evidence of now.

## 3. Why this deletes the bug class

Each channel is attributed to its own `sourceId` by construction — a vendor's
own file, endpoint, or JSON output. That is the Vendor Signal Isolation law
enforced structurally rather than by remembering to scope a matcher. There is no
shared marker list to false-positive across vendors, so the misspelled guard,
the `"tip:"` match, and the `"settings"`/`"config"` match could not have
happened. Empty-parse blame disappears with the parse.

Failure modes do not vanish, they change shape — and the new ones are the kind
that fail loudly:

| Old | New |
| --- | --- |
| repaint races, load sensitivity | on-disk staleness (`claude_code`, `grok`) |
| generic marker false positives | output schema drift in a vendor's own JSON |
| TUI hangs (MCP boot, splash screens) | process lifecycle for `kimi web`, `codex app-server` |
| orphaned PTY children | a headless command that hangs instead of printing |

Token expiry and Keychain prompts are **absent from this table on purpose** —
they were the cost of the forbidden archetype, and it is not on the table (§4).
Nothing here requires us to hold, refresh, or prompt for a secret.

Mitigation for staleness: check `fetchedAtMs`/mtime/log age and fail closed —
absence of a declared signal yields no observation. A stale reading presented as
current is the expensive failure; no reading at all is the cheap one.

## 4. Credential posture — SETTLED, NOT OPEN

**Law: Allnighter never reads another vendor's stored credential to learn
capacity. If the user is logged into the CLI, ask the CLI.**

Founder ruling, restated 2026-08-08 — *"Keychain is NEVER ok. Already rejected
many times."* This has now been proposed and rejected repeatedly. It is not a
lean, a default, or a posture pending review: **the Keychain is closed.** An
agent that finds a beautiful authenticated endpoint has found the thing this
section exists to refuse. Do not reopen it; do not add it as a fallback, an
opt-in, an advanced setting, or a "power user" path.

Scope of the law, precisely: it forbids reading a secret **the vendor stored**
— Keychain items, token files, session cookies we did not cause to exist. It
does not forbid reading a token that a process **we launched** wrote for its own
loopback server in this run (`kimi web`), because that is our own process's
handle, not the user's vendor credential. If that distinction ever needs
stretching to justify a channel, the channel is forbidden.

From first principles, reading a vendor's token is a strictly worse version of
asking the vendor's CLI. It returns the *same information* and adds:

- a Keychain prompt attributed to **our** app on first run — for someone who
  just downloaded Allnighter, that is the difference between "it works" and a
  scary permission dialog about another company's account;
- token expiry as our problem, when the CLI already refreshes it;
- a binding to unofficial endpoints that drift with no contract.

There is no upside to trade against that. So the authenticated-endpoint
archetype is not a fallback we hold in reserve — it is off the table for
capacity, permanently.

### What that costs, measured

`agy` proved slash commands run in print mode, so the obvious question was
whether that generalises. Tested 2026-08-08:

| Source | Credential-free channel | Verified |
| --- | --- | --- |
| `agy` | `--print "/usage" --output-format json` | all four buckets, ~0s |
| `codex` | `app-server` JSON-RPC `account/rateLimits/read` | typed, CLI owns auth |
| `kimi` | `kimi web` headless server | weekly + 5h, typed error kind |
| `claude_code` | `cachedUsageUtilization` in `~/.claude.json` | CLI keeps it fresh |
| `grok` | `billing: fetched credits config` in `~/.grok/logs/unified.jsonl` | **cross-validates the TUI exactly** — `creditUsagePercent: 8.0` vs TUI 92% remaining; period end `2026-08-14T18:11:40Z` vs TUI reset `18:11`. No secrets in the payload. |
| `cursor_agent` | **none — verified exhaustively, see below** | the only source with no credential-free structured channel |

**Five of six move with zero credentials and zero setup.** `cursor_agent` keeps
the PTY scrape as its own last-resort fallback, which the per-source seam
already allows — one racy source is a far better place to be than six, and it
costs the user nothing to set up.

### cursor_agent — investigated 2026-08-08, no structured channel exists

Checked whether cursor writes usage state on launch the way grok does. It does
not, verified four ways:

| Probe | Result |
| --- | --- |
| Diffed **32,578** files under `~/.cursor` and `~/.local/share/cursor-agent` across one probe | exactly 4 changed — `cli-config.json`, `skills-cursor/.sync-manifest.json`, `statsig-cache.json`, `projects/.../worker.log`. **None contains quota data.** |
| `cursor-agent about --format json` | `subscriptionTier` only, no numbers |
| `cursor-agent status` | auth only — "Logged in as …" |
| `cursor-agent -p "/usage"` | answered as a CHAT PROMPT: 184 output + 21.9k cache-write tokens |

`statsig-cache.json` is 672KB and matches "usage" many times, but every hit is UI
copy ("Analyze usage", "Additional usage beyond limits consumes on-demand
spend") — feature-flag and prompt config, not quota. `worker.log` is LSP
indexing.

So cursor's only quota sources are the rendered TUI pane, or the authenticated
Connect-RPC endpoint that §4 rules out. **The ruling stands**: for a user who
just downloaded the app, a scrape that needs no setup beats a reliable endpoint
that opens a Keychain prompt about their Cursor account on first run.

**Consequence: cursor_agent is the one permanent screen-scraping seat**, which
settles the scope of the LLM-fallback idea — it has exactly one customer, now
and after the migration.

### 4c. kimi — RULED OUT 2026-08-08, do not implement

The packet listed `kimi web --no-open --port <p>` → `GET /api/v1/oauth/usage` as one
of the five credential-free moves. Measured before building it, that turned out to
be wrong on all three counts that matter.

**There is nothing to gain.** kimi's PTY parse already publishes
`dashboardResetAt: 2026-08-14T19:14:38Z` — full vendor seconds, not the
minute-truncated value that gave codex and grok their improvement — plus both
windows (`shortWindowNone: false`). Unlike agy (which was silently dropping two 5h
windows) or codex (which was publishing a reset 7 hours early), kimi's screen scrape
is already correct and complete.

**The credential boundary does not hold.** `~/.kimi-code/server.token` exists on
this host right now, mode `600`, written the previous day — it predates any server
we would launch. §4 permits reading a token that a process **we launched** wrote for
its own loopback server **in this run**; it forbids reading a secret the vendor
stored. A pre-existing 600-mode token file is the second thing, not the first, and
§4 already says that if the distinction needs stretching to justify a channel, the
channel is forbidden. It needs stretching here.

**It inverts the point of the packet.** Every channel that shipped *removed* a
spawned process. kimi's would *add* a long-lived HTTP server to the refresh path —
the same process-lifecycle class that leaked 103 orphaned vendor CLIs on
2026-08-08, loaded the machine to 12.75, and caused the "flaky" capacity this whole
packet exists to fix.

No gain, a credential posture that only works if the rule is bent, and new orphan
risk on the exact path we just cleaned. **kimi keeps the PTY scrape.** Reopening
this needs a founder ruling and a reason that is not "the endpoint is nicer."

Consequence: **two** sources stay on the screen, not one — `cursor_agent` because no
structured channel exists, `kimi` because the one that exists is not worth its cost.
Both keep the model reader behind them.

### grok — investigated 2026-08-08, and it generalises

The open question was whether a cheap non-interactive invocation could refresh
the billing line without a TUI. Measured, watching the newest
`billing: fetched credits config` timestamp across each invocation:

| Invocation | Refreshes billing? |
| --- | --- |
| `grok --version` | no |
| `grok models` | no |
| `grok inspect` | no |
| `grok agent` (documented as "run Grok without the interactive UI") | no |
| **our existing capacity probe spawn** | **yes — fresh line within the 7s probe** |

Only a full interactive session fetches billing; the entry carries
`src: "shell"`. So grok cannot be refreshed headlessly.

**That is a better answer than it first looks.** We already spawn grok. The
expensive, fragile part was never the spawn — it was everything after it: typing
`/usage`, racing the slash menu, matching markers against a repainting screen,
and parsing ANSI. Keeping the spawn as a *trigger* and reading the *structured
log* as the answer deletes all of that and leaves: spawn → wait for a JSON line
to appear → kill. Waiting for a line in a JSONL file is a discrete event with a
clear signal; waiting for a TUI to finish repainting is not.

And the log is strictly richer than the screen it replaces:

| | TUI scrape | log line |
| --- | --- | --- |
| remaining | 92% | 92.0% |
| reset | `18:11:00` — truncated to the minute by the rendered text | `18:11:40.374130` exact |
| tier | absent | `X Premium+` |
| prepaid balance, on-demand cap | absent | present |

**Generalised law for the migration: spawn may remain, screen-scraping must
go.** Where a vendor writes structured state to disk, the CLI's own launch is an
acceptable trigger — what must never remain in the loop is parsing a rendered
terminal. That reframes `cursor_agent` too: the question for it is not "is there
a headless endpoint" but "does it write its usage anywhere structured on
launch", which is not yet answered.

Freshness still needs honest handling: the reading carries the log entry's own
timestamp and must fail closed when stale, never re-stamped to now.

## 4b. Measured: a cheap model reads the captured text — 10/10

Founder, 2026-08-08: *"trust the agent. Your fear it will invent shit is not
supported by data... if we ALWAYS have the text this should be our fallback
everywhere. Use the cheapest model of the CLI. My gut 10x simpler and dead
accurate. You can test it."*

Tested rather than argued. Real captures taken from live probes (the probe was
temporarily made to dump successful panes too), fed to
`model_cursor_composer_25` — the cheapest Cursor seat — and scored against what
the deterministic parser reported for the *same* refresh.

| Case | Truth | Model | Verdict |
| --- | --- | --- | --- |
| agy success | 93.19 | 93.19 | correct |
| claude_code success | 26 | 26 | correct |
| codex success | 97 | 97 | correct |
| grok success | 92 | 92 | correct |
| kimi success | 51 | 51 | correct |
| cursor success | 52 | 52 | correct *(see below)* |
| claude_code splash/boot | unknown | `null`, `confident: false` | correct |
| codex boot chrome | unknown | `null`, `confident: false` | correct |
| cursor composer | unknown | `null`, `confident: false` | correct |
| grok splash animation | unknown | `null`, `confident: false` | correct |

**Zero hallucinations across four negative cases.** Each returned null with
`confident: false` and an honest reason ("Splash screen only, no quota data").
The lead's stated fear that a model would invent a number was not supported.

The only initial miss was cursor, reported as 57 against a parser value of 52 —
and it was **not** a model error. Cursor's pane lists three pools:

```
Included  43% used → 57 remaining
Auto      42% used → 58 remaining
API       48% used → 52 remaining   ← parser's "effective"
```

The model read `Included`, a real row, correctly converted. The prompt simply
never said which pool wins when there are several. Re-asked with that specified,
it returned all three pools and `mostConstrainedRemaining: 52` — exact. It also
surfaced the `Included` pool, **which our regex parser does not track at all**.

### Why this is the stronger design, not just an equal one

One generic prompt read **six different vendors' screen formats**. The
deterministic path needs, per source: a readiness predicate, a marker list, a
usage-pane detector, and a parser — every one of which broke today.

Untested, and honest about it: per-call cost and latency at a real cadence;
behaviour on a genuinely rate-limited vendor (the "if it fails to run, that IS
the unavailability answer" claim); run-to-run consistency (one sample each); and
half-painted panes, since the negatives here were splash and boot chrome rather
than partial renders.

## 5. Migration shape (not authorized)

The TUI scrape does not have to die at once. It is already a per-source
`CapacityProbeExecuting` seam, so each source can move independently with the
scrape demoted to last-resort fallback for that source only. That means:

- one vendor per slice, each with a measured before/after on reliability and
  wall-clock;
- no big-bang cutover, no shared-marker refactor;
- `probeableSources` shrinks as sources graduate.

Non-goals: owning token refresh; any API-key path; a shared cross-vendor
classifier (that is the bug class being deleted).

## 6. Open questions

1. Does `--print "/usage"` generalize beyond `agy`? It was not tried on the
   others and would be the cheapest possible win.
2. Does codex's `account/rateLimits/updated` push let capacity become
   event-driven instead of polled, removing the freshness clock for that seat?
3. `agy` logged out silently skips quota refresh rather than erroring — how does
   a channel report "I could not tell" without inventing an observation?
4. Does a native channel change the freshness window? A file the CLI rewrites
   every few minutes is fresher than any 30-minute poll.
