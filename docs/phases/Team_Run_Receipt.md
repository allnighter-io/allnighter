# Team Run Receipt — gorgeous private report, deliberate share

Status: **Draft feature packet — not started.** Founder brainstorm locked
2026-07-25. Not a pivot; presentation + share of truth alln already produces.
Owner: AllnighterCore (receipt object) + CLI first; Mac Factory Floor as
existing reader to reuse/project from; hosting/Buzz optional later.
Updated: 2026-07-25
Companions:
- Mac reader already exists: `FactoryFloorView` / `docs/phases/Live_Team_Board.md`
  (Factory Floor = full team result; thread keeps a compact receipt)
- Growth note (aspirational): `docs/marketing/Growth_Playbook.md` §Shareable
  run receipts
- Adjacent Buzz spike (optional room test **after** this packet; firm/plural-
  member framing retired 2026-07-25):  
  `docs/phases/Buzz_Harness_Spike.md` +  
  `docs/strategy/Buzz_And_The_Judgment_Layer.md`

## Founder intent

CLI-first users (and anyone who never opens the Mac app) finish a team run and
never see the gorgeous multi-seat result the Mac Factory Floor was built for.
The judgment already happened; the *poster* is missing.

Ship a **signed, private-by-default team run report** every run can open locally,
styled once and reused for any team (Growth, Spec Review, etc.). Sharing is a
deliberate act — like sharing a Notion page — never an automatic public URL.
Do not require the Mac app to *view* a shared export (that kills the share).
The Mac/CLI win on **running** the next team, not on being the PDF reader.

## Product value

- **Felt finish for team runs.** Same smart run; finally visible, keepable,
  screenshotable.
- **CLI parity with Mac WOW.** Factory Floor content without trapping it in the
  Dock app.
- **Share loop without privacy foot-guns.** Deliberate export/link; private
  default.
- **One report family for every team.** Not a Growth-only special case.

Expected lift (founder brainstorm, not a promise): large on “this feels
finished” after a team run; medium on retention/share; ~zero on the judgment
engine itself. Presentation of an existing moat — not a new moat.

## Trusted workflow slice

```text
alln run … (any team) completes
  -> alln writes/updates a local Team Run Receipt (structured + gorgeous HTML)
  -> private by default (on disk; no network; no public URL)
  -> user opens: `alln team open <run-id>` / Mac Factory Floor / double-click export
  -> optional deliberate Share:
       (a) self-contained signed file (HTML/PDF) → browser, no app install
       (b) later: private hosted link (ACL / password / expiry)
       (c) later optional: drop same object into Buzz/Slack thread
  -> recipient views in a browser; CTA may invite install to *run* a team
```

## Non-goals

- **Not DocuSign-for-agents / escrow / online agreements.** File the far-out
  idea; do not build for it.
- **Not “alln as a Buzz firm member / plural seat type.”** Any agent or human
  may call alln; there is no ALLN agent identity required in Buzz’s UI.
- **Not public Nostr by default.** Signing ≠ public. Public publish is a later,
  explicit act if ever.
- **Not private auth relays in v1.** Too much infrastructure for the first
  slice.
- **Not requiring Mac app to view shares.** Browser-openable export wins.
- **Not auto-posting receipts to X/Slack/Buzz.**
- **Not changing RunService / team grammar / Core contracts** beyond a receipt
  projection of existing `TeamRun` / `TeamRunJSON` truth.
- **Not claiming vendor cryptographic authorship.** alln attests “these seats
  produced this text under this run”; Anthropic/OpenAI keys do not sign.

## Current state

| Piece | Today |
| --- | --- |
| Multi-seat run truth | Built — `TeamRun` / `TeamRunJSON`, `alln team result` |
| Gorgeous Mac reader | Built — Factory Floor (`FactoryFloorView`) |
| Compact thread receipt | Spec’d — `Live_Team_Board.md` |
| CLI-visible WOW report | Missing — JSON/text only for CLI-first users |
| Signed local receipt object | Missing |
| Deliberate share / private hosted link | Missing (Growth Playbook named it; unbuilt) |
| Buzz as distribution | Spike only — adapter not a product commitment |

## Privacy and signing (laws for this packet)

1. **Private by default.** Local disk. No public URL created unless the user
   explicitly Shares.
2. **Signing and visibility are orthogonal.** A receipt may be signed and never
   published; published only to a private audience; or (later) published widely.
3. **Share modes, in order of preference for v1:**
   - Local open (no share)
   - Signed self-contained **file** (email / DM / AirDrop) — private = who has
     the file; viewer = any browser
   - Optional hosted private link (deliberate) — Notion rules (ACL, revoke,
     expiry)
4. **Buzz / Slack** may display the same object later; they are surfaces, not
   the privacy system and not required for signing.
5. **Honesty string on every shared artifact:** alln-attested multi-seat
   receipt — not “Claude cryptographically signed this.”

## Truth owner

