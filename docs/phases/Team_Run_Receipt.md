# Team Run Receipt — gorgeous private report, deliberate share

Status: **Draft feature packet — reshaped 2026-07-25 after Growth Min
(Cursor+K3).** Not started. Not a pivot; presentation of truth alln already
produces. Near-term scope is ~¼ of the first draft: a screenshot-native
**decision card** first; signing/hosted-link/Buzz slices cut or unscheduled.
Owner: AllnighterCore (receipt projector) + CLI first; Mac Factory Floor as
existing reader to reuse/project from.
Updated: 2026-07-25 (post Growth Min E900A4BC…)
Companions:
- Mac reader already exists: `FactoryFloorView` / `docs/phases/Live_Team_Board.md`
  (Factory Floor = full team result; thread keeps a compact receipt)
- Growth note: `docs/marketing/Growth_Playbook.md` §Shareable run receipts +
  §2 receipt series
- Adjacent Buzz spike (optional room test **after** card exists; firm/plural-
  member framing retired):  
  `docs/phases/Buzz_Harness_Spike.md` +  
  `docs/strategy/Buzz_And_The_Judgment_Layer.md`

## Founder intent (unchanged core)

CLI-first users finish a team run and never see the gorgeous multi-seat result
the Mac Factory Floor was built for. The judgment already happened; the
*poster* is missing.

Ship a **private-by-default team run report** every run can open locally,
styled once, reusable across teams. Sharing is deliberate — never an automatic
public URL. Do not require the Mac app to *view* a share (that kills the
share). Mac/CLI win on **running** the next team, not on being the PDF reader.

## Growth reshaping (locked from review)

Framing that can spread: **“Show the decision your AI team changed,”** not
“CLI parity with Factory Floor” and not “signed agent receipts.”

| Decision | Why |
| --- | --- |
| **Hero = screenshot-native decision card** | Timeline-native; image is the viral unit; OS screenshot is enough for v1 |
| **Verification = `reproduceCommand`, not cryptography** | Already on `TeamRunJSON`; “run this yourself” beats “trust my signature” for builders; deletes key-management slice |
| **Attestation = honesty string, not TRR-S02** | “alln-attested multi-seat receipt” as copy; no verify UI in v1 |
| **Pre-launch customer = founder’s receipt series** | Growth Playbook §2; user share loop inherits the same artifact later |
| **Measure before renderer (TRR-S00)** | If real runs lack disagreement / dodged-bullet stories, kill the growth thesis before a sprint |
| **Cut S02 / S04 / S05 as numbered slices** | Signing infra, hosted ACL links, Buzz/Slack — gravitational pull without near-term pull |
| **Defer file export (old S03)** | Build when an outsider asks for the file; founder screenshots locally until then |
| **Hero-optimize Spec Review + Growth cards first** | “One report family” stays as one projector; equal visual priority across every team kills the post |

## Product value (revised)

- **Felt finish for team runs.** Card at `alln team open` — recognition, not
  novelty (“this is what I’ve been screenshotting tmux for”).
- **Founder content engine now.** Hand-then-auto cards for the X receipt
  series; compounds before launch.
- **Later: user share without privacy foot-guns.** Deliberate only; private
  default; card is structurally lean (no full prompts/bodies above the fold).
- **Install path in the proof line.** Footer prints `reproduceCommand`.

Expected lift (revised): large on “this feels finished” **if** cards have a
story (disagreement / changed decision); **binary** on share/retention
depending on whether the artifact is timeline-native; ~zero on the judgment
engine. “Medium on retention/share” from the first draft was overstated.

## Trusted workflow slice (v1)

```text
alln run … completes
  -> Team Run Receipt card available locally (private; no network)
  -> CLI prints path / hints `alln team open <run-id>`
  -> card shows: question one-liner, seat chips + one-line verdicts + timings,
     team call / dodged bullet as headline, honesty string, reproduceCommand
  -> user screenshots with the OS (founder series; later anyone)
  -> (later, only if asked) deliberate file export or private hosted link
```

Full Factory Floor (cast rail, full seat bodies) remains the deep reader; the
card is the above-the-fold poster, not a replacement for the floor.

## Non-goals

- **Not DocuSign-for-agents / escrow / online agreements.**
- **Not “alln as a Buzz firm member / plural seat type.”**
- **Not public Nostr / public URLs by default.**
- **Not private auth relays in v1.**
- **Not requiring Mac app to view shares.**
- **Not auto-posting to X/Slack/Buzz.**
- **Not changing RunService / team grammar** beyond projecting existing
  `TeamRun` / `TeamRunJSON`.
- **Not claiming vendor cryptographic authorship.**
- **Not TRR-S02 crypto sign/verify UI in v1** (reproduce line + honesty string).
- **Not PDF.**
- **Not hosted ACL/expiry (old S04) or Buzz/Slack slice (old S05) until
  evidence demands them.**

## Current state

| Piece | Today |
| --- | --- |
| Multi-seat run truth | Built — `TeamRun` / `TeamRunJSON`, `alln team result` |
| `reproduceCommand` on runs | Built — print on the card |
| Seat timings / model ids | Built — card inputs |
| Gorgeous Mac Factory Floor | Built — deep reader |
| Screenshot-native decision card | **Missing** |
| CLI `team open` card path | **Missing** |
| Measured “do real runs have a story?” | **Missing — TRR-S00** |
| Signed crypto verify / hosted share | Deferred / cut for now |

## Privacy laws (still bind)

1. **Private by default.** Local disk. No public URL unless user explicitly
   Shares (and Share is not v1).
