# Team Run Receipt — gorgeous private report, deliberate share

Status: **Ready for Implementation** (entire authorized phase — TRR-S00,
S00b✓, S01, S01b, S01c, S03). Cut/unscheduled: S02 / S04 / S05.
Primary job = scannable, readable polished team **artifact** (like a great AI
chat response, with phosphor status). Not a viral poster.
Owner: AllnighterCore (artifact projector) + CLI first; Mac Factory Floor as
existing deep reader (not the artifact owner).
Updated: 2026-07-25 (full packet Ready — all authorized slices specified)
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
| **Branded export = TRR-S03 (authorized)** | md export already ships; styled HTML export is a Ready slice, demand-triggered after S01 |
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

**Out of S01:** progressive paint while seats fill — **TRR-S01c** (Ready;
Mac live preview only). Dry-run `seats[]` is not on `TeamRunJSON`; do not
invent a live artifact from dry-run alone. CLI `artifact show` stays
terminal-only forever under this packet.

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
- **Not replacing `alln floor show` / Factory Floor** with the team artifact.
- **Not Mac Floor embed in S01** — that is **TRR-S01b** (Ready, after S01).
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
| Polished team artifact HTML | **Missing — TRR-S01** (spec Ready) |
| CLI `artifact show` / `export` | **Missing — S01 / S03** (spec Ready) |
| Field ownership ledger | **Locked** — §Card field ledger + §Must-specify |
| Measured “do real runs have a story?” | **Missing — TRR-S00** (spec Ready; growth only) |
| Floor “Open artifact” | **Done — TRR-S01b** (2026-07-25) |
| Live progressive paint | **Missing — TRR-S01c** (spec Ready; Mac only) |
| Signed crypto verify / hosted share | Cut / unscheduled |

## Privacy laws (still bind)

1. **Private by default.** Local disk. No public URL unless user explicitly
   Shares (and Share is not v1).
2. **Signing and visibility are orthogonal** — when/if signing returns, it
   still never implies public.
3. **v1 share mode:** OS screenshot of the local artifact (or copy path).
   Styled file export is **TRR-S03**; hosted link remains unscheduled.
4. **Honesty string on every artifact:** exact
   `alln-attested multi-seat artifact · not vendor-signed` — not
   “Claude cryptographically signed this.”
5. **Artifact content is lean by construction** — question, one-liners, timings,
   call — so casual screenshots don’t dump full prompts/seat bodies. Full
   bodies stay on Factory Floor / `team result` / `floor show` (craft body on
   the artifact is intentional for reading; seat one-liners stay truncated).
6. **Reproduce-line elision.** `reproduceCommand` embeds the full prompt
   verbatim — printing it raw in the footer can violate lean privacy on
   every screenshot. Elide past **96** chars with a marked ellipsis + run id
   micro-line (§Must-specify). Hard cap the **question line** at 120; when
   `promptSource` is file/stdin or bodies were inlined via `@`, never dump the
   file into the artifact.
## Truth owner

- **Run truth:** existing `TeamRun` / `TeamRunJSON` (unchanged).
- **Team artifact document:** deterministic projection from run truth. Must
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

## Card field ledger (LOCKED — S01 law)

Every artifact field needs a `TeamRunJSON` (or constant) owner. No owner → not
on the artifact in S01.

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
## Authorized slices (Ready for Implementation)

Execution order (do not reorder without founder):

1. **TRR-S01** — core product (CLI artifact). May start immediately.
2. **TRR-S00** — growth measure. Does **not** block S01; run before claiming
   growth packaging / founder series success.
3. **TRR-S01b** — after S01 Works Test green.
4. **TRR-S01c** — after S01 Works Test green (and Live Team Board events already
   emit `workerAnswerDelta` / status — they do; see Live_Team_Board).
5. **TRR-S03** — after S01; ship when local demand counter ≥1 ask **or** founder
   requests (whichever first). Spec is Ready so implementers do not invent.
6. ~~S02 / S04 / S05~~ — cut / unscheduled (no work orders).

### Slice-order risks (named)