- **Run truth:** existing `TeamRun` / `TeamRunJSON` (unchanged owner).
- **Receipt document:** new projection — deterministic render from run truth
  (HTML + signature metadata). Must not invent seat text the run did not store.
- **Share / ACL state (if hosted later):** explicit share store; never inferred
  from “we uploaded once.”

## Lie-prone layers

- Pretty HTML that paraphrases or truncates seat output without marking
  truncation.
- “Verified” / “signed by Claude” copy when the signer is alln’s key.
- Auto-public links, relay publish, or Buzz post on run complete.
- Mac-only open path that blocks CLI users from the WOW report.
- Requiring Allnighter install to *read* an exported receipt.

## New / changed semantic rules

- Every terminal team run may materialize a **Team Run Receipt** (local).
- Receipt schema includes: run id, team identity, seat list, per-seat outputs
  (or content hashes + full bodies), synthesis/verdict when present, timestamps,
  alln signature over a canonical serialization.
- `alln team open <run-id>` (name TBD at implement) opens the local gorgeous
  report.
- `alln team share` / export (name TBD) is the only path that creates a
  portable artifact or link; default remains private.
- No new public product surface that publishes on run completion.

## Duplicate truth to delete

None yet. When HTML templates land, do not fork a second “results” content
model beside Factory Floor projectors — reuse or share the projection.

## Implementation impact

| Surface | Impact |
| --- | --- |
| AllnighterCore / Engine | Receipt projector + sign/verify helpers; optional on-disk artifact beside run journal |
| CLI | `team open` / export-share commands; print local path (and later share URL only after deliberate share) |
| Mac app | Factory Floor remains the in-app reader; may open the same receipt HTML or keep native view fed by the same projector |
| iOS | Out of scope for v1 (parked with iOS) |
| Drivers / protocol | None |
| Auth / privacy | Local keys for signing; no vendor API keys; no default network publish |
| Buzz | Optional later consumer of the same receipt object — not in v1 critical path |

## Suggested slices (not authorized until scheduled)

| ID | Slice | Done when |
| --- | --- | --- |
| TRR-S01 | Local gorgeous HTML receipt from existing `TeamRunJSON` | `alln team open` shows browser/report for a completed Growth or Spec Review run |
| TRR-S02 | alln signature + offline verify affordance on the page | Tamper flips verify to fail; honest attestation copy |
| TRR-S03 | Deliberate file export (shareable, still private-as-file) | Export opens in Safari/Chrome with no Allnighter installed |
| TRR-S04 | (later) Private hosted link + revoke | Notion-like share; never default-on |
| TRR-S05 | (later, optional) Post receipt into Buzz/Slack thread | Same object; no firm-member mythology |

## Works Test

1. Run any built-in team from CLI to completion.
2. Open the local receipt without launching the Mac app results UI as the only
   path — report is gorgeous enough to screenshot.
3. Confirm no public URL / relay publish happened.
4. Export a signed file; open on a machine without Allnighter; content matches
   seats; verify passes; after byte flip, verify fails.
5. (Waiver OK for S01–S02) Hosted link and Buzz/Slack out of Works Test until
   those slices are scheduled.

## Proof command

```text
# shape TBD at implement — illustrative
alln team result <run-id> --json   # existing truth
alln team open <run-id>            # local receipt
# export + verify once commands exist
```

## Done when

- CLI-first users can open a private gorgeous team report for any team run.
- Share is deliberate; privacy default holds under review.
- Signing claims are honest (alln attestation).
- Mac Factory Floor and the receipt projector do not drift into two content
  truths.
- Buzz/Nostr/hosted link remain optional — not blockers for v1.

## Open questions

1. Exact CLI verb names (`team open` vs `receipt open` vs `team report`).
2. HTML in run journal vs derived cache path.
3. Whether Mac Factory Floor switches to the HTML receipt or stays native with
   a shared projector.
4. Key management for signatures (per-user alln key vs per-machine) — decide
   in S02, keep boring.
5. Redaction controls on share (strip prompts? strip full seat bodies?).

## Relationship to Buzz

Buzz is **not** required for this packet. It remains a useful optional place to
*show* a receipt inside an attended human/agent thread. Do not marry privacy or
signing to a private auth relay. If Buzz (or Slack) agents call `alln`, they
consume the same CLI → same receipt object.

## Growth Min review (pending)

**Requested:** 2026-07-25 — before/after git commits bracket this review so the
diff is the team's input only.

**Team:** `custom_growth_min_cursor_k3` (Growth Min · Cursor CLI seats + one
Kimi K3 · Fabel lead). Read-only.

**Ask:** Review this packet (`docs/phases/Team_Run_Receipt.md`) with Growth:
the loved wedge, the shareable artifact, the simplest lovable version, what to
cut, and whether private-by-default + deliberate share + CLI-openable gorgeous
report is the right near-term bet (vs Buzz marriage, public Nostr, Mac-only
viewer, etc.).

**Outcome:** fold the verdict into this section after the run completes.
