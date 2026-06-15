# Design1 - The Image Council

Status: **BUILT (2026-06-15) — Core+Engine+Mac green (135 swift test + Mac app).** Capability gate passed: 3 image engines confirmed headless at $0.
Owner: Shared Core + Mac
Created: 2026-06-15
Updated: 2026-06-15
Depends on: 06 (`PanelSeat`, `StageOutput`), RB1 (`WorkflowPreset`, `CallPlan`, reuse), 05 (`Doctor`)

> **Dead and not coming back:** OCR and the HTML render pipeline. See Design0 §
> "What is DEAD." The unit is a **generated image**, not rendered HTML. There is no
> WKWebView, no content fixture, no pHash, no render contract.

## Why this is small

The council shape already exists (RB): fan out one prompt to a panel, capture each
worker's output, show it. Design1 changes exactly one thing — **the workers emit
images instead of text, and the board shows images.** Everything else (panel
selection, parallel fan-out, per-worker timeout/status, reuse, the `CallPlan`) is
reused. The only genuinely new engineering is **capturing an image output from a CLI**
and a **gallery board**.

## Goal

Design chip + an attached screenshot ("improve this") → fan out to image-capable
workers × design personas → each returns a finished design image → a board of options
side by side → the user picks → "more like this" iterates a seat.

## Non-Goals

- No HTML, no rendering, no OCR, no content fixture, no divergence/reroll engine.
- No build/implement step (Design2).
- No required vision critique (advisory only, Design2).

## Design

### Panel: image-capable workers × personas

