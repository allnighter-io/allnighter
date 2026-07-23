# Buzz Harness Spike — An Alln Team as One Signed Member

Status: **SPIKE — exploratory, throwaway-permitted. Not a product commitment.
No laws change. No core contract changes allowed.**
Owner: Founder (strategy), one dev session (execution)
Updated: 2026-07-23 (drafted)
Companion doc: `docs/strategy/Buzz_And_The_Judgment_Layer.md` — the why.
This doc is only the how of the cheapest possible test.

## Question this spike answers

Buzz (github.com/block/buzz, released 2026-07-22) is an open-source workspace
where people and agents are equal members behind cryptographic identity: every
message, patch, review, and workflow step is a signed nostr event on a
self-hosted relay. Its harness model is one agent = one member (goose, codex,
claude code harnesses exist today, bridged via `buzz-acp`).

The strategic hypothesis (argued in the companion doc) is that alln's natural
position on such a substrate is **the only plural member**: one signed identity
that is secretly a firm — it convenes a multi-model panel and returns a signed,
permanent verdict into the same thread as the conversation that shaped the
spec.

The spike answers exactly one question:

> When a team on buzz types `@alln panel this spec` in a channel and a signed
> multi-model verdict lands in the thread minutes later, does "the firm as a
> member" feel obviously valuable — or like a bot posting a wall of JSON?

That is a legibility test, not an engineering test. Everything here is scoped
to produce that one moment as cheaply as possible.

## Non-goals (read before building)

- **No open-sourcing anything.** The spike runs against a private local relay.
- **No changes to AllnighterCore contracts, schemas, or run grammar.** The
  bridge is an adapter that *calls* the existing CLI; if the spike needs a core
  change, stop and report — that itself is a finding.
- **No federation, no payments, no reputation, no per-seat identities** beyond
  the stretch slice below.
- **No new standing surface.** No `alln buzz` subcommand in the shipped CLI.
  The adapter lives in `labs/` (or equivalent scratch area) and may be deleted
  the day after the demo.
- **No unattended operation.** The spike run is live and attended, like every
  alln run.

Laws that stay fully intact during the spike: no API keys (a nostr keypair is
an identity, not a vendor API key — the panel still runs on the user's own CLI
subscriptions), no git management (buzz owns git via NIP-34; alln never
touches it), D5 (alln never rates itself — the verdict is about the *spec*,
and no seat evaluates alln), agent-first schemas (the bridge consumes the
CLI's existing structured output; it never asks for a text mode).

## Architecture

```text
buzz relay (local, self-hosted)
  <- websocket ->
bridge adapter (new, ~small, throwaway)
  1. holds the "alln" nostr keypair, appears as one member
  2. watches subscribed channels for a trigger mention
  3. extracts the spec (message body, thread, or canvas reference)
  4. shells out to the EXISTING alln CLI: panel / spec-review run
  5. renders the structured result (verdict + impact ledger) into
     signed events posted back into the originating thread
```

Key design rule: **the bridge is a consumer of alln, not a part of it.** It
exercises the same public CLI surface any host agent uses. This doubles as a
free cold-consumer test of the CLI's agent ergonomics (see the AE memory:
the CLI historically under-reports itself; a bridge that struggles is data).

Bridge language: whatever is fastest against buzz's client libraries (their
stack suggests TypeScript is the path of least resistance). It does not need
to be Swift and should not be — that would tempt core entanglement.

## Slices

**BZ-S00 — Stand up buzz, join as humans.** Run a local relay + desktop app.
Founder + one dev join with their own keys. Create a channel, post, open a
thread, look at the raw event log. Output: one paragraph of notes on what the
event model actually is in practice (kinds used, size limits observed, how
threads reference parents). No alln code.

**BZ-S01 — Alln gets a name.** Generate a keypair for `alln`, join the
workspace as a member, post one signed hello from the bridge skeleton.
Success: the alln member appears in the member list indistinguishably from a
person, and the event is verifiably signed by its key.

**BZ-S02 — Summon and run.** Bridge watches one channel for a trigger
(`@alln panel …` or a reaction — pick whatever buzz makes idiomatic). On
trigger it posts an immediate signed acknowledgment ("panel convening: N
seats"), runs the existing panel/spec-review via the CLI, and streams at
least one progress event mid-run (long silences are where the demo dies —
cold spawns alone are ~22s of dead air, a full panel is minutes).

**BZ-S03 — The verdict is a record.** Post the result into the thread as
signed events: a human-readable verdict summary message, plus the impact
ledger. Decide during the slice whether the ledger is one event, an event per
finding, or a canvas — judge by how it *reads* in the buzz UI, not by schema
purity. The raw structured payload can ride along in an event tag for
machines. Success: scroll the thread top to bottom and it reads as a
conversation that ends in an attributable judgment with a permanent record.

**BZ-S04 (stretch, only if S03 lands well) — Seats as identities.** Give each
panel seat its own keypair so the thread shows distinct signed members
deliberating (claude-seat, codex-seat, …) rather than one alln member
narrating. This is the difference between "a bot ran a job" and "a firm
worked in public." Skip without guilt if time runs out — S03 alone answers
the spike question.

## Demo artifact

Record the S03 (or S04) run end to end: the mention, the acknowledgment, the
progress, the verdict landing in the thread, then a click into an event
showing the signature. One recording, shareable with mentors alongside the
strategy memo. This recording *is* the spike deliverable.

## Findings to capture (the actual output)

1. The legibility verdict: did the moment land? Founder's honest read, plus
   the reaction of at least one person who didn't build it.
2. Impedance mismatches: everywhere buzz's model and alln's model disagreed
   (event size vs. ledger size, threading vs. run structure, identity vs.
   seats, long-run progress vs. chat cadence). This list is the real spec for
   any future harness.
3. CLI ergonomics friction: everything the bridge author had to learn the
   hard way about driving alln cold. Feed to the AE backlog.
4. Effort: actual hours and where they went. The strategy memo claims this is
   weekend-scale; verify or falsify.

## Risks

- **Buzz is a week old.** APIs and event kinds may shift under us; the relay
  may be rough. Acceptable for a spike; pin the commit we build against.
- **ACP harness assumptions.** `buzz-acp` likely assumes a single
  conversational agent loop; a panel run is long and plural. If the harness
  fights us, bypass it and speak relay events directly — the spike tests the
  *moment*, not the integration path.
- **Sandbox/spawn interaction.** The bridge spawning `alln` which spawns
  vendor CLIs must not recreate the sandbox-inheritance failure the Resident
  Execution Broker exists to solve. If the resident path (`alln serve`) is
  far enough along, route through it; otherwise run the bridge from an
  ordinary user terminal and note the dependency.

## Decision this spike feeds

None automatically. Results go to the founder next to the strategy memo. The
possible outcomes are: (a) the moment lands → decide whether to spec a real
harness phase; (b) the moment is muddy → the strategy memo's Move 1 loses its
cheapest proof and the thesis needs a different test; (c) buzz itself is too
immature → shelve with findings, revisit when the substrate pattern recurs
elsewhere. All three are wins over deciding in the abstract.
