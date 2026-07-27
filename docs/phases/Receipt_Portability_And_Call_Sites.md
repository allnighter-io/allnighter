# Receipt Portability and Call Sites — make the artifact survive leaving the machine

Status: **⚠ FOUNDER DECISION — proposal packet, no work authorized.** Phase
packet, not SSOT. Contains one request to narrowly reopen a cut decision
(TRR-S02 signing → *digest only*); do not build RP-S01 without a ruling.
Owner: Founder (strategy + rulings); AllnighterCore artifact path (execution)
Created: 2026-07-27
Origin: Buzz channel thread with founder, 2026-07-27 — reaction to public
claims that multiplayer agent harnesses are a winner-take-most layer.

Companions:

- Strategy why: `docs/strategy/Buzz_And_The_Judgment_Layer.md` (revised
  2026-07-25 — no ALLN agent identity; receipt is the wedge)
- Room test: `docs/phases/Buzz_Harness_Spike.md` (BZ-S00…S03; was deferred
  behind "receipt exists" — **that prerequisite is now met**)
- Closed design record: `docs/archive/phases/Team_Run_Receipt.md`
  (ARCHIVED 2026-07-26; **code is SSOT**)
- Code SSOT: `ArtifactProjector` / `ArtifactWriter` / `ArtifactCLI`
- Product layer language: `docs/strategy/Allnighter_Deploy_Teams_Wedge.md`
  ("Deploy a team. Get a move. Keep the receipt.")

## One-sentence version

The team artifact already exists and is beautiful on the machine that made it;
this packet asks whether it should be **portable and checkable off that
machine**, and proposes the cheapest pre-launch way to find out.

## The strategic claim (compressed)

Public argument in July 2026 is that multiplayer agent harnesses are a
winner-take-most layer and value accrues to whoever wins it. Both halves are
worth pushing on:

1. **Buzz's durable primitive is not chat.** It is a signed, addressable event
   log with portable identity; the chat window is one renderer over it. So a
   "the chat box is the wrong shape" critique does not sink it — the log
   outlives the UI.
2. **The network effect sits at identity and track record, not the client.**
   Keys are portable and relays are swappable, so nobody locks the log. What
   compounds is the record of *who did work and whether it held up*.
3. **That record does not exist yet, anywhere.** Dispatch exists (Buzz, Slack
   agents, any harness). Execution exists (every vendor CLI). Nothing answers
   *what actually ran, across which seats, and did the judgment hold*.
4. **Alln already produces exactly that object** and calls it the team
   artifact. It is the only part of this stack we own that a lab is unlikely
   to ship, because "judge our model against its rivals on the user's other
   subscriptions" is structurally not their product.

This does not argue for competing at the harness layer. It argues that alln
should be the **best supplier to whatever call site wins** — Buzz today, Slack
agents tomorrow, a plain terminal always. Same object, many rooms.

Consistent with existing law: the artifact's home stays local, share stays
deliberate, and nothing here requires alln to be a member of anyone's roster.

## Corrections to the originating conversation

Recorded so the thread's mistakes do not leak into the build:

| Claim made in-thread | Correction | Source |
| --- | --- | --- |
| "Ship an `alln acp` shim so ALLN is a first-class Buzz agent" | **Retired framing.** Buzz has humans and single-model agents; `alln` is a tool any of them can call. No membership needed. | `Buzz_And_The_Judgment_Layer.md` §2026-07-25 correction; `Buzz_Harness_Spike.md` §reframe |
| "Signed public permalinks; publish the receipt" | Signing and hosted share were **deliberately cut** — verification is `reproduceCommand`, attestation is an honesty string, public Nostr is never default. | `Team_Run_Receipt.md` §Growth reshaping |
| "Test share rate ≥15%, repeat invocation ≥30% inside Buzz" | **Invalid.** Alln has not launched and nobody can discover it in Buzz. Those are launch metrics, not pre-launch tests. | Founder, 2026-07-27 |
| "Publish the receipt (growth loop)" | The growth thesis is explicitly **not allowed to drive layout**, and its S00 scorecard disposition is still open. | `Team_Run_Receipt.md` §Two theses |

What survives all four corrections: **the object is the wedge, the room is a
test.** That is what this packet is scoped to.

## What actually shipped (verified 2026-07-27, `27599b2e`)

| Capability | State | Evidence |
| --- | --- | --- |
| `alln artifact show <run\|latest>` | Shipped | `ArtifactCLI.swift:41` |
| `alln artifact export <run\|latest> --out <path>` | Shipped | `ArtifactCLI.swift:7` |
| CSS inlined into the HTML | Shipped | `ArtifactProjector.swift:185` |
| Honesty string in footer + `--json` | Shipped — `alln-attested multi-seat artifact · not vendor-signed` | `ArtifactProjector.swift:12`, `ArtifactCLI.swift:83` |
| `reproduceCommand` replay line | Shipped | `ArtifactCLI.swift:30`, `TeamRunReplayCommand` |
| Raw prompt never dumped; `Asked` capped to 140 | Shipped | `ArtifactProjector.swift:53`, `:1129` |

## Gaps found (all three are pre-conditions for any room test)

1. **No content fingerprint.** The artifact says what the team decided, but
   nothing ties the rendered page to the run bytes. `reproduceCommand` tells
   you how to re-run; it does not tell you this page matches that run.
   CryptoKit SHA256 is already in the codebase, so this costs no new
   dependency (`DirectModePairingSessionStore.swift:257`).