- **Capability gate (`canGenerateImages`).** Doctor learns, per worker, whether its
  CLI can generate an image headlessly at $0. **Confirmed on-device (2026-06-15):**
  `grok` → Grok Imagine, **Antigravity CLI** → Gemini/Nano Banana (the successor to
  the legacy gemini-cli — use Antigravity), `codex` → ChatGPT image. **Claude Code does
  *not* generate images** — it is the build-side `canReadImages` implementer (Design2),
  not a design seat. A design seat binds only to an image-capable worker; the
  `CallPlan` shows the routing and honestly omits workers that can't. **The image
  probe is a separate, quota-aware check** (a tiny test generation, opt-in / "verify
  image gen" button) — it is **never folded into everyday text Doctor**, so normal
  health checks don't burn image quota.
- **Personas** are short editable style directions (Design0): `minimal`, `bold`,
  `editorial`, `on_brand`. A design panel is **seats = (image worker × persona)**,
  spread for range. Default 3–4 seats. A worker may fill several seats (different
  personas) — self-fusion, exactly like RB.
- **Range** comes from engines × personas. No automated divergence measurement; if
  options look too alike, the user hits **"more / re-roll."**

### Driver capability: capture an image output (the one new primitive — and the riskiest slice)

Today drivers capture **stdout text** or an **output file** (`02_Worker_Drivers`).
The on-device gate (Design0, 2026-06-15) corrected the key assumption: **image
generation is an agentic *tool call* triggered by the prompt, not an `--out` flag.**
All three confirmed engines (Grok, Antigravity/Gemini, Codex):

- run through their **headless agent entry** behind an **auto-approve** flag
  (`grok -p … --yolo`, `agy --print … --dangerously-skip-permissions`,
  `codex exec -C <runDir> --skip-git-repo-check …`);
- generate via an internal `image_gen` tool and **write a local file (PNG or JPEG)** —
  **never base64, never a URL**;
- **report the path in stdout** (Grok: `.text` of `--output-format json`; Antigravity:
  a markdown `![](abs/path.png)`; Codex: plain path).

So the destination is controlled **via the prompt**, with a stdout-path fallback:

```jsonc
// additive to DriverManifest — present only on image-capable workers
"imageGen": {
  "entry":         ["-p", "{{prompt}}", "--yolo", "--output-format", "json", "--cwd", "{{runDir}}"],
  "autoApprove":   "--yolo",                 // | "--dangerously-skip-permissions" | "--skip-git-repo-check"
  "promptWrap":    "Generate an image: {{designPrompt}}. Save the final image to {{imageOut}} and reply with the absolute path only.",
  "arrival":       "promptDirected",         // grok/codex honor an explicit save path; antigravity = "stdoutPath"
  "stdoutPathRegex": "…",                    // fallback / antigravity: extract the reported path and copy
  "sessionIdRegex":  "…",                    // capture for "more like this" (resume + image_edit)
  "format":        "png|jpeg",
  "timeoutMs":     600000
}
```

Per engine: **Grok & Codex honor an explicit `{{imageOut}}` save path** (most
reliable). **Antigravity writes to an opaque artifact dir**
(`~/.gemini/antigravity-cli/brain/<session>/<name>.png`) and embeds the path in
stdout — so we **parse the path and copy** into the run folder.

**Normalization is mandatory:** whatever arrives (a file at our path, or a path parsed
from stdout) is copied to a **validated local `option_<seatId>.png|jpg`** (PNG/JPEG
magic bytes + non-zero size) before it reaches `board.json`. No URLs, no base64 in
practice. A capture that can't be normalized → **failed seat** (gray tile + reason),
never a broken board. Keep this **thin and per-driver**; it is the only new contract.

### The design prompt (kept dumb)

Each seat is dispatched the **attached screenshot** (as a file the model reads) +
**"improve this"** + the **persona direction** + the **target shape**. Two short,
honest constraints earn their place (no fixture, no structural cage):

- **Preserve the screen.** "Same screen and same information architecture — keep the
  sections, nav items, and content; change **visual style only**." One line that stops
  seats from drifting into *different screens* (worst for greenfield), so the board
  compares **taste**, not content.
- **Pin the shape.** Append an explicit aspect/shape directive ("vertical mobile
  layout" / "wide desktop layout") so engines don't return random aspect ratios that
  break the identical-scale grid.

Greenfield (no screenshot) sends the text prompt + persona + target shape + the same
two constraints.

### Target shape (light, not a contract)

- **Screenshot attached** → infer mobile/desktop from its pixel dimensions (aspect
  ratio < ~0.6 → mobile, > ~1.8 → desktop, else ask); show it as an **editable chip**
  the user can flip. No deep image analysis — this is arithmetic, not the dead render
  contract.
- **No screenshot** → default from the prompt archetype; if genuinely ambiguous, ask
  **one** quick choice (mobile / desktop). That's the whole "clarify" story.

### The board (the hero view)

`board.json` = ordered options `{ seatId, engine, persona, imagePath }`. The board is
the **first truth surface** — no AI verdict precedes it.

- **Progressive reveal:** placeholder tiles at identical size appear immediately; each
  swaps to its image as the seat finishes (like RB's streaming panel). Tiles use
  **fixed aspect-ratio containers** (from the target shape) with `object-fit: cover`,
  so a stray engine aspect ratio can't make the grid reflow.
- **Identical scale; persona + engine badge** on each tile (and a "same engine,
  different persona" hint when one worker fills several seats — so the user reads
  *where the range comes from*). Fullscreen loads the full-res original PNG.
- **Fullscreen** (←/→ to flip) and **A/B** (two side by side). For redesigns, A/B and
  fullscreen offer a **before/after toggle** against the attached `screenshot.png` —
  the dopamine shot that validates "improve this." (Cheap; reuses the attached image.)
- **Palette swatches** under each tile — top ~5 dominant colors via native Core Image
  color quantization (local, $0, no model). Lets the user read each option's color
  system at a glance. (Cheap delight; pixel stats, not OCR.)
- **Pick this** → a **UI action that appends `chosen_option.json` to `run.json`** (one
  truth path; logged for future taste memory).
- **"More like this"** on any tile → **resume that seat's session and ask for a
  variant** (Grok `--resume <sessionId>` → `image_edit`; Antigravity `-c`; Codex
  resume) with a tightened push ("same direction, bolder" / "more whitespace"), so the
  result is a real *variation*, not a fresh random layout. The seat's `sessionId`
  (captured from its gen run) is the handle. If resume isn't available, fall back to a
  text re-prompt that references the prior image. RB1 `reuseKey`; other tiles untouched.
- **Failed seat** (engine error / un-normalizable output) → a gray tile with the
  reason; the board is usable with N−1 options (partial beats blocked, RB law).

### Reuse / resume

- **"More like this"** and persona edits re-run **one** seat. Changing the screenshot
  or the base prompt invalidates the board (content-addressed `reuseKey` over
  `{screenshot, prompt, persona, targetShape}`).
- A run stopped mid-fan-out keeps completed options; re-running continues from the
  first incomplete seat.

### Engine/spine wiring (contract-first)

Additive only — do **not** overload RB's text stages:

- New `StagePurpose` cases: `design_fanout` (fanout that captures images), `board`
  (local view stage).
- New `StagePayload.board(BoardPayload)`; new `Doctor` flag `canGenerateImages`.
- Design runs are a **parallel preset** with no Markdown member answers — the unit is
  the image, not `JudgeAnalysis`.

Land these in `AllnighterCore` with Codable round-trip + fixtures before any UI.

## Ordered Slices

- [ ] D1-S01 — Core models: `DesignRequest`, `BoardPayload`, `chosen_option.json`,
  `StagePurpose.design_fanout`/`.board`; Codable round-trip + fixtures.
- [ ] D1-S02 — Doctor `canGenerateImages` probe per worker: **separate, quota-aware,
  opt-in** (tiny test gen; validate magic bytes + non-zero size); surfaced in Doctor
  UI + `CallPlan` routing. Not part of everyday text Doctor.
- [ ] D1-S03 — Driver manifest `imageGen` capability (additive): agentic entry +
  auto-approve flag + **prompt-directed save** (`{{imageOut}}`) with **stdout-path
  parse + copy** fallback (Antigravity's opaque dir) → validated local
  `option_<seatId>.png|jpg`; capture `sessionId` for "more like this". Ship the three
  confirmed manifests (grok / agy / codex) from the gate.
- [ ] D1-S04 — Persona style-direction `PromptProfile`s (the four in Design0;
  editable) + the dumb design-prompt builder (screenshot file + "improve this" +
  persona + target shape + the **preserve-the-screen** and **pin-the-shape**
  constraints).
- [ ] D1-S05 — Screenshot attach in the composer (drag/drop + `NSOpenPanel`/
  `fileImporter`, image types only, thumbnail preview, remove) + the target-shape chip
  (aspect-ratio inference, editable, one quick choice for greenfield).
- [ ] D1-S06 — `design_fanout` stage: parallel image fan-out over image-capable seats,
  per-seat timeout/status, normalized image capture; `CallPlan` shows generation count
  + per-seat engine + quota note.
- [ ] D1-S07 — The board UI: progressive reveal, fixed-aspect identical-scale grid,
  persona/engine badges, fullscreen + A/B with before/after toggle, palette swatches,
  "pick this" (append `chosen_option.json`), "more like this" (img2img), failed tiles.
- [ ] D1-S08 — `design_board` preset + reuse/resume + `bundle.md` includes the board.

## Works Test

```text
Pick the Design chip. Attach a screenshot of a cluttered profile page; type
"make this feel premium and clean."
-> the target-shape chip reads "mobile" from the screenshot dimensions; one tap could
   flip it to desktop.
-> 3-4 seats fan out across image-capable engines × personas (minimal / bold /
   editorial / on_brand). The CallPlan showed "4 image generations · grok-imagine,
   gemini" before commit.
-> the board fills progressively; four finished design images sit side by side at the
   same scale, each badged with its engine + persona.
-> open the bold option fullscreen, flip ←/→ through the others; toggle before/after
   against the original screenshot; A/B the two you like; palette swatches show each
   one's color system.
-> click "more like this" on the minimal option: that one seat regenerates via
   image-to-image (its own image as reference, "bolder") into a real variant; the other
   three tiles are untouched.
-> pick the minimal variant; chosen_option.json is appended to run.json.
Force one engine to return a broken/URL-only output that can't be normalized: its tile
is gray with the reason; the other three remain fully usable.
```

## Exit Gates

- [ ] Design seats bind only to `canGenerateImages` workers; routing is shown in the
  `CallPlan`; non-capable workers are omitted honestly.
- [ ] Workers emit **images**; the engine **normalizes** any output (file / URL /
  base64) to a validated local `option_<seatId>.png`. No HTML, no render step, no OCR
  anywhere.
- [ ] The board reveals progressively at identical (fixed-aspect) scale, supports
  fullscreen/A-B + before/after, palette swatches, "pick this", and "more like this"
  (img2img one-seat reuse), and degrades on a failed/un-normalizable seat.
- [ ] No AI verdict precedes the board; `chosen_option.json` is appended to `run.json`
  on pick.
- [ ] `run.json` is truth; artifacts derived; reuse re-runs one seat, screenshot/prompt
  change invalidates the board.
- [ ] Activation Gate passed and image-capable CLIs recorded.
- [ ] `swift test` + app suite green via `scripts/check.sh`.

## Closeout

Design1 is lovable alone: attach a screenshot, get a board of real design options,
pick the one you love. Activate Design2 to turn that pick into code.
