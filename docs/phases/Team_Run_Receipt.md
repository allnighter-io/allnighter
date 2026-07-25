# Team Run Receipt — gorgeous private report, deliberate share

Status: **Ready for Implementation — TRR-S01.** Primary job = scannable,
readable polished team **artifact** (like a great AI chat response, with
phosphor status). Not a viral poster. S00b locked 2026-07-25 (`artifact`
verb). TRR-S00 remains optional (growth packaging only).
Owner: AllnighterCore (artifact projector) + CLI first; Mac Factory Floor as
existing deep reader (not the artifact owner).
Updated: 2026-07-25 (S00b closed — implementation ready)
Companions:
- Mac deep reader: `FactoryFloorView` / `docs/phases/Live_Team_Board.md`
  (Factory Floor = full team result; thread keeps a compact cockpit receipt →
  Open Floor; **team artifact is a third surface** — see §Surface ownership)
- **Lead Call** (universal Lead / `.planWriter` envelope + `lead-call` fenced
  JSON — call / leans / status): `SkillCatalog.leadCallEnvelope`;
  Spec Review closeout: `docs/phases/Spec_Review.md` §1
- Design authority: `docs/design-system/production.md` +
  `docs/design-system/tokens/*.css` + `docs/gui/GUI_Workflow.md`
- Growth note (optional later series — **not** the layout driver):
  `docs/marketing/Growth_Playbook.md` §Shareable run receipts
- Adjacent Buzz spike (optional room test **after** artifact exists):  
  `docs/phases/Buzz_Harness_Spike.md` +  
  `docs/strategy/Buzz_And_The_Judgment_Layer.md`
- Disagreement fields (NOT AUTHORIZED): `Contradiction_Pass.md`
- Future attestation stamp (not v1): signed/certified artifact — same noun,
  property later; do not put “certified” in the CLI verb until signing ships

## Founder intent

CLI-first users finish a team run and get JSON/terminal walls — or never open
the Mac Factory Floor. The judgment happened; the **readable finish** is
missing.

Ship a **private-by-default HTML team artifact** you open locally after a run:
scannable hierarchy, phosphor seat status, Lead Call up top, craft body below —
the same job as polishing a long chat answer so a human can actually use it.
Sharing is deliberate and rare; **do not design the layout primarily for
virality.** Mac/CLI win on running the next team; the artifact wins on
**reading this one**. CLI noun (locked): **`artifact`**.

## Growth reshaping (locked — keep product vs growth split)

| Decision | Why |
| --- | --- |
| **Hero = polished scannable receipt** | Everyday job: read the team result fast and honestly — like a great chat response |
| **Verification = `reproduceCommand`, not cryptography** | Already on `TeamRunJSON`; deletes key-management slice |
| **Attestation = honesty string, not TRR-S02** | Copy only; no verify UI in v1 |
| **Viral / X series = optional secondary** | ~90% of opens are private reading; founder series may use the same artifact later — it must not drive frame, truncation, or Works Tests |
| **Measure before renderer (TRR-S00)** | May kill **growth packaging**; never the readable-finish product path (§Two theses) |
| **Cut S02 / S04 / S05 as numbered slices** | Signing / hosted / Buzz — not needed for v1 reading |
| **Defer branded export (old S03)** | md export already ships; styled export when asked |
| **One projector, all teams** | Spec Review Max, tiny feature, Design three-up — same family; content-intrinsic height |

## Two theses (do not conflate)

| Thesis | Claim | Kill condition |
| --- | --- | --- |
| **Growth** | Occasional shareable screenshots drive awareness | S00 finds no stranger-worthy stories → kill **series ambition**, keep measuring later |
| **Product** | After every team run, CLI users deserve a polished, scannable local receipt | Only kill if the receipt is worse to read than `team result` / Floor |

**Ruling:** Product thesis owns layout and S01. Growth thesis may borrow the
artifact; it does not set aspect ratio, truncation, or “must fit a timeline.”

## Product value

- **Felt finish / scanability.** Open the receipt and grasp Ready|Partial, the
  call, seats, and the body without decoding JSON or hunting the Mac app.
