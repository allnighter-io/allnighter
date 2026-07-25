# Buzz Harness Spike — receipt in an attended room

Status: **SPIKE — exploratory, throwaway-permitted. Not a product commitment.
No laws change. No core contract changes allowed.** Deferred behind
`docs/phases/Team_Run_Receipt.md` (build the receipt first; then feel it here).
Owner: Founder (strategy), one short session (execution) after receipts exist
Updated: 2026-07-25 (reframed — drop firm/plural-member mythology)
Companion: `docs/strategy/Buzz_And_The_Judgment_Layer.md` — the why (revised).
Product path: `docs/phases/Team_Run_Receipt.md` — gorgeous private receipt.

## 2026-07-25 reframe

Original spike asked whether "alln as a firm / plural member" lands in Buzz.
**That framing is retired.** Live Buzz UI shows humans + single-model agents
(Opus, Fabel, Sonnet, …). There is no ALLN agent. Any agent (or human) can
call the alln CLI and run a team.

New spike question (only after Team Run Receipt exists):

> When someone in a Buzz channel has an agent call `alln`, and the **same
> Team Run Receipt** (or a faithful summary + link/path to it) lands in the
> thread, does the attended-room moment feel obviously valuable — or like a
> bot dumping JSON?

That is still a **legibility** test, not an engineering bet on Buzz.

## What this spike is not

- Not building an ALLN Buzz agent / harness identity as the product.
- Not per-seat Nostr identities / "firm worked in public" theater.
- Not private auth relay design.
- Not public Nostr publish by default.
- Not blocking or replacing Team Run Receipt.
- Not a standing `alln buzz` product surface.

## Prerequisites

1. Team Run Receipt S01+ available locally (`alln team open` or equivalent)
   for a completed team run — see `Team_Run_Receipt.md`.
2. Founder has already tasted the receipt in CLI (and optionally Mac Factory
   Floor). If CLI WOW is weak, fix the receipt — do not debug Buzz.

## Question this spike answers

Buzz (github.com/block/buzz) is an open-source workspace where people and
agents share a signed event log on a self-hosted relay. Single-model agents
are first-class members; they can invoke tools/CLIs.

Hypothesis worth testing (pattern, not marriage): **attended agent chat**
(Buzz today; Slack-with-agents tomorrow) is a natural *call site* for alln.
The durable object is the receipt. Buzz is one room that might make that
object feel native.

## Non-goals (read before building)

- **No open-sourcing anything.** Local / private workspace only.
- **No changes to AllnighterCore contracts, schemas, or run grammar** beyond
  consuming whatever Team Run Receipt already ships.
- **No federation, payments, reputation, per-seat identities.**
- **No new standing CLI surface.** Adapter in `labs/` (or scratch); deletable.
- **No unattended operation.** Live and attended, like every alln run.
- **No requirement that "alln" appear in Buzz's Agents grid.**

Laws intact: no API keys (panel still on user CLI subscriptions), no git
management, D5 (verdict about the work, never about alln), agent-first
schemas (consume structured CLI / receipt output only).

## Architecture (minimal)

Preferred path after receipts exist — **no special alln member**:

```text
Buzz channel (humans + ordinary agents)
  -> an agent (or human) shells out to existing alln CLI (team run)
  -> Team Run Receipt materializes locally (private by default)
  -> agent posts into the thread:
       short human summary + path/link to open the receipt
       (optional: attach export file or paste receipt summary events)
```

Optional throwaway bridge (only if manual agent-call is too clumsy for the
demo): watch a trigger, call CLI, post summary. Bridge is a **consumer** of
alln, never part of Core. Prefer TypeScript against Buzz client libs; do not
Swift-entangle.

Key design rule: **Buzz posts a projection of the receipt; the receipt's
home remains local / deliberate-share.** If Buzz dies mid-demo, `alln team
open` still works.

## Slices (revised)

**BZ-S00 — Stand up buzz, join as humans + stock agents.** Local relay + app.
Note event model in practice. Confirm Agents UI: humans, single-model
agents, Buzz "agent teams" — no ALLN identity required. Output: short notes.

**BZ-S01 — Call alln from an existing agent.** From a channel, have Fabel /
Opus / etc. run an alln team (Growth Min or Spec Review). No custom alln
member. Success: run completes; receipt exists on disk via Team Run Receipt.

**BZ-S02 — Receipt lands in the thread.** Agent (or human) posts the verdict
summary + how to open the gorgeous receipt (path, file attach, or later
deliberate share link). Success criterion is **how it reads in the room**,
not schema purity. Mid-run progress ping optional (dead air kills demos).

**BZ-S03 — Same object, second room (optional).** Repeat the feel test with
a Slack (or other) agent that can call `alln`. If Buzz-specific magic
vanishes and Slack feels the same, the wedge is the receipt + call site, not
Buzz.

**BZ-S04 — Retired.** Per-seat keypairs / "firm in public" — do not build.

## Demo artifact

One short recording: trigger → run → receipt summary in thread → open
gorgeous local receipt. Share with mentors next to the revised strategy memo.
Deliverable is the **feeling**, not a harness repo.

## Findings to capture

1. Room legibility: did the moment land? Founder + one outsider.
2. Impedance: Buzz vs alln (size limits, thread cadence, long runs).
3. CLI cold-drive friction for the calling agent → AE backlog.
4. Did Buzz add anything the CLI receipt + file share did not?
5. Effort hours; was "after receipts" the right sequence?

## Risks

- **Buzz immaturity.** Pin commits; accept breakage; spike only.
- **ACP single-agent assumptions.** If harness fights long team runs, bypass
  — have the agent shell `alln` directly. Moment > integration path.
- **Sandbox/spawn.** Prefer ordinary user terminal for the calling side;
  note dependencies; do not revive deleted resident broker mythology.
- **Premature Buzz polish before receipt WOW.** If S01 is ugly, stop and
  return to `Team_Run_Receipt.md`.

## Decision this spike feeds

None automatic. Outcomes:

- (a) Room moment lands → optional thin "post receipt to channel" helper
  later; still no Buzz marriage.
- (b) Muddy → keep investing in receipts + CLI; Buzz stays dogfood only.
- (c) Buzz too immature → shelve; retry when Slack/GitHub agent rooms are
  better call sites.

All three beat deciding from the membership mythology.
