# Capacity Native Channels — stop scraping a repainting terminal

Status: **v1 — findings verified, no slice authorized.** Founder ruling needed
on scope and on the credential posture in §4.
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

## 4. Founder ruling needed — credential posture

Archetypes 1 and 3 need nothing. Archetype 2 (`cursor_agent`, and grok's
refresh) requires reading a token the vendor already stored, from Keychain or a
file.

This does **not** breach *no API keys / no BYOK* — it is the user's own existing
CLI login, never a key they paste. But it is a posture change: Allnighter would
read a credential it does not today, and Keychain access prompts on first use
per calling binary.

Per the standing rule that a permission prompt is fine **if** the CLI explains
what, why, where it goes, and the decline path **before** triggering it, the
question is not whether prompting is allowed but whether we want token-reading
at all when two of six sources need it. Options:

| Option | Scope |
| --- | --- |
| **A** | Archetypes 1 + 3 only. `agy`, `codex`, `kimi`, `claude_code` move; `cursor_agent` and `grok` keep the TUI scrape. Zero credential change. |
| **B** | All six, with upfront disclosure before any Keychain read. |
| **C** | 1 + 3 now, revisit 2 after the first four prove out. |

Lean: **C.** It takes four of six off the racy path immediately with no posture
change, and lets the two credential-reading seats be judged on evidence from a
migration that already worked.

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