- **Same polish bar as good chat UI.** Hierarchy, density, status color,
  readable markdown — not a marketing poster.
- **Desktop-first reading, mobile-capable.** Must look **excellent on a big
  desktop** (where most alln users will open it) and still scan cleanly on a
  phone. Comfortable measure — not stretched edge-to-edge wallpaper, not a
  mobile-only column that wastes a 27″ display.
- **Optional deliberate share later.** Private by default; share is not the
  design center.
- **Replay path in the footer.** `reproduceCommand` (elided) when useful —
  proof for skeptics, not an install funnel.

Expected lift: large on “I can actually read what the team did”; growth/
retention from sharing is **optional upside**, not the success metric.

## Surface ownership (resolves Floor / thread collision)

Three surfaces; one run truth. Do not call all three “the receipt” in teaching
copy without a qualifier.

| Surface | Owns | Does not own |
| --- | --- | --- |
| **Run truth** | `TeamRun` / `TeamRunJSON` | Presentation |
| **Factory Floor** (`FactoryFloorView`, `alln floor show`) | Full inspectable result — cast rail, full seat bodies, synthesis | Everyday polished reading surface |
| **Thread compact card** (Live Team Board terminal) | Live cockpit + counts + **Open Floor** | Full bodies; receipt layout |
| **Team artifact** (this packet) | Scannable polished read of Lead Call + seats + craft body | New run facts; Floor replacement; viral-first layout |
| **`alln team result`** | Terminal structured truth dump | Gorgeous reading UI |
| **`alln export <id> --format md`** | Shipped portable markdown | Branded/styled receipt export (old S03) |
| **`alln spec …` summary paths** | Spec-oriented projections where they exist | Receipt layout |

Companions stay authoritative: Live_Team_Board §Done When — terminal thread
keeps compact receipt → Floor. This packet adds a **CLI-first reading
surface**, not a second Floor and not a marketing poster.
## Trusted workflow slice (v1 — terminal only)

```text
alln run … completes (terminal TeamRunJSON exists)
  -> Artifact projector derives fields from TeamRunJSON + lead-call
  -> `alln artifact show <run-id|latest>` writes/opens local HTML (private)
  -> user reads: Ready|Partial, the call, seats in status color, craft body
  -> optional: OS screenshot or export only if they choose to share
```

**Out of v1:** progressive “gorgeous at early paint” while seats fill — that
needs live events and is a separate slice (deferred). Dry-run `seats[]` is not
on `TeamRunJSON`; do not invent a live card from dry-run alone.

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
- **Not auto-detecting “dodged bullet” / disagreement as card schema fields**
  unless a sourced contract field exists — S00 may *annotate* hand cards;
  S01 must not paraphrase theater.
- **Not replacing `alln floor show` / Factory Floor** with the decision receipt.
- **Not Mac Floor above-the-fold embed in the first code slice.**
- **Not designing primarily for virality / timeline crops.** Scanability and
  readability own the layout; share is a deliberate afterthought.

## Current state

| Piece | Today |
| --- | --- |
| Multi-seat run truth | Built — `TeamRun` / `TeamRunJSON`, `alln team result` |
| `reproduceCommand` on runs | Built — `teamRun.reproduceCommand` |
| Seat timings / model ids | Built — `workers[]` + `workerAnswers[]` |
| Gorgeous Mac Factory Floor | Built — deep reader (`FactoryFloorView`) |
| Inspectable Floor CLI | Built — `alln floor show` (different surface) |
| Polished team artifact HTML | **Missing — TRR-S01** |
| CLI `artifact show` | **Missing — TRR-S01** |
| Field ownership ledger for card | **Missing until §Card field ledger sticks** |
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
5. **Card content is lean by construction** — question, one-liners, timings,
   call — so casual screenshots don’t dump full prompts/seat bodies. Full
   bodies stay on Factory Floor / `team result` / `floor show`.
