# Team Run Receipt — gorgeous private report, deliberate share

Status: **Draft feature packet — visual grammar G1–G13** (content-intrinsic
receipt; fixed 16:9 poster **retired** 2026-07-25). Not Ready for
Implementation until §Blockers before TRR-S01 are closed. Near-term:
screenshotable **decision receipt** (Lead Call + seat chips in phosphor
status color); signing/hosted/Buzz cut or unscheduled.
Owner: AllnighterCore (receipt projector) + CLI first; Mac Factory Floor as
existing deep reader (not the card owner).
Updated: 2026-07-25 (G8 corrected — scrollable report, not cinema frame)
Companions:
- Mac deep reader: `FactoryFloorView` / `docs/phases/Live_Team_Board.md`
  (Factory Floor = full team result; thread keeps a compact cockpit receipt →
  Open Floor; **decision card is a third surface** — see §Surface ownership)
- **Lead Call** (universal Lead / `.planWriter` envelope + `lead-call` fenced
  JSON — card headline/leans/status): `SkillCatalog.leadCallEnvelope`;
  Spec Review closeout: `docs/phases/Spec_Review.md` §1
- Design authority for beauty-first HTML: `docs/design-system/production.md`
  + `docs/design-system/tokens/*.css` (CSS tokens are canonical; see
  §Design authority) + `docs/gui/GUI_Workflow.md`
- Growth note: `docs/marketing/Growth_Playbook.md` §Shareable run receipts +
  §2 receipt series
- Adjacent Buzz spike (optional room test **after** card exists; firm/plural-
  member framing retired):  
  `docs/phases/Buzz_Harness_Spike.md` +  
  `docs/strategy/Buzz_And_The_Judgment_Layer.md`
- Disagreement / co-attribution fields (NOT AUTHORIZED): `Contradiction_Pass.md`
  — do not treat as a near-term card schema source
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
| **Measure before renderer (TRR-S00)** | If real runs lack disagreement / dodged-bullet stories, **kill the growth thesis** before a sprint — not the product card (see §Two theses) |
| **Cut S02 / S04 / S05 as numbered slices** | Signing infra, hosted ACL links, Buzz/Slack — gravitational pull without near-term pull |
| **Defer file export (old S03)** | Build when an outsider asks for the file; founder screenshots locally until then |
| **Hero-optimize Spec Review + Growth cards first** | “One report family” stays as one projector; equal visual priority across every team kills the post |

## Two theses (do not conflate)

| Thesis | Claim | Kill condition |
| --- | --- | --- |
| **Growth** | Timeline posts of disagreement / changed-decision cards drive awareness | S00 finds fewer than 1 stranger-worthy story in last N multi-seat hero runs → **kill growth series / share ambition**, keep measuring later |
| **Product** | CLI users deserve a local felt-finish poster after a team run, even when seats agree | Only kill if hand-cards feel worthless as finish (not “no drama”) |

**Ruling (Spec Review):** TRR-S00’s “kill if 4-of-4 agree” overclaims when read as
killing the feature. Seats agreeing is still a legitimate team outcome; a lean
local card remains product-valuable. S00 may kill **growth packaging and
sprint priority**, not the private decision-card product path.

## Product value (revised)

- **Felt finish for team runs.** Card via CLI open path — recognition, not
  novelty (“this is what I’ve been screenshotting tmux for”).
- **Founder content engine now.** Hand-then-auto cards for the X receipt
  series; compounds before launch — **only if S00 growth gate is green**.
- **Later: user share without privacy foot-guns.** Deliberate only; private
  default; card is structurally lean (no full prompts/bodies above the fold).
- **Replay path in the proof line.** Footer prints `reproduceCommand` (replays
  a run for someone who already has alln + vendor CLIs — it does **not**
  install Allnighter).

Expected lift (revised): large on “this feels finished” **if** cards are legible;
**binary** on share/retention depending on timeline-native story artifacts;
~zero on the judgment engine. “Medium on retention/share” from the first draft
was overstated.

## Surface ownership (resolves Floor / thread collision)

Three surfaces; one run truth. Do not call all three “the receipt” in teaching
copy without a qualifier.