1. ~~S01 before S00b~~ — **cleared.**
2. **S01 bundles live paint** → forbidden; that is S01c only.
3. **Mac embed in S01** → forbidden; that is S01b only.
4. **Growth kill misread as product kill** → orphan CLI finish forever.
5. **Teaching drift** — must distinguish `artifact show` vs `floor show` vs
   `team result` vs `export` vs `continuity receipt`.

### Doc blockers

**None.** All Must-specify locks closed. ContractRegistry + teaching + version
bump land **inside** the S01 PR (budgeted work, not open design).

---

### TRR-S00b — Lock open specs (DONE)

| | |
| --- | --- |
| **Status** | Done 2026-07-25 |
| **Owner** | Docs only |
| **Done when** | §Must-specify closed; verb = `artifact` — **met** |

---

### TRR-S01 — Terminal HTML artifact + CLI (core)

| Field | Spec |
| --- | --- |
| **Status** | Done 2026-07-25 |
| **Truth owner** | `TeamRun` / `TeamRunJSON` (+ optional `lead-call` fence in Lead markdown). New code: `ArtifactProjector` (name may match repo convention) projecting to HTML under the run journal. |
| **Lie-prone layers** | HTML that invents seats/call/status; CLI that opens non-terminal runs; teaching that conflates artifact with Floor / continuity receipt / export |
| **CLI** | `alln artifact show <run-id\|latest> [--no-open] [--json]` — exit 0 + print absolute path to `artifact/index.html`; default open in OS browser; `--json` → path + run id + honesty string only (no HTML body). Fail closed `RUN_NOT_TERMINAL` for non-terminal. |
| **Contract** | Register `artifact.show` in `ContractRegistry`; bump `contractVersion` off pinned `4.0.2`; regen `docs/generated/alln/*`. |
| **Teaching** | Help topic `artifact`; search terms: report, card, receipt, team artifact → this command; deny teaching `receipt show` as this feature; note continuity `receipt` is unrelated. |
| **Model / package** | AllnighterCore projector + AllnighterEngine CLI command. Share seat-set helper with `FloorProjector` (anti-drift unit test). Design-system: add `WorkerChip` compact (+ dot pill) in `tokens`/`components` **before or with** this slice — no one-off CSS in the projector. |
| **Mac / iOS** | **None in S01.** No Floor button, no SwiftUI HTML webview required. |
| **Auth / privacy** | File stays under run journal (user home / Allnighter data); never uploaded; no third-party host. |
| **Non-goals (this slice)** | Live progressive paint; Floor embed; branded export path picker; signing; Buzz. |
| **Works Test** | Terminal multi-seat team run → `alln artifact show <id>` opens private HTML; Lead Call (or fallback call rules) + seats per ledger; honesty exact; reproduce elision; failed seats visible; substring truth test (fixture TeamRunJSON → HTML contains only declared strings); negative fixtures (non-terminal → `RUN_NOT_TERMINAL`); visual: layout-watcher or recorded waiver for desktop ≥1280 and mobile ≤430 + G13. |
| **User gesture** | After any terminal team run: `alln artifact show latest` |
| **Proof command** | See §Proof command |
| **Done when** | CLI Works Test green; ContractRegistry + generated docs + help topic shipped; G1–G13 honored; no Mac/iOS change required |

---

### TRR-S00 — Measure + hand-render (growth packaging)

| Field | Spec |
| --- | --- |
| **Status** | Ready for Implementation (growth thesis only — does not block S01) |
| **Truth owner** | Founder scorecard doc/notes (not product runtime). Hand HTML is throwaway; must not become the projector. |
| **Purpose** | Decide whether founder **growth series / packaging** is worth effort — **not** whether the product artifact ships. |
| **Method** | 1. Collect fixed **N = 20** recent multi-seat terminal hero-ish runs (`outputKind` plan/review preferred). 2. Score each against rubric classes (a) disagreement-with-a-call (b) consensus-with-a-call (c) lead-vs-seat reversal — count how many would make a stranger-worthy screenshot **for a growth series**. 3. Hand-build **3** HTML artifacts using design tokens (no projector code required) from the best stories. 4. Founder pass/fail: “would I post or show this.” |
| **Kill condition** | If fewer than **3**/20 score as stranger-worthy **for series** → kill growth packaging / series ambition; **keep S01 product path**. |
| **CLI / Mac / contract** | None. |
| **Works Test** | Scorecard exists with N=20 rows + 3 hand files linked; founder written disposition (kill growth packaging \| proceed with optional series). |
| **Done when** | Disposition recorded in this packet’s review log or a one-line addendum under this slice. |