6. **Reproduce-line elision.** `reproduceCommand` embeds the full prompt
   verbatim — printing it raw in the footer can violate lean-card privacy on
   every screenshot. Elide past N chars with a marked ellipsis, or show an
   id-based replay pointer (`alln run … --run-id …` shape TBD in S00b). Hard
   cap the **question line** separately; when `promptSource` is file/stdin or
   bodies were inlined via `@`, never dump the file into the card.
## Truth owner

- **Run truth:** existing `TeamRun` / `TeamRunJSON` (unchanged).
- **Card / receipt document:** deterministic projection from run truth. Must
  not invent seat text the run did not store. Truncation must be marked.
- **Share/ACL (if ever):** explicit share store — never inferred.
- **Not owners:** SwiftUI, prompt prose, hand-edited HTML without regenerating
  from the projector.

## Lie-prone layers

- Pretty card that paraphrases seat output without marking truncation.
- “Verified” / “signed by Claude” copy.
- Auto-public links or relay publish on run complete.
- Mac-only open path that blocks CLI users from the card.
- Requiring Allnighter install to *read* an exported artifact (when export
  exists).
- Calling `outcome.headline` a “team call” — it is mechanical timing/status,
  never a correctness or judgment claim (`TeamRunJSON.Outcome` docs).
- Teaching `team open` / “receipt” as if it were `floor show`.

## Card field ledger (must stick before S01 code)

Every card field needs a `TeamRunJSON` (or constant) owner. No owner → not on
the card in S01.

| Card field | Owner | Rule |
| --- | --- | --- |
| Question line | `teamRun.prompt` | Hard cap + mark; file/stdin/`@` bodies never inlined; do not LLM-summarize in v1 |
| Team label | `teamRun.teamDisplayName` / `teamPresetId` | No inference from prompt |
| Seat set (who gets a chip) | `workers[]` filtered by purpose `answer\|plan\|review`; lead included; disambiguate `instanceIndex` | **Share helper with `FloorProjector`**; anti-drift test required so Floor and card never disagree on who was on the team |
| Seat chip identity | `workers[].modelName` (+ `sourceId` glyph if present) | Stable worker id for join |
| Seat status | `workerAnswers[].status` | Closed enum only |
| Seat timing | `workerAnswers[].durationMs` (optional queue/ttft) | Null → blank, never estimate |
| Seat one-liner | First non-empty line of `workerAnswers[].markdown`, hard-truncated + `…` | **Never** invent a “verdict” label. **Single-seat Law 2:** when the winning seat’s markdown is hoisted into `answer` and nulled on the worker row, the chip must read from `answer.markdown`, not show blank |
| Team call / headline | Prefer fenced `lead-call` JSON `call` when present; else first ~2 lines of `answer.markdown` | **Not** `outcome.headline`. Lead Call envelope is the contract owner for the call (`SkillCatalog.leadCallEnvelope`). Law-2: no dead `plan.markdown` fallback |
| Status chip | `lead-call.status` Ready\|Partial | Omit if block absent |
| Recommendation bullets | Top leans from `lead-call.recommendations` (cap display at 3) | Must be substrings of Lead markdown |
| Bang / changed | `lead-call.changed` and/or declared `flags` (not inferred disagreement) | No auto drama without a declared Lead field; `Contradiction_Pass` still unauthorized |
| Dodged bullet / disagreement bang | **S00 annotation only** unless present in `lead-call` | Do not ship heuristic “we disagreed” chrome |
| Honesty string | Constant copy | Exact string locked in S01 Works Test |
| Reproduce line | `teamRun.reproduceCommand` | Apply §Privacy law 6 elision; blank/omit marked if null — do not invent. **Not** authored by the Lead (Lead owns Proof of the call only) |
| Run id | `teamRun.id` | Footer micro-type OK |

**Hero chrome keying:** prefer `teamRun.outputKind` (and lane) over an exact
`teamPresetId` allowlist — custom presets (e.g. `custom_growth_min_cursor_k3`)
must still get hero treatment. Verify during S00b that `teams duplicate`
preserves `outputKind`. One projector family; optional presentation hints —
not two content truths.