2. **Export is single-file only for runs without mockups.** Design-team runs
   copy PNGs into a sibling `mockups/` directory next to the export
   (`ArtifactWriter.swift:71-79`, `:113-137`). Handing someone "the file"
   silently drops the images.
3. **No share preflight.** The only content limiter I found in the projector
   is the `Asked` cap; seat bodies and craft body render as authored. An
   export can therefore carry repo detail into a room without the user being
   told what is about to leave the machine. This is a **privacy-law** gap, not
   a growth feature.

## Slices

Deliberately ordered so the free test runs before any code.

**RP-S00 — Room legibility, zero engineering.** Execute `Buzz_Harness_Spike.md`
BZ-S00→S02 now that the prerequisite is met: in the existing Allnighter Buzz
channel, have an agent (or the founder) run a real alln team, then post the
verdict summary plus the exported artifact into the thread. Success is **how it
reads in the room**, not schema purity. Output: findings notes against the
spike's five questions. Cost: one session.

**RP-S01 — Portable proof line.** *(Requires founder ruling — see below.)*
Add a `sha256` digest over canonical `TeamRunJSON` to the artifact footer and
the `artifact show|export --json` payload. Explicitly **not** a signature: no
keys, no key management, no verify UI, and the word "certified" stays out of
the CLI. It makes the existing honesty string checkable instead of decorative,
and leaves the door open if signing ever returns.

**RP-S02 — Share-safe export.** `alln artifact export --for-share`: embed
mockups as data URIs so the export is genuinely one file, and print a preflight
listing what content is about to leave the machine. Default export behavior
unchanged. Closes gaps 2 and 3.

**RP-S03 — Second call site.** Repeat RP-S00 somewhere that is not Buzz — a
Slack agent that shells out to `alln`, or a plain terminal run whose export is
handed over as a file. Purpose: separate "the receipt is the value" from "Buzz
is the value." This is the spike's BZ-S03, kept because it is the single
cheapest way to falsify the whole thesis.

**RP-S04 — Pre-launch evidence ledger.** Local-only, founder-visible counts:
artifacts generated, opened, exported, handed to a second person, reopened by
that person. No telemetry service, no network calls — this is a file, not a
product surface. Purpose: the dogfood period should leave behind the numbers
that become launch metrics, rather than an anecdote.

## How to test this pre-launch (replaces the invalid metrics)

Alln has not launched; there is no population to measure. So the tests are
qualitative, small-n, and honest about it.

| # | Question | Method | Gate |
| --- | --- | --- | --- |
| 1 | Does the artifact survive the room? | RP-S00, this channel | Founder plus one outsider read it without needing it explained |
| 2 | Is the artifact load-bearing for its own author? | Passive observation over 7 days of normal use | Founder voluntarily reopens at least one past artifact without being prompted to |
| 3 | Does anyone reach for proof? | RP-S00/S03 observation | Any reader asks "is this real / can I check it" — if nobody ever asks, RP-S01 is theater |
| 4 | Is the value the object or the room? | RP-S03 | Handing the file over in a non-Buzz context feels ≥ as useful |
| 5 | Would a stranger care? | 3-5 outsiders shown one export cold | ≥2 say what it is and why it matters, unprompted |

Timebox: two weeks from ruling. n is small on purpose — the point is a
directional read before launch, not statistical confidence.

## Kill conditions

- **Test 2 fails** (founder never reopens an old artifact) → the object is not
  load-bearing; stop investing in portability entirely and go back to making
  runs better. This is the most important gate in the packet.
- **Test 1 fails** (readers need it explained) → legibility problem in the
  projector. Fix the artifact; do not build share.
- **Test 3 fails** (nobody ever asks whether it is real) → drop RP-S01. A
  fingerprint nobody wants is decoration.
- **Room reads as a bot dumping JSON** → spike outcome (b): Buzz stays dogfood
  only, keep investing in CLI + artifact.
- **First real pull is audit/compliance shaped** ("give me a log of what my
  agents touched") → that is a different company from the current ICP. Notice
  the fork and choose; do not straddle.

## Non-goals (inherited, restated so they are not re-litigated)

- No ALLN identity in anyone's agents grid; no per-seat keypairs; no "firm
  worked in public" theater.
- No federation, payments, or reputation graph. Reputation is a *possible
  consequence* of portable receipts existing; it is not a thing to build, and
  nothing in RP-S00…S04 assumes it.
- No public Nostr publish by default; no hosted link; no ACL system.
- No open-sourcing anything.
- No changes to `AllnighterCore` contracts, run grammar, or D5.
- No layout changes driven by virality; the growth thesis still does not own
  the frame.
- No standing `alln buzz` surface. Any bridge stays a deletable consumer.

## Founder decisions required

1. **RP-S01 digest — reopen or hold?** `Team_Run_Receipt.md` cut signing to
   delete the key-management slice. A digest needs no keys and no verify UI,
   so the original reason to cut does not apply — but it is adjacent enough
   that it should be an explicit ruling, not an assumption. Recommendation:
   authorize the digest, keep signing cut.
2. **RP-S00 first, or in parallel with S01/S02?** Recommendation: RP-S00
   alone. It costs one session and can kill the rest.
3. **Does the "call site, not membership" thesis get promoted?** If it holds
   after RP-S00/S03, it belongs in `docs/strategy/`, not here — phases never
   hold SSOT.

Nothing in this packet is authorized until (1) and (2) are ruled on.