---

### TRR-S01b — Mac Floor optional embed

| Field | Spec |
| --- | --- |
| **Status** | Done 2026-07-25 |
| **Truth owner** | Same `ArtifactProjector` as S01 — Floor must not re-implement HTML mapping. |
| **Lie-prone** | Floor inventing a second HTML layout; WebView loading a path Floor did not regenerate from current `TeamRun`. |
| **CLI** | Unchanged. Optional: `alln floor show` teaching cross-link “Open artifact: `alln artifact show <id>`”. |
| **Mac** | On Factory Floor for a **terminal** run: control **“Open artifact”** that (1) ensures `artifact/index.html` is regenerated via the shared projector (2) opens via `NSWorkspace` / default browser (same as CLI). Prefer open-in-browser over in-app WebKit unless GUI_Workflow later authorizes an in-app reader. |
| **iOS** | None (GUI §5 — no shared SwiftUI). |
| **Works Test** | Terminal run visible on Floor → Open artifact → same HTML bytes (or regenerable equivalent) as `alln artifact show --no-open` path for that run id. |
| **Done when** | Floor control ships; no duplicate field ledger in Mac target; Works Test green. |

---

### TRR-S01c — Progressive / live paint

| Field | Spec |
| --- | --- |
| **Status** | Ready for Implementation (after S01 green) |
| **Truth owner** | Live: `RunEvent` stream (`workerStatusChanged`, `workerAnswerDelta`) — same owners as Live_Team_Board. Settled: still `TeamRunJSON` via ArtifactProjector. |
| **Product** | While a team run is **running**, a live artifact preview may update seat chips (status + duration) and one-liner from answer deltas. **Settled card rules (G5 zero glow) do not apply to the live preview** — live may use board motion; on terminalization, rewrite via S01 projector (zero glow). |
| **CLI** | `alln artifact show` on non-terminal remains **fail closed** (`RUN_NOT_TERMINAL`). Live paint is **Mac-only** (or a future `artifact watch` — **not** authorized in this slice). Do not weaken the CLI terminal precondition. |
| **Mac** | Optional live panel or Floor-adjacent preview fed by existing board events; on run terminal → replace with settled artifact regenerate. |
| **Non-goals** | Inventing new RunEvent kinds; changing RunService; CLI live HTML. |
| **Works Test** | Start multi-seat run in Mac → live preview shows seat status transitions without inventing answers → on done, settled artifact matches S01 honesty rules. |
| **Done when** | Live preview uses board events only; CLI still refuses non-terminal; settled path unchanged. |

---

### TRR-S03 — Branded / styled export

| Field | Spec |
| --- | --- |
| **Status** | Done 2026-07-25 |
| **Truth owner** | Same ArtifactProjector HTML. Export = copy/regenerate to a **user-chosen path**, not a second layout. |
| **CLI** | `alln artifact export <run-id\|latest> --out <path>` — writes self-contained HTML (inline or sibling token CSS per implementer choice; must remain readable offline). Exit non-zero if run non-terminal. Does **not** replace `alln export --format md`. |
| **Contract** | Register `artifact.export`; teaching distinguishes `artifact export` (styled HTML) vs `export` (md/json). |
| **Mac** | Optional “Export artifact…” save panel calling the same Core export API. |
| **Demand gate** | Implement when founder asks **or** ≥1 real user ask is logged; spec is Ready so no redesign stall. |
| **Works Test** | `artifact export` → file opens offline; content matches `artifact show --no-open` body for same run; md `export` unchanged. |
| **Done when** | Command + teaching + one offline open proof. |

---

### Cut / unscheduled (no work orders)