**v1 hero-field policy (Decision 2A):** marked mechanical truncation for all
teams. Typed per-seat verdict / decision-delta fields are a **v2** path gated
on a real contract slice — not S01. LLM-summarized one-liners are rejected
(violates truth-owner law).
## Suggested slices (authorized shape; schedule separately)

| ID | Slice | Done when |
| --- | --- | --- |
| **TRR-S00** | Measure + hand-render (**optional**, growth only) | Fixed N (~20) multi-seat hero runs; rubric (a)(b)(c); hand-build ~3 artifacts. Does **not** block S01. |
| **TRR-S00b** | Lock open specs (doc-only) | **DONE 2026-07-25** — §Must-specify closed; verb = `artifact`. |
| **TRR-S01** | Terminal artifact + CLI | Projector + `alln artifact show`; fields per ledger; substring truth test + negative fixtures with projector; visual proof desktop+mobile; private; reproduce elision + honesty. **No early-paint / live fill.** |
| **TRR-S01b** | (later) Mac Floor optional embed | Same projector linked from Floor — after S01 CLI WOW. |
| **TRR-S01c** | (later) Progressive paint | Live/status contract; not S01. |
| **TRR-S03** | (later) Branded/styled export | md export already ships; branded HTML export on demand. |
| ~~TRR-S02~~ | **Cut** — crypto sign/verify | Honesty string + reproduce; “certified” is a future property, not v1 verb. |
| ~~TRR-S04~~ / ~~S05~~ | **Unscheduled** | Hosted link / Buzz helper |

### Slice-order risks (named)

1. ~~S01 before S00b~~ — **cleared.**
2. **S01 bundles live paint** → couples to Live Team Board streaming gaps.
3. **Mac embed in S01** → GUI drag before CLI Works Test.
4. **Growth kill misread as product kill** → orphan CLI finish forever.
5. **Teaching drift** — must distinguish `artifact show` vs `floor show` vs
   `team result` vs `export` vs `continuity receipt`.

## Blockers before TRR-S01 code

1. ~~TRR-S00~~ — **not a product blocker** (growth optional).
2. ~~TRR-S00b~~ — **closed** (this revision).
3. ~~Must-specify blanks~~ — **closed.**
4. ContractRegistry entry + `contractVersion` bump + `docs/generated/alln/*`
   regen — **expected in S01**, budgeted (not a doc blocker).
5. Teaching topic + help search terms — **land in same S01 PR** (Feature
   Workflow teaching-surface rule).
6. No new *run* schema — projection only; new CLI verb is the contract slice.
7. Design authority + proof route — **named** (§Design authority / §Proof).
8. Run-status precondition — **locked** below (`RUN_NOT_TERMINAL`).

**No remaining founder decisions block S01.** Implementer locks below are law.

## Must-specify (S00b — LOCKED)

| Item | Lock |
| --- | --- |
| CLI verb | **`alln artifact show <run-id\|latest>`** — prints path; opens default browser unless `--no-open`. Strike `receipt show` (collides with `continuity receipt`). Strike `card show` as product noun. |
| Render medium | HTML reading doc; content-intrinsic; desktop + mobile (G8); G1–G13 |
| On-disk path | Under the run journal dir: `artifact/index.html` (+ optional `artifact/lead-call.json` mirror). Private, deterministic, **regenerable** from `TeamRunJSON` / Lead markdown (never hand-edit as truth). |
| Seat one-liner | First line of `workerAnswers[].markdown`, hard-truncate **120** chars + `…`; Law-2 single-seat hoist from `answer.markdown` |
| Team call | Prefer `lead-call.call`; else first **2** lines of `answer.markdown`; else `"(no synthesized output — status …)"` |
| Honesty string | Exact: **`alln-attested multi-seat artifact · not vendor-signed`** |
| Hero keying | `teamRun.outputKind` (+ lane). Verify `teams duplicate` preserves `outputKind` in S01 tests. |
| Seat-set rule | `workers[]` declaration order; include purposes `answer\|plan\|review` and lead; disambiguate `instanceIndex`. **Share helper with `FloorProjector`**; anti-drift unit test required. |
| Prompt cap | Question line **120** chars + marked `…`; never inline file/stdin/`@` bodies |
| Reproduce elision | Footer: if `reproduceCommand` length **> 96** chars, show first 96 + `…` and the run id on the next micro-line. Never invent a command. |
| Run-status errors | Non-terminal (running/cancelled/parked/missing) → fail closed, error code **`RUN_NOT_TERMINAL`** (prior art), non-zero exit. Failed/timedOut/done terminal runs still show (failed seats visible). |
| ContractRegistry | New command `artifact.show`; flags: run id / `latest`, `--no-open`, `--json` (path + metadata only in v1). Bump `contractVersion` off pinned `4.0.2`; regen generated docs; help topic `artifact` + search hits for report/card/receipt synonyms → this command. |
| Non-hero teams | Same projector, simpler chrome |
| Mac Floor embed | Deferred S01b |
| Design-system compact chip | Add `WorkerChip` compact (+ dot pill) in design tokens/components **before or with** S01 — no one-off projector CSS |
| Visual proof | S01: layout-watcher at desktop ≥1280 and mobile ≤430 + G13; HTML gate extension **or** recorded waiver in `WAIVERS.manifest` — implementer picks cheaper path that still proves both viewports |