| Surface | Owns | Does not own |
| --- | --- | --- |
| **Run truth** | `TeamRun` / `TeamRunJSON` | Presentation |
| **Factory Floor** (`FactoryFloorView`, `alln floor show`) | Full inspectable result — cast rail, full seat bodies, synthesis | Screenshot poster; viral above-the-fold |
| **Thread compact card** (Live Team Board terminal) | Live cockpit + counts + **Open Floor** | Full bodies; decision-card layout |
| **Decision card** (this packet) | Lean poster projection for OS screenshot / founder series | New run facts; Floor replacement |
| **`alln team result`** | Terminal structured truth dump | Gorgeous poster |
| **`alln export <id> --format md`** | Shipped portable markdown (already in run `nextActions`) | Branded/styled decision-card export (old S03 → re-scoped) |
| **`alln spec …` summary paths** | Spec-oriented projections where they exist | Decision-card layout |

Companions stay authoritative: Live_Team_Board §Done When — terminal thread
keeps compact receipt → Floor. This packet adds a **CLI-first poster**, not a
second Floor and not a richer thread dump.
## Trusted workflow slice (v1 — terminal only)

```text
alln run … completes (terminal TeamRunJSON exists)
  -> DecisionCard projector derives lean fields from TeamRunJSON only
  -> CLI open verb writes/opens local card (private; no network)
  -> card shows: question line, seat chips + sourced one-liners + timings,
     team call line, honesty string, reproduceCommand
  -> user screenshots with the OS (founder series; later anyone)
  -> (later, only if asked) deliberate file export or private hosted link
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
- **Not replacing `alln floor show` / Factory Floor** with the decision card.
- **Not Mac Floor above-the-fold embed in the first code slice.**

## Current state

| Piece | Today |
| --- | --- |
| Multi-seat run truth | Built — `TeamRun` / `TeamRunJSON`, `alln team result` |
| `reproduceCommand` on runs | Built — `teamRun.reproduceCommand` |
| Seat timings / model ids | Built — `workers[]` + `workerAnswers[]` |
| Gorgeous Mac Factory Floor | Built — deep reader (`FactoryFloorView`) |
| Inspectable Floor CLI | Built — `alln floor show` (different surface) |
| Screenshot-native decision card | **Missing** |
| CLI decision-card open path | **Missing** (verb still open — §Must-specify) |
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
| **TRR-S00** | Measure + hand-render | Fixed N (~20) multi-seat **hero** runs; written rubric counts **(a)** disagreement stories, **(b)** consensus-with-a-call, **(c)** lead-vs-seat reversals (the Growth Min packet itself was (c) — lead overruling seats). Named judge; raw counts recorded; per-team-type base rates appended to this packet. Hand-build ~3 cards from real JSON. **Growth-axis gate only.** Note: Growth Playbook §2 is also overnight-relay-shaped — record which artifact class S00 measured so a red result isn’t over-read. Product path continues even if growth kills. |
| **TRR-S00b** | Lock open specs (doc-only) | Close §Must-specify **including a drafted `ContractRegistry` entry** (so S01 doesn’t discover the version cascade mid-flight). **No renderer code.** |
| **TRR-S01** | Terminal decision card + CLI open | Projector + open verb from terminal `TeamRunJSON` only; fields per ledger; substring truth test + negative fixtures land **with** the projector; visual proof route decided (gate extension or recorded waiver). OS-screenshotable; private; reproduce elision + honesty present. **No early-paint / live fill.** |
| **TRR-S01b** | (later) Mac Floor optional above-fold | Same projector embedded or linked from Floor — only after S01 CLI WOW; shared projector mandatory. |
| **TRR-S01c** | (later) Progressive paint | Seats appear as answers land — needs live/status contract; not S01. |
| **TRR-S03** | (later) **Branded/styled** export | Markdown export already ships (`alln export --format md`). S03 = branded decision-card file/HTML export — only if demand (local journal counters or outsider ask). |
| ~~TRR-S02~~ | **Cut** — crypto sign/verify | Replaced by honesty string + reproduce line. |
| ~~TRR-S04~~ | **Unscheduled** — hosted private link | |
| ~~TRR-S05~~ | **Unscheduled** — Buzz/Slack post helper | One line under Relationship to Buzz is enough. |

### Slice-order risks (named)

1. **S01 before S00b** → invents paraphrase fields and a second JSON shape.
2. **S01 bundles live paint** → couples to Live Team Board streaming gaps.
3. **Mac embed in S01** → GUI/design drag before CLI Works Test.
4. **Growth kill misread as product kill** → orphan CLI finish forever.
5. **`team open` without teaching sweep** → collisions with `floor show` /
   `team result` (Feature Workflow teaching-surface rule).

## Blockers before TRR-S01 code

1. TRR-S00 executed with written rubric + evidence (growth gate recorded).
2. TRR-S00b closes every §Must-specify row (or explicitly waives with owner).
3. Card field ledger has no blank “Must-specify” rows left for shipped fields.
4. CLI verb + ContractRegistry args/exit codes/errors drafted (CLI-first rule)
   — including expected `contractVersion` bump off pinned `4.0.2` and regen of
   `docs/generated/alln/*`.
5. Teaching surface plan: help topic + search terms; distinguish card vs
   `floor show` vs `team result` vs `export`.
6. **No new *run* schema** — projection only. A new CLI verb **is** a contract
   slice (registry, version bump, generated artifacts); budget it — do not deny
   it under “projection only.”
7. Design authority route named (§Design authority); visual proof route named
   (§Proof design).
8. Run-status precondition defined (running / failed / cancelled / parked →
   error code; `RUN_NOT_TERMINAL` prior art).

## Must-specify (S00b checklist)

| Item | Options / default lean | Status |
| --- | --- | --- |
| CLI verb | Prefer **`alln card show <run-id\|latest>`**. **Strike `receipt show`** — collides with shipped `alln continuity receipt`. Avoid `team open` (Floor/`team result` teaching collision) | Open — lean `card show` |
| Render medium | **HTML** report consuming design tokens; content-intrinsic height; G1–G13 | **Locked** — §Design authority (16:9 fixed poster **retired**) |
| On-disk path | Derived cache under support/run journal vs beside journal | Open — must be private, deterministic, regenerable |
| Seat one-liner | First line truncate + mark; Law-2 single-seat hoist rule | Lean locked in ledger |
| Team call | First ~2 lines of `answer.markdown`; no-canonical-result house line | Lean locked in ledger |
| Honesty string exact text | e.g. `alln-attested multi-seat receipt · not vendor-signed` | Open — lock string |
| Hero keying | `teamRun.outputKind` (+ lane), not exact preset-id allowlist | Open — verify duplicate preserves `outputKind` |
| Seat-set rule | Shared with `FloorProjector`; anti-drift test | Open — write the filter |
| Prompt / reproduce caps | Question hard cap; reproduce elision rule (§Privacy 6) | Open — pick N |
| Run-status errors | Behavior + error code when non-terminal | Open |
| ContractRegistry draft | Flags, exit codes, errors, version bump plan | Open — draft in S00b |
| Non-hero teams | Same projector, simpler chrome; no equal visual spend | Locked intent |
| Mac Floor embed | Deferred to S01b | Locked |

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

**G5 — Glow is the live/settled bit.** Live board may glow; **the card carries
zero glow and zero animation.** Same chips; one bit of difference. Screenshots
freeze motion — animated grammar is worthless in the viral unit.

**G6 — Amber alive glow is singular per live surface.** Exactly one mutating
worker → glow on that worker; parallel research → glow on the board’s live
mark, **not** every running chip (no amber wallpaper).

**G7 — Vendor identity is monochrome.** Glyph → `--ink-100`; model id mono
faint. **Glyph says who; color says state.** Never both. No Anthropic/OpenAI
brand hues (collides with phosphor amber).

**G8 — Content-intrinsic report, not a fixed poster.** The receipt **grows with
the run** — Spec Review Max with many leans, a tiny feature harden, a Design
board with three proposals. Fixed 16:9 / no-scroll was an overfit to X
timeline crops and is **retired** (founder gut 2026-07-25). Rules:

- Primary artifact = **scrollable HTML report** (comfortable reading width,
  midnight field). Zones expand; marked ellipsis only where the field ledger
  already requires hard caps (question line, seat one-liner) — not to fake a
  poster height.
- Craft bodies that need space (three design directions, long recommendation
  tables, impact ledgers) get space. Do not truncate craft truth to fit a frame.
- Optional later: a **share crop** / OG image that freezes the **above-the-fold
  band** (verdict + call + seat rhythm) for timelines — a derivative, never the
  only view. v1 share = OS screenshot of whatever height the report actually is
  (or scroll-shot); do not force users into a cinema frame.

**G9 — Above-the-fold ladder (order is load-bearing; height is not).** First
viewport / share crop targets: Verdict + team line → the call → what changed →
top leans (≤3 on the fold; full list scrolls) → seat chips. Deeper craft body
and remaining leans continue below. A stranger scrolling a timeline may only
see the fold — the **reader** who opened the receipt gets the whole run.

**G10 — Sentiment is not status.** “What changed” and leans are **ink only** —
no red/green delta drama. Status hues reserved for status.

**G11 — Deterministic seat order.** `workers[]` declaration order — identical
to live board / `FloorProjector` seat-set helper. Never sort by finish time.
Lead distinguished structurally (label + border), not by amber fill.

**G12 — Surface.** Solid `--bg-base` field, body `--bg-raised`, `--radius-lg`,
`--border-subtle`, `--shadow-sm`. No gradient wash. No light-mode share
variant (midnight in a white timeline **is** recognition). No emoji. Static
render (no GIF/MP4 export in v1).

**G13 — Enforceable check (ship with projector).** Fail the gate if the
rendered receipt contains `animation:` / `@keyframes` / `--glow-*`, any hex
literal outside the token layer, or more than one amber content event above
the fold. Deterministic — not agent judgment. **Do not** fail on document
height.

### Above-the-fold glance test (Works Test visual bar)

Grade the **first screen / share crop band** (not a forced 16:9 of the whole
doc), as a ~500px-wide thumbnail, **and again in grayscale**. Must survive:

1. Warm patch present or absent (needs-you vs not) before any word is read  
2. **The call** — largest type (`--ink-50`)  
3. Seat-row rhythm — N aligned glyphs as a team (prefer single row; wrap only
   if seat count demands it)  
4. A red seat if one exists  
5. The mark (small amber crescent)

Not required at first glance: full lean table, craft body, reproduce, run id,
timings, honesty, Why column (those scroll or sit in footer micro-type).

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
  name a `layout-watcher` PASS on the **above-the-fold band** (and at least one
  long-body fixture: Spec Review Max–shaped or Design three-proposal) before
  first ship — plus G13 deterministic checks. Do **not** require a fixed 16:9
  of the entire document.
- **Named blocked proofs (honest):** growth lift unfalsifiable pre-launch;
  “gorgeous” has no automated oracle; no CI end-to-end multi-seat run
  (Keychain/sandbox); screenshot fidelity across OS versions.

## Works Test

**S00:** Fixed-N counts for disagreement / consensus-with-a-call /
lead-vs-seat + ≥1 hand-rendered card shown to founder — **or** explicit
growth-thesis kill with evidence. Product path not auto-killed. Append base
rates to this packet.

**S00b:** Every Must-specify row closed or waived in this packet (commit),
including ContractRegistry draft.

**S01:** Terminal CLI team run → `card show` opens the card without Mac app;
OS screenshot is postable; no public URL; reproduce line present (elided);
honesty string exact; every visible field maps to ledger / substring truth
test; truncation marked; failed seats stay visible as failed; visual proof
route satisfied or waived; **above-the-fold glance test** (§Design authority)
passes; **G13** deterministic checks pass (no glow/animation/extra amber).
Document height may grow — do not fail long Spec Review / Design bodies.

**S01b+ / S03+:** waived until scheduled.
## Proof command

```text
alln team result <run-id> --json   # existing truth
alln floor show <run-id>           # existing deep Floor (not the card)
alln card show <run-id>            # decision card (S01) — verb pending S00b lock
```

## Done when (near-term)

- S00 growth gate recorded (proceed or kill growth packaging).
- S00b must-specify closed (including contract draft).
- CLI-first users can open a private decision card for hero team runs
  (Spec Review + Growth first visually via `outputKind` hints).
- Privacy default holds; reproduce elision holds; no crypto-verify theater.
- Factory Floor, thread compact card, and decision card do not drift into
  three content truths — one projector family over `TeamRunJSON` + shared
  seat-set helper with Floor.
- **Local demand signal:** journal counters for card-open / export-request
  (privacy forbids network analytics, not local counts) schedule S01b/S03.
- Buzz/Nostr/hosted link remain optional non-blockers.

## Open questions (surviving — owned by S00b)

1. Exact CLI verb — lean `card show` (**not** `receipt show`).
2. Card HTML on-disk path (journal vs derived cache).
3. Whether Mac Factory Floor embeds the same card above the fold (S01b).
4. ~~Key management~~ — **retired with S02.**
5. Branded export redaction (when S03 exists); card itself stays lean.
6. Exact honesty string + `outputKind` hero mapping table.
7. Reproduce elision N / replay-pointer shape.
8. Visual proof: gate extension vs waiver id.
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

**Founder correction (same day):** fixed **16:9 no-scroll poster (old G8)
retired**. Receipt is content-intrinsic / scrollable; optional share crop of
the above-the-fold band only. Long Spec Review / Design three-proposal bodies
must not be chopped to fit a cinema frame.