| ID | Disposition |
| --- | --- |
| ~~TRR-S02~~ | Cut — crypto sign/verify. Honesty string + reproduce. “Certified” = future property. |
| ~~TRR-S04~~ / ~~S05~~ | Unscheduled — hosted link / Buzz helper. |

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
| Mac Floor embed | **TRR-S01b** (Ready) — same projector; Open artifact from Floor |
| Progressive paint | **TRR-S01c** (Ready) — Mac live preview only; CLI stays terminal-only |
| Branded export | **TRR-S03** (Ready) — `alln artifact export --out` |
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

**S00b:** **DONE** — Must-specify locked; verb = `artifact`.

**S01:** Terminal CLI team run → `alln artifact show` opens the artifact
without Mac app; private; reproduce elided; honesty exact; ledger/substring
honesty; truncation marked; failed seats visible; **desktop + mobile
scanability** passes; **G13** checks pass. Long bodies allowed.

**S00:** N=20 scorecard + 3 hand-renders + founder disposition on growth
packaging (does not gate S01).

**S01b:** Floor “Open artifact” → same regenerable HTML as CLI for that run.

**S01c:** Mac live preview tracks board events; on terminal, settled artifact
matches S01; CLI still `RUN_NOT_TERMINAL` while running.

**S03:** `alln artifact export --out` offline-readable; matches show body;
`alln export --format md` unchanged.

## Proof command

```text
alln team result <run-id> --json   # existing truth
alln floor show <run-id>           # existing deep Floor (not the artifact)
alln artifact show <run-id>        # team artifact (S01)
alln artifact show latest --no-open
alln artifact export <run-id> --out /tmp/team-artifact.html   # S03
```

## Done when (phase)

- ~~S00b~~ — **done.**
- **S01** — CLI-first users open a private team artifact for any terminal team
  run; privacy + honesty + reproduce elision; teaching distinguishes surfaces.
- **S00** — growth disposition recorded (kill packaging or proceed).
- **S01b** — Floor opens the same projector artifact.
- **S01c** — optional live Mac preview without weakening CLI terminal gate.
- **S03** — styled HTML export on demand, same projector.
- Buzz/Nostr/hosted / “certified” remain optional non-blockers (no slices).

## Open questions

**None.** Entire authorized phase is Ready for Implementation.

## Relationship to Buzz

Buzz is **not** required. Optional later room to *show* a card/receipt in an
attended thread. Do not marry privacy or signing to a private auth relay. No
numbered Buzz slice until the card exists and S00/S01 earned it.

## Impact ledger (Spec Review 2026-07-25)

### Keep

- Hero = polished scannable artifact (readability-first; virality secondary).
- Verification = `reproduceCommand`; cut crypto S02.
- Private by default; OS screenshot as v1 share path.
- S00 measure-before-renderer for **growth packaging only**.
- Cut/unschedule S02 / S04 / S05; **S03 authorized** as Ready export slice.
- One projector family; content-intrinsic HTML.
- Non-goals: no Buzz marriage, no RunService grammar change, no PDF.
- Buzz spike deferred behind artifact (`Buzz_Harness_Spike.md`).

### Change (applied — historical)

- S00 kill scope → growth only (§Two theses).
- S01 = terminal-only; live paint = S01c; Floor embed = S01b.
- S00b closed Must-specify; verb = **`artifact`** (not `card` / not
  `receipt show`).
- Surface ownership table; Law-2 call/one-liner rules; `outputKind` hero keying;
  reproduce elision; G1–G13 design locks; dual viewport.

### Cut

- Progressive paint from S01; Mac embed from S01; crypto verify; LLM one-liners;
  fixed 16:9 poster; `receipt show` verb.

### Must-specify

**Closed** — see §Must-specify (S00b — LOCKED). Stale “card show” lean from the
2026-07-25 Spec Review log is superseded by `artifact`.

## Finalization note (2026-07-25)

No further Spec Review required for this packet. Prior Growth Min, Spec Review
Min, Lead Call schema, and design-taste runs plus founder locks already closed
every authorized slice. Remaining work was **writing full Ready work orders**
for S00 / S01b / S01c / S03 (not re-judging product). Code starts at **TRR-S01**.

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