## Design authority

This packet’s entire product value is visual. Route card styling — including
TRR-S00 hand-renders — through `docs/design-system/production.md` and
`docs/design-system/readme.md`. The HTML card **consumes
`docs/design-system/tokens/*.css` as source** (CSS tokens canonical; Swift
mirrors). GUI engineering: `docs/gui/GUI_Workflow.md`. No new token or
component variant may originate in the projector — it lands in `tokens/*.css`
/ `components/product/` first (`production.md` §1).

**Inspiration (borrowed, not copied):** OpenAI × Work Louder Agent Keys —
“Your agents, in color” / ambient state before opening the chat. Steal
**glance-first state** and **“needs you” as a first-class state**. Reject
rainbow RGB, per-vendor hues, hardware fetish, glow-on-settled-poster, and
any sixth status color.

### Visual grammar (locked) — Opus 5 design taste 2026-07-25

**G1 — Two axes, two components.** Seat status
(`queued|running|done|failed|timed_out`) renders via `StatusPill` / dot inside
`WorkerChip` (`production.md` §3, §5). Card verdict (`Ready|Partial` from
`lead-call`) is **not** a seat status and **never** a `StatusPill`. A run may
be Ready with a failed seat.

**G2 — One amber content event per card.** Priority: Partial verdict >
lead-call rule. Footer crescent (the mark) is exempt. **Never** amber on a
seat chip. Amber points at the thing you are supposed to do.

**G3 — Verdict grammar (card level).**

| Verdict | Treatment |
| --- | --- |
| `Ready` | Word “Ready” in `--text-primary`, `--border-default` hairline, **no fill, no hue** |
| `Partial` | Words “Partial · needs you”, `--accent-surface` / `--accent-border` / `--accent-text` |
| no `lead-call` block | Omit the lockup — **never default to Ready** |

Presence/absence of warm is the 1-bit glance read. The word is always present —
color never carries meaning alone.

**G4 — Seat chip grammar (one component, two modes).** Bind `production.md` §3:

| Seat status | Live board | Settled card |
| --- | --- | --- |
| `queued` | `--status-queued` | rare on terminal; render as-is, never recolor |
| `running` | `--status-running` (+ blink); see G6 for glow | **illegal** on card (`RUN_NOT_TERMINAL`) |
| `done` | `--status-done` | `--status-done`, no motion |
| `failed` | `--status-failed` | `--status-failed` — **must survive crop** |
| `timed_out` | `--status-timeout` | `--status-timeout` |

Chip zones fixed-width: `[glyph] [name + one-liner] [status dot + duration]`.
Duration mono muted; null → blank, never estimated. Add
`WorkerChip size="compact"` (+ dot-only pill) to the design system **before**
S01 invents a one-off.