2. **Signing and visibility are orthogonal** — when/if signing returns, it
   still never implies public.
3. **v1 share mode:** OS screenshot of the local card (or copy path). File
   export / hosted link only later and deliberate.
4. **Honesty string on every card:** alln-attested multi-seat receipt — not
   “Claude cryptographically signed this.”
5. **Card content is lean by construction** — question, verdicts, timings,
   call — so casual screenshots don’t dump full prompts/seat bodies. Full
   bodies stay on Factory Floor / `team result`.

## Truth owner

- **Run truth:** existing `TeamRun` / `TeamRunJSON` (unchanged).
- **Card / receipt document:** deterministic projection from run truth. Must
  not invent seat text the run did not store.
- **Share/ACL (if ever):** explicit share store — never inferred.

## Lie-prone layers

- Pretty card that paraphrases seat output without marking truncation.
- “Verified” / “signed by Claude” copy.
- Auto-public links or relay publish on run complete.
- Mac-only open path that blocks CLI users from the card.
- Requiring Allnighter install to *read* an exported artifact (when export
  exists).

## Suggested slices (authorized shape; schedule separately)

| ID | Slice | Done when |
| --- | --- | --- |
| **TRR-S00** | Measure + hand-render | Pull last N multi-seat runs; count material disagreement / dodged bullets; hand-build ~3 cards from real JSON; post or show founder. **Kill or proceed gate.** |
| **TRR-S01** | Screenshot-native decision card + `alln team open` | Card from `TeamRunJSON`: question, seat chips, one-liners, timings, team call, honesty string, `reproduceCommand`. Gorgeous at early paint (seats from dry-run/`seats[]`, fill as answers land). ~2-day budget after S00 green. |
| **TRR-S03** | (later) File export | Only if an outsider asks for a portable file; browser-openable; still private-as-file. |
| ~~TRR-S02~~ | **Cut** — crypto sign/verify | Replaced by honesty string + reproduce line. |
| ~~TRR-S04~~ | **Unscheduled** — hosted private link | |
| ~~TRR-S05~~ | **Unscheduled** — Buzz/Slack post helper | One line under Relationship to Buzz is enough. |

## Works Test

**S00:** At least one hand-rendered card from a real run has a story a stranger
would ask “wait, what is that?” about — or explicit kill of the growth thesis
with evidence.

**S01:** CLI team run → `alln team open` shows the card without Mac app; OS
screenshot is postable; no public URL created; reproduce line present;
honesty string present.

**S03+:** waived until scheduled.

## Proof command

```text
alln team result <run-id> --json   # existing truth
alln team open <run-id>            # local decision card (S01)
```

## Done when (near-term)

- S00 gate passed or thesis explicitly killed with evidence.
- CLI-first users can open a private decision card for hero team runs
  (Spec Review + Growth first).
- Privacy default holds; no crypto-verify theater in v1.
- Factory Floor and card projector do not drift into two content truths.
- Buzz/Nostr/hosted link remain optional non-blockers.

## Open questions (surviving)

1. Exact CLI verb (`team open` vs `receipt open` vs `team report`).
2. Card HTML in run journal vs derived cache path.
3. Whether Mac Factory Floor embeds the same card above the fold or stays
   native with a shared projector.
4. ~~Key management~~ — **retired with S02.**
5. Redaction for **export** (when S03 exists); card itself stays lean.

## Relationship to Buzz

Buzz is **not** required. Optional later room to *show* a card/receipt in an
attended thread. Do not marry privacy or signing to a private auth relay. No
numbered Buzz slice until the card exists and S00/S01 earned it.

## Growth Min review (done)

| | |
| --- | --- |
| **When** | 2026-07-25 · wall ~6m37s · readOnly |
| **Run** | `E900A4BC-9D7A-41CE-93F0-37F5206FACEC` |
| **Team** | `custom_growth_min_cursor_k3` — Kimi K3, Cursor Grok 4.5, Opus 5 (Cursor), ChatGPT 5.6 Sol (Cursor); lead Fable 5 (Cursor) |
| **Pre-commit** | `08ff41d7` (pending marker) |
| **Post-commit** | this revision |

**Verdict (Fabel synthesis):** Packet is the right near-term bet at roughly a
quarter of written scope. Hero = screenshot-native decision card; verification
= `reproduceCommand` (cuts S02); pre-launch loop = founder receipt series;
**TRR-S00 measure-before-build** is mandatory — if cards have no story, kill
the growth thesis before the renderer sprint. §Non-goals was the strongest
section of the first draft; “medium on retention/share” was overstated.

**Worker sparks retained:** broadcast-vs-collaboration + compounding footer
stats (Kimi); above-the-fold hero-card discipline (Grok); reproduce-line +
disagreement-data gap + measure-before-build (Opus); “show the decision your
team changed” + S00 shape (Sol). Lead disagreed with all four on optimizing a
*user* share loop pre-launch — founder series first; export when someone asks.

## Spec Review Min (pending)

**Requested:** 2026-07-25 — bracket commits so the diff is this review’s input.

**Team:** `custom_spec_review_min_cursor_k3` (Spec Review Min · Cursor CLI seats
+ one Kimi K3 · Fabel lead). Read-only.

**Ask:** Harden `docs/phases/Team_Run_Receipt.md` as a buildable packet —
ambiguities, missing acceptance criteria, slice order risks, contradictions
with companions (Factory Floor / Live Team Board / Buzz spike), and what must
be true before TRR-S01 code starts. Pressure-test TRR-S00 kill gate vs product
value of a local card even when seats agree.

**Outcome:** fold the verdict into this section after the run; patch the packet
where the review sticks.
