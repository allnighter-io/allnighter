# Capacity Native Channels — stop scraping a repainting terminal

Status: **v2 — findings verified; credential posture RULED (§4). Ready for
per-source slices.** Five of six sources move with zero credentials; only
`cursor_agent` keeps the PTY scrape.
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
execution** on the dogfood host unless marked otherwise. Three archetypes, in
order of preference:

1. **CLI-owned local JSON** — a headless command or local server where the vendor
   binary does auth and refresh internally and emits typed JSON. Race-free,
   credential-free.
2. **Vendor HTTP endpoint on the existing session** — typed JSON, no spawn, but
   Allnighter must read a token the vendor already stored.
3. **On-disk cache/log the CLI already writes** — zero cost, zero credentials;
   freshness bounded by last CLI activity, so it must fail closed on staleness.

| Source | Best channel | Archetype | Credentials |
| --- | --- | --- | --- |
| `agy` | `agy --print "/usage" --output-format json --print-timeout 25s` — ~1s, **zero model tokens**, structured `groups[].buckets[]` with `remaining_fraction` + `reset_time` for all four buckets | 1 | none — CLI refreshes in-process |
| `codex` | `codex app-server --listen stdio://` → JSON-RPC `initialize` / `account/rateLimits/read` → typed `rateLimits.{primary.usedPercent, resetsAt, credits, planType}`; also `unix://`, a durable `daemon` mode, and a push `account/rateLimits/updated` | 1 | none — CLI owns auth |
| `kimi` | `kimi web --no-open --port <p>` → `GET /api/v1/oauth/usage` with `~/.kimi-code/server.token` → weekly + 5h windows, absolute `reset_at`, typed error kind | 1 | vendor-written local token |
| `claude_code` | `cachedUsageUtilization` in `~/.claude.json` — five_hour/seven_day utilization, reset times, spend; `fetchedAtMs` observed ~5 min old under active use | 3 | none |
| `cursor_agent` | Connect-RPC `POST api2.cursor.sh/aiserver.v1.DashboardService/GetCurrentPeriodUsage` → `planUsage.{totalPercentUsed, limit}`, cycle bounds, spend limits | 2 | Keychain `cursor-access-token` |
| `grok` | newest `billing: fetched credits config` line in `~/.grok/logs/unified.jsonl` (weekly period, `creditUsagePercent`, prepaid balance, tier), refreshed by `GET cli-chat-proxy.grok.com/v1/billing` | 3 + 2 | vendor-written token for the refresh |

**`agy` is the headline.** Slash commands run in **print mode** — one second,
no model tokens, structured JSON, no PTY. If that pattern generalizes to other
CLIs it removes the TUI entirely for those seats; nobody had tried it.

**`grok` is the weakest** — no headless quota method exists (`x.ai/billing` over
ACP stdio returns `-32601`, verified), so it needs two channels to cover the
full picture.

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
| repaint races, load sensitivity | token expiry |
| generic marker false positives | endpoint schema drift |
| TUI hangs (MCP boot, splash screens) | Keychain ACL prompt on first access |
| orphaned PTY children | process lifecycle for `kimi web` |

Mitigation for expiry: **re-read the credential the vendor just refreshed;
never own refresh.** Mitigation for staleness: check `fetchedAtMs`/mtime/log age
and fail closed — absence of a declared signal yields no observation.

## 4. Credential posture — RULED

Founder 2026-08-08: *"lean whatever helps us move forward in right direction.
Answers should be simple and obvious thinking from first principles. I want this
to work for any user that will soon be downloading our apps."*

**Law: Allnighter never reads another vendor's stored credential to learn
capacity. If the user is logged into the CLI, ask the CLI.**

From first principles, reading a vendor's token is a strictly worse version of
asking the vendor's CLI. It returns the *same information* and adds:

- a Keychain prompt attributed to **our** app on first run — for someone who
  just downloaded Allnighter, that is the difference between "it works" and a
  scary permission dialog about another company's account;
- token expiry as our problem, when the CLI already refreshes it;
- a binding to unofficial endpoints that drift with no contract.

There is no upside to trade against that. So archetype 2 is not a fallback we
hold in reserve — it is off the table for capacity.

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