**G5 — Glow is the live/settled bit.** Live board may glow; **the receipt
carries zero glow and zero animation.** Same chips; one bit of difference.
Motion does not help a static reading document.

**G6 — Amber alive glow is singular per live surface.** Exactly one mutating
worker → glow on that worker; parallel research → glow on the board’s live
mark, **not** every running chip (no amber wallpaper).

**G7 — Vendor identity is monochrome.** Glyph → `--ink-100`; model id mono
faint. **Glyph says who; color says state.** Never both. No Anthropic/OpenAI
brand hues (collides with phosphor amber).

**G8 — Content-intrinsic report; desktop + mobile.** The receipt **grows with
the run** — Spec Review Max, a tiny feature harden, a Design board with three
proposals. Fixed 16:9 / viral-poster framing is **retired**. Rules:

- Primary artifact = **scrollable HTML reading document** on midnight field.
  Zones expand with content; marked ellipsis only where the field ledger
  already hard-caps (question line, seat one-liner).
- **Desktop is first-class.** On a large display the receipt must look
  *excellent*: comfortable max measure (chat/doc column, not full-bleed
  stretch), generous but disciplined type/spacing, seats and craft body that
  use the width without sparse emptiness or 100vw wallpaper. Most alln users
  will open this on a Mac display — that is the primary Works Test viewport.
- **Mobile must still scan cleanly.** Single column, readable tap targets,
  seats that wrap honestly, no horizontal overflow. Nice on a phone is required;
  **perfect on a big desktop is required too** — not “mobile-first, desktop
  afterthought.”
- Craft bodies that need space get space. Do not truncate craft truth to fit
  a frame or a feed.

**G9 — Scan ladder (order is load-bearing; height is not).** Top of document:
Verdict + team line → the call → what changed → recommendations → seat chips →
craft body → footer. Reader who opened the receipt gets the whole run; do not
hide long Spec Review / Design content below an artificial fold for virality.

**G10 — Sentiment is not status.** “What changed” and leans are **ink only** —
no red/green delta drama. Status hues reserved for status.

**G11 — Deterministic seat order.** `workers[]` declaration order — identical
to live board / `FloorProjector` seat-set helper. Never sort by finish time.
Lead distinguished structurally (label + border), not by amber fill.

**G12 — Surface.** Solid `--bg-base` field, body `--bg-raised`, `--radius-lg`,
`--border-subtle`, `--shadow-sm`. No gradient wash. No light-mode variant. No
emoji. Static render.

**G13 — Enforceable check (ship with projector).** Fail the gate if the
rendered receipt contains `animation:` / `@keyframes` / `--glow-*`, any hex
literal outside the token layer, or more than one amber content event in the
header lockup. Deterministic — not agent judgment. **Do not** fail on document
height. **Do** proof at **≥2 viewports**: wide desktop (≥1280px) and narrow
mobile (≤430px).

### Scanability Works Test (visual bar)

Grade as a **reading document**, not a feed thumbnail:

1. **Desktop (≥1280px):** open a Spec Review–length and a Design three-proposal
   fixture — hierarchy is obvious, measure is comfortable, no sparse stretch,
   seats + body use the layout well.
2. **Mobile (≤430px):** same fixtures — no horizontal scroll, call still
   dominant, seats wrap cleanly, Partial “needs you” still unmistakable.
3. Warm present/absent (Partial) readable before deep reading.
4. Failed seats stay visibly failed.
5. Mark present; footer proof stays quiet micro-type.

## Proof design

- **Substring truth test:** after render, every non-allowlisted visible string
  on the card is a substring of source `TeamRunJSON` / Lead markdown
  (mechanizes §Truth owner).
- **Negative fixtures:** failed seat; single-seat Law-2 hoist; no-answer
  partial; null timings; hostile 8KB prompt / `</div><script>` HTML escape;
  duplicate model ids; `designBoard` seat markdown with image paths (never
  print a file path as a verdict).
- **Run-status precondition:** non-terminal invocations fail closed with a
  named error code.
- **Visual proof:** `scripts/check_gui_proof.sh` today scopes Mac SwiftUI —
  an HTML card from Core is invisible to that wall. Extend the gate to the
  card artifact **or** record a waiver in `docs/qa/gui/WAIVERS.manifest` and
  name a `layout-watcher` PASS at **desktop ≥1280px and mobile ≤430px** (and at
  least one long-body fixture: Spec Review Max–shaped or Design three-proposal)
  before first ship — plus G13. Do **not** require a fixed 16:9 of the document.
- **Named blocked proofs (honest):** growth lift unfalsifiable pre-launch;
  “gorgeous” has no automated oracle; no CI end-to-end multi-seat run
  (Keychain/sandbox); screenshot fidelity across OS versions.

## Works Test

**S00:** Optional growth gate — Fixed-N story counts + hand-renders; does not
block S01.

**S00b:** **DONE** — Must-specify locked; verb = `artifact`.

**S01:** Terminal CLI team run → `alln artifact show` opens the artifact
without Mac app; private; reproduce elided; honesty exact; ledger/substring
honesty; truncation marked; failed seats visible; **desktop + mobile
scanability** passes; **G13** checks pass. Long bodies allowed.

**S01b+ / S03+:** waived until scheduled.

## Proof command

```text
alln team result <run-id> --json   # existing truth
alln floor show <run-id>           # existing deep Floor (not the artifact)
alln artifact show <run-id>        # team artifact (S01)
alln artifact show latest --no-open
```

## Done when (near-term)

- ~~S00b~~ — **done.**
- CLI-first users can open a private team artifact for any terminal team run.
- Privacy default holds; reproduce elision holds; no crypto-verify theater.
- Factory Floor, thread compact card, and team artifact share one projector
  family over `TeamRunJSON` + shared seat-set helper.
- Teaching distinguishes artifact vs floor vs team result vs export.
- Buzz/Nostr/hosted / “certified” remain optional non-blockers.

## Open questions

**None blocking S01.** Optional later: TRR-S00 growth measure; S01b Floor
embed; certified/signed property; branded export.

## Relationship to Buzz

Buzz is **not** required. Optional later room to *show* a card/receipt in an
attended thread. Do not marry privacy or signing to a private auth relay. No
numbered Buzz slice until the card exists and S00/S01 earned it.

## Impact ledger (Spec Review 2026-07-25)

### Keep

- Hero = screenshot-native decision card (§Growth reshaping).
- Verification = `reproduceCommand`; cut crypto S02.
- Private by default; OS screenshot as v1 share.
- S00 measure-before-renderer for **growth**.
- Cut/unschedule S02 / S04 / S05; defer S03 until asked.
- One projector family; hero-optimize Spec Review + Growth visuals first.
- Non-goals: no Buzz marriage, no RunService grammar change, no PDF.
- Buzz spike deferred behind card (`Buzz_Harness_Spike.md`).

### Change

- **S00 kill scope** → growth thesis / series priority only; not the product
  card when seats agree (§Two theses). Rubric also counts consensus-with-a-call
  and lead-vs-seat reversals — not disagreement-only.
- **S01 shrink** → terminal-only; drop early-paint / dry-run `seats[]` fill
  from S01 (§Trusted workflow; TRR-S01c deferred).
- **Add TRR-S00b** → close Must-specify + ContractRegistry draft before any
  renderer code.
- **Surface ownership** → name Floor / thread / decision card / export /
  `team result` as distinct surfaces (`Live_Team_Board.md` §Done When).
- **CLI verb lean** → `card show`; **reject `receipt show`** (collides with
  `alln continuity receipt`).
- **Team call** → `answer.markdown` only; no `outcome.headline`; no dead
  `plan.markdown` fallback (Law 2).
- **Hero keying** → `outputKind`, not exact preset-id allowlist.
- **Reproduce line** → elision rule (Privacy law 6); “replay path” not
  “install path.”
- **S03** → branded/styled export; plain md export already ships.
- **phases/README** router copy updated in this harden (was “signed receipt”).

### Cut

- Progressive “gorgeous at early paint” from S01 scope.
- Auto “dodged bullet” / disagreement as first-class card fields without a
  contract owner (`Contradiction_Pass` / `PlanAnalysis` not near-term).
- Implicit kill of the whole feature when S00 finds consensus runs.
- Bundling Mac Floor embed into first code slice.
- ~2-day budget claim until S00b closes.
- `receipt show` as verb candidate.
- LLM-written one-liners/headlines in v1.

### Must-specify (blocking)

- CLI verb `card show` + ContractRegistry + teaching surface + version bump.
- Render medium (HTML + tokens) + on-disk path.
- Seat-set rule shared with Floor; one-liner + team-call rules (ledger).
- Exact honesty string; reproduce elision N.
- `outputKind` hero mapping; run-status precondition.
- S00 measurement rubric (three story classes) + visual proof route.
## Growth Min review (done)

| | |
| --- | --- |
| **When** | 2026-07-25 · wall ~6m37s · readOnly |
| **Run** | `E900A4BC-9D7A-41CE-93F0-37F5206FACEC` |
| **Team** | `custom_growth_min_cursor_k3` — Kimi K3, Cursor Grok 4.5, Opus 5 (Cursor), ChatGPT 5.6 Sol (Cursor); lead Fable 5 (Cursor) |
| **Pre-commit** | `08ff41d7` (pending marker) |
| **Post-commit** | Growth reshape revision |

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

## Spec Review Min (done)

| | |
| --- | --- |
| **When** | 2026-07-25 · wall ~11m8s · readOnly |
| **Run** | `EC1DCCAF-BBFC-40DE-96C5-9467B8C333D1` |
| **Team** | `custom_spec_review_min_cursor_k3` — Kimi K3 (First Principles), Opus 5 Cursor (Proof Planner), Cursor Grok 4.5 (Scope Steward); lead Fable 5 Cursor (Spec Review Writer) |
| **Pre-commit** | `0451daa0` (pending marker) |
| **Post-commit** | this revision |

**Process note:** Scope Steward edited the packet during the review (rubric is
review-only). Founder disposition per lead: **keep the patch**, apply synthesis
fixes on top, commit once — pair with this conduct note so it doesn’t repeat.

**Verdict (Fabel synthesis):** Not ready for TRR-S01 code; ready to run
TRR-S00 today. Two-theses split sticks: S00 may kill growth packaging, not the
product card when seats agree. Biggest remaining gaps were mapper-honest field
owners (no dead `plan.markdown` fallback; Law-2 single-seat hoist; reproduce
elision), `outputKind` hero keying, contract-slice honesty (new verb bumps
`4.0.2`), design-authority route for HTML tokens, and proof design (substring
truth test + visual gate/waiver). Decision 2A: mechanical truncation in v1;
typed verdict fields are v2.

**Gems retained:** substring truth test; two kill axes; Blocker 6 rewrite;
`outputKind` hero chrome; CSS tokens as HTML source; no-canonical-result house
line; Floor seat-set anti-drift; reproduce elision; negative fixtures; local
demand counters for S03.

## Design taste — agents in color (done)

| | |
| --- | --- |
| **When** | 2026-07-25 · wall ~4m6s · readOnly |
| **Run** | `96DA941A-B1E7-42E8-BA98-93459D99D84E` |
| **Worker** | Opus 5 (Cursor) — design taste |
| **Stimulus** | OpenAI × Work Louder Agent Keys (“Your agents, in color”) + Lead Call Ready\|Partial + existing `production.md` status tokens |

**Verdict:** Steal glance-first state and Partial = “needs you.” Reject rainbow
RGB, per-vendor hues, hardware fetish, glow on a settled card. **Ready has no
hue** (calm ink); **Partial carries the one amber content event**. Seat color =
lifecycle status only; glyph = who. Card = zero glow/motion (glow marks live
board). Locked as §Design authority G1–G13.

**Founder corrections (same day):** (1) fixed 16:9 poster retired — content-
intrinsic scrollable report. (2) Layout driver is **readability/scanability**,
not virality (~90% private reading). (3) Must render **excellent on big
desktop and clean on mobile** — dual viewport, not mobile-only.
